#!/bin/bash

#######################################
# Docker 容器启动脚本
# 功能：检查依赖、安装项目特定依赖并运行项目
# 基于 bot.sh 优化，适配 Docker 环境
#######################################

set -e  # 遇到错误立即退出

# 国内多镜像源定义（默认阿里云，备选字节跳动火山引擎源、清华源）
export PIP_INDEX_URL="${PIP_INDEX_URL:-https://mirrors.aliyun.com/pypi/simple/}"
export PIP_EXTRA_INDEX_URL="${PIP_EXTRA_INDEX_URL:-https://mirrors.volces.com/pypi/simple/ https://pypi.tuna.tsinghua.edu.cn/simple/}"
export UV_INDEX_URL="${UV_INDEX_URL:-$PIP_INDEX_URL}"
export UV_EXTRA_INDEX_URL="${UV_EXTRA_INDEX_URL:-$PIP_EXTRA_INDEX_URL}"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# 记录启动时间
START_TIME=$(date +%s)

echo ""
echo "=========================================="
echo "   💖 GsCore (早柚核心) 容器环境启动"
echo "   应用标识: ${APP_NAME:-GsCore} (${APP_KEY:-gscore})"
echo "   基础镜像: ${DOCKER_IMAGE:-python:3.13-slim}"
echo "   Python:   $(python --version 2>&1 | awk '{print $2}')"
echo "   工作目录: $(pwd)"
echo "=========================================="
echo ""

#######################################
# 0. 检查并安装系统底层基础依赖 (git, C 动态链接库)
# 适配公版 python:slim 镜像无 git 与缺失 OpenGL/XCB 动态库的情况
#######################################
check_system_dependencies() {
    log_info "检查系统基础依赖 (git, 图像与图形 C 运行库)..."
    local missing_pkgs=""

    # 1. 检查 git (GsCore 核心更新、插件拉取与版本识别必需)
    if ! command -v git &> /dev/null; then
        missing_pkgs="$missing_pkgs git"
    fi

    # 2. 检查 OpenCV/图像处理所需的系统 C 动态链接库 (使用 Python ctypes 跨架构精准检测)
    if ! python -c "import ctypes; ctypes.CDLL('libxcb.so.1')" &> /dev/null; then
        missing_pkgs="$missing_pkgs libxcb1"
    fi
    if ! python -c "import ctypes; ctypes.CDLL('libGL.so.1')" &> /dev/null; then
        missing_pkgs="$missing_pkgs libgl1"
    fi
    if ! python -c "import ctypes; ctypes.CDLL('libglib-2.0.so.0')" &> /dev/null; then
        # Debian 13+ (trixie/sid) 及 Ubuntu 24.04+ (noble) 因 64 位 time_t 迁移更名为 libglib2.0-0t64
        if grep -qE "trixie|sid|noble|forky" /etc/os-release 2>/dev/null; then
            missing_pkgs="$missing_pkgs libglib2.0-0t64"
        else
            missing_pkgs="$missing_pkgs libglib2.0-0"
        fi
    fi

    if [ -n "$missing_pkgs" ]; then
        log_warn "检测到公版 slim 镜像缺少以下系统运行依赖:$missing_pkgs"
        log_info "正在自动配置国内源并快速安装系统依赖..."
        
        # 修复 /tmp 目录权限，防止 _apt 用户创建临时文件验签时报 Permission denied (13)
        mkdir -p /tmp 2>/dev/null || true
        chmod 1777 /tmp 2>/dev/null || true

        # 配置 APT 沙盒用户为 root，避免 Docker 容器环境下 _apt 降权沙盒引发权限异常
        mkdir -p /etc/apt/apt.conf.d 2>/dev/null || true
        echo 'APT::Sandbox::User "root";' > /etc/apt/apt.conf.d/99sandbox 2>/dev/null || true

        # 换源工具函数：支持 Debian 12/13 debian.sources 及旧版 sources.list，支持在多镜像源间平滑切换
        switch_apt_mirror() {
            local mirror_host="$1"
            if [ -f /etc/apt/sources.list.d/debian.sources ]; then
                sed -i -E "s#(deb\.debian\.org|mirrors\.[a-zA-Z0-9.-]+)#${mirror_host}#g" /etc/apt/sources.list.d/debian.sources 2>/dev/null || true
            fi
            if [ -f /etc/apt/sources.list ]; then
                sed -i -E "s#(deb\.debian\.org|mirrors\.[a-zA-Z0-9.-]+)#${mirror_host}#g" /etc/apt/sources.list 2>/dev/null || true
            fi
        }

        export DEBIAN_FRONTEND=noninteractive

        # 优先使用阿里源，若失败则自动切换至字节跳动 (火山引擎) 源，再失败回退至清华源
        log_info "配置 APT 阿里源 (mirrors.aliyun.com)..."
        switch_apt_mirror "mirrors.aliyun.com"

        if ! apt-get -o APT::Sandbox::User=root update -qq 2>&1; then
            log_warn "阿里 APT 源更新未成功，正在自动切换至 [字节跳动 (火山引擎) 源] (mirrors.volces.com)..."
            switch_apt_mirror "mirrors.volces.com"
            if ! apt-get -o APT::Sandbox::User=root update -qq 2>&1; then
                log_warn "字节跳动 APT 源更新未成功，正在切换至 [清华大学源] (mirrors.tuna.tsinghua.edu.cn)..."
                switch_apt_mirror "mirrors.tuna.tsinghua.edu.cn"
                apt-get -o APT::Sandbox::User=root update -qq 2>&1 || true
            fi
        fi

        # 优先批量安装
        if apt-get -o APT::Sandbox::User=root install -y --no-install-recommends $missing_pkgs 2>&1; then
            rm -rf /var/lib/apt/lists/*
            ldconfig 2>/dev/null || true
            log_info "系统基础依赖补齐完成 ✓ ($missing_pkgs)"
        else
            log_warn "批量安装依赖遇到异常，尝试逐个安装与容错回退..."
            for pkg in $missing_pkgs; do
                if [[ "$pkg" == "libglib2.0-0" ]]; then
                    apt-get -o APT::Sandbox::User=root install -y --no-install-recommends libglib2.0-0 2>/dev/null || \
                    apt-get -o APT::Sandbox::User=root install -y --no-install-recommends libglib2.0-0t64 2>/dev/null || true
                elif [[ "$pkg" == "libglib2.0-0t64" ]]; then
                    apt-get -o APT::Sandbox::User=root install -y --no-install-recommends libglib2.0-0t64 2>/dev/null || \
                    apt-get -o APT::Sandbox::User=root install -y --no-install-recommends libglib2.0-0 2>/dev/null || true
                else
                    apt-get -o APT::Sandbox::User=root install -y --no-install-recommends "$pkg" 2>/dev/null || true
                fi
            done
            rm -rf /var/lib/apt/lists/*
            ldconfig 2>/dev/null || true

            if command -v git &> /dev/null; then
                log_info "基础系统依赖补齐流程结束 (git 已就绪 ✓)"
            else
                log_warn "git 未能成功安装，部分依赖 Git 的功能可能受限"
            fi
        fi
    else
        log_info "系统基础依赖已就绪 ✓"
    fi
}

#######################################
# 1. 检查环境
#######################################
check_environment() {
    log_info "检查运行环境..."
    
    # 检查 Python
    if ! command -v python &> /dev/null; then
        log_error "Python 未安装！"
        exit 1
    fi
    
    PYTHON_VERSION=$(python --version 2>&1 | awk '{print $2}')
    log_info "Python 版本: ${PYTHON_VERSION}"

    # 动态检测与配置 PyPI / uv 镜像源 (阿里源 -> 字节跳动火山引擎源 -> 清华源)
    local aliyun_pypi="https://mirrors.aliyun.com/pypi/simple/"
    local bytedance_pypi="https://mirrors.volces.com/pypi/simple/"
    local tsinghua_pypi="https://pypi.tuna.tsinghua.edu.cn/simple/"

    if python -c "import urllib.request; urllib.request.urlopen('$aliyun_pypi', timeout=2)" &>/dev/null; then
        export PIP_INDEX_URL="$aliyun_pypi"
        export PIP_EXTRA_INDEX_URL="$bytedance_pypi $tsinghua_pypi"
        log_info "PyPI/uv 镜像源: 优先使用 [阿里源] (备选: 字节跳动火山引擎源、清华源)"
    elif python -c "import urllib.request; urllib.request.urlopen('$bytedance_pypi', timeout=2)" &>/dev/null; then
        export PIP_INDEX_URL="$bytedance_pypi"
        export PIP_EXTRA_INDEX_URL="$aliyun_pypi $tsinghua_pypi"
        log_warn "阿里 PyPI 源无响应，已自动切换至 [字节跳动 (火山引擎) 源] 作为主源"
    else
        export PIP_INDEX_URL="$tsinghua_pypi"
        export PIP_EXTRA_INDEX_URL="$bytedance_pypi $aliyun_pypi"
        log_warn "阿里与字节 PyPI 源均不可用，已自动切换至 [清华源] 作为主源"
    fi
    export UV_INDEX_URL="$PIP_INDEX_URL"
    export UV_EXTRA_INDEX_URL="$PIP_EXTRA_INDEX_URL"
    
    # 检查 pip
    if ! python -m pip --version &> /dev/null; then
        log_error "pip 不可用！"
        exit 1
    fi
    
    # 检查 uv
    if command -v uv &> /dev/null; then
        UV_VERSION=$(uv --version 2>&1 | awk '{print $2}')
        log_info "uv 版本: ${UV_VERSION}"
    else
        log_info "当前环境未找到 uv，尝试自动安装 uv..."
        python -m pip install uv -i "$PIP_INDEX_URL" 2>&1 | grep -v "^$" || \
        python -m pip install uv -i "https://mirrors.volces.com/pypi/simple/" --trusted-host mirrors.volces.com 2>&1 | grep -v "^$" || \
        python -m pip install uv -i "https://pypi.tuna.tsinghua.edu.cn/simple/" --trusted-host pypi.tuna.tsinghua.edu.cn 2>&1 | grep -v "^$" || \
        python -m pip install uv 2>&1 | grep -v "^$" || true
        if command -v uv &> /dev/null; then
            UV_VERSION=$(uv --version 2>&1 | awk '{print $2}')
            log_info "uv 安装完成 ✓ (${UV_VERSION})"
        else
            log_warn "uv 安装未成功，将退回使用 pip"
        fi
    fi
    
    log_info "环境检查完成 ✓"
}

#######################################
# 2. 创建并激活虚拟环境
#######################################
setup_virtualenv() {
    log_info "设置虚拟环境..."
    
    VENV_DIR="/app/.venv"
    
    # 检查虚拟环境是否已存在
    if [ -d "$VENV_DIR" ]; then
        log_info "虚拟环境已存在: $VENV_DIR"
    else
        log_info "创建虚拟环境: $VENV_DIR"
        
        if command -v uv &> /dev/null; then
            log_info "使用 uv 创建虚拟环境..."
            uv venv "$VENV_DIR" --python python || {
                log_warn "uv 创建虚拟环境失败，使用 python -m venv..."
                python -m venv "$VENV_DIR"
            }
        else
            log_info "使用 python -m venv 创建虚拟环境..."
            python -m venv "$VENV_DIR"
        fi
        
        log_info "虚拟环境创建完成 ✓"
    fi
    
    # 激活虚拟环境
    log_info "激活虚拟环境..."
    source "$VENV_DIR/bin/activate"
    
    # 验证虚拟环境
    PYTHON_PATH=$(which python)
    log_info "Python 路径: $PYTHON_PATH"

    # 确保虚拟环境中包含 pip (GsCore 动态安装插件依赖必需)
    if ! python -m pip --version &> /dev/null; then
        log_info "虚拟环境中未检测到 pip，正在补齐 pip (ensurepip)..."
        uv run python -m ensurepip 2>/dev/null || python -m ensurepip 2>/dev/null || true
    fi

    log_info "虚拟环境激活完成 ✓"
}

#######################################
# 2.5. 同步/安装 GsCore 项目核心依赖
#######################################
sync_project_dependencies() {
    log_info "检查 GsCore 核心项目依赖..."
    
    local need_sync=0
    if ! command -v core &> /dev/null && ! python -c "import gsuid_core" &> /dev/null; then
        log_info "首次启动或未检测到 gsuid_core，正在初始化安装项目依赖..."
        need_sync=1
    elif [ -f ".update_flag" ]; then
        log_info "检测到代码更新标志 (.update_flag)，正在同步最新项目依赖..."
        need_sync=1
        rm -f ".update_flag"
    fi

    if [ $need_sync -eq 1 ]; then
        if [ -f "pyproject.toml" ]; then
            log_info "检测到 pyproject.toml，使用 uv sync 进行项目依赖同步..."
            if command -v uv &> /dev/null; then
                uv sync 2>&1 | grep -v "DeprecationWarning" || {
                    log_warn "uv sync 失败，尝试执行 uv pip install -e . ..."
                    uv pip install -e .
                }
                uv run python -m ensurepip 2>/dev/null || true
            else
                pip install -e .
            fi
            log_info "GsCore 核心依赖安装完成 ✓"
        elif [ -f "requirements.txt" ]; then
            log_info "检测到 requirements.txt，正在安装依赖..."
            if command -v uv &> /dev/null; then
                uv pip install -r requirements.txt
            else
                pip install -r requirements.txt
            fi
            log_info "requirements.txt 依赖安装完成 ✓"
        else
            log_warn "未在当前工作目录 ($(pwd)) 找到 pyproject.toml，请确认代码挂载目录是否正确！"
        fi
    else
        log_info "GsCore 核心依赖已就绪 ✓"
    fi
}

#######################################
# 4. 可选依赖处理 (OpenCV)
#######################################
handle_optional_dependencies() {
    INSTALL_OPENCV="${INSTALL_OPENCV:-true}"

    # --- OpenCV 选装处理 ---
    if [ "$INSTALL_OPENCV" = "true" ]; then
        log_info "选装组件 [OpenCV]: 已启用"
        if python -c "import cv2" &> /dev/null; then
            CV_VERSION=$(python -c "import cv2; print(cv2.__version__)" 2>/dev/null)
            log_info "OpenCV 已就绪 ✓ (${CV_VERSION})"
        else
            log_info "正在安装 opencv-python-headless (免系统 X11/OpenGL 依赖)..."
            if command -v uv &> /dev/null; then
                uv pip install opencv-python-headless 2>&1 | grep -v "^$" || true
            else
                pip install opencv-python-headless 2>&1 | grep -v "^$" || true
            fi

            if python -c "import cv2" &> /dev/null; then
                log_info "opencv-python-headless 安装完成 ✓"
            else
                log_warn "opencv-python-headless 安装失败，图像处理功能可能受限"
            fi
        fi
    else
        log_info "选装组件 [OpenCV]: 未启用 (跳过安装)"
    fi
}

#######################################
# 4.5. 清理锁定文件 (避免 git pull 冲突)
#######################################
cleanup_lock_files() {
    log_info "检查并清理 uv.lock 锁定文件..."
    local count=0

    # 扫描 /app 下的 uv.lock 并清理
    while IFS= read -r -d '' lock_file; do
        log_info "删除锁定文件: $lock_file"
        rm -f "$lock_file"
        count=$((count + 1))
    done < <(find /app -maxdepth 3 -name "uv.lock" -type f -print0 2>/dev/null)

    if [ $count -gt 0 ]; then
        log_info "共清理了 $count 个 uv.lock 文件 ✓ (已避免后续更新产生 git 冲突)"
    else
        log_info "未检测到残留的 uv.lock 文件 ✓"
    fi
}

#######################################
# 5. 启动应用
#######################################
start_application() {
    # 计算启动用时
    END_TIME=$(date +%s)
    ELAPSED_TIME=$((END_TIME - START_TIME))
    
    # 格式化时间显示
    if [ $ELAPSED_TIME -ge 60 ]; then
        ELAPSED_MIN=$((ELAPSED_TIME / 60))
        ELAPSED_SEC=$((ELAPSED_TIME % 60))
        ELAPSED_STR="${ELAPSED_MIN}分${ELAPSED_SEC}秒"
    else
        ELAPSED_STR="${ELAPSED_TIME}秒"
    fi
    
    log_info "启动应用..."
    echo ""
    echo "=========================================="
    echo "   💖 GsCore (早柚核心) 运行中"
    echo "   应用标识: ${APP_NAME:-GsCore}"
    echo "   Python:   ${PYTHON_VERSION}"
    echo "   工作目录: $(pwd)"
    echo "   启动用时: ${ELAPSED_STR}"
    echo "=========================================="
    echo ""
    
    # 设置环境变量
    export PYTHONUNBUFFERED=1
    export PIP_INDEX_URL="$PIP_INDEX_URL"
    export PIP_EXTRA_INDEX_URL="$PIP_EXTRA_INDEX_URL"
    export UV_INDEX_URL="$UV_INDEX_URL"
    export UV_EXTRA_INDEX_URL="$UV_EXTRA_INDEX_URL"
    export UV_LINK_MODE=copy
    
    # 启动 core 命令
    if command -v uv &> /dev/null; then
        log_info "使用 uv run 启动 core 命令..."
        exec uv run core "$@"
    elif command -v core &> /dev/null; then
        log_info "使用虚拟环境 bin/core 启动..."
        exec core "$@"
    else
        log_info "使用 python -m gsuid_core 启动..."
        exec python -m gsuid_core "$@"
    fi
}

#######################################
# 主函数
#######################################
main() {
    # 执行各个步骤
    check_system_dependencies
    echo ""

    check_environment
    echo ""
    
    setup_virtualenv
    echo ""
    
    sync_project_dependencies
    echo ""
    
    handle_optional_dependencies
    echo ""
    
    cleanup_lock_files
    echo ""
    
    start_application "$@"
}

# 捕获 Ctrl+C
trap 'echo -e "\n${YELLOW}容器被用户中断${NC}"; exit 130' INT

# 捕获错误
trap 'echo -e "\n${RED}容器启动出错，退出码: $?${NC}"; exit 1' ERR

# 运行主函数（传递所有命令行参数）
main "$@"
