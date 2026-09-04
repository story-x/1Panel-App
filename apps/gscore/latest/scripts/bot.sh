#!/bin/bash

#######################################
# Docker 容器启动脚本
# 功能：检查依赖、安装项目特定依赖并运行项目
# 基于 bot.sh 优化，适配 Docker 环境
#######################################

set -e  # 遇到错误立即退出

# 可选：指定 Playwright 版本（留空则自动安装适配版本，公版 Python 建议留空）
PLAYWRIGHT_VERSION="${PLAYWRIGHT_VERSION:-}"

# 国内镜像源定义
export PIP_INDEX_URL="${PIP_INDEX_URL:-https://pypi.tuna.tsinghua.edu.cn/simple}"
export UV_INDEX_URL="${UV_INDEX_URL:-$PIP_INDEX_URL}"
export PLAYWRIGHT_DOWNLOAD_HOST="${PLAYWRIGHT_DOWNLOAD_HOST:-https://npmmirror.com/mirrors/playwright/}"

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
        python -m pip install uv -i "$PIP_INDEX_URL" 2>&1 | grep -v "^$" || true
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
            log_info "检测到 pyproject.toml，使用 uv 进行项目依赖同步..."
            if command -v uv &> /dev/null; then
                uv sync --no-dev 2>&1 | grep -v "DeprecationWarning" || {
                    log_warn "uv sync 失败，尝试执行 uv pip install -e . ..."
                    uv pip install -e .
                }
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
# 3. 检查并安装 Chromium 浏览器
#######################################
check_chromium() {
    # 检查 playwright 是否已安装
    if ! python -c "import playwright" &> /dev/null; then
        log_debug "playwright 未安装，跳过浏览器检查"
        return
    fi

    log_info "检查 Chromium 浏览器..."

    # 定义浏览器路径
    BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/ms-playwright}"
    FORCE_REINSTALL="${FORCE_REINSTALL_CHROMIUM:-0}"

    log_debug "浏览器安装路径: $BROWSERS_PATH"

    # 强制重装时才清理
    if [ "$FORCE_REINSTALL" = "1" ]; then
        log_warn "检测到 FORCE_REINSTALL_CHROMIUM=1，执行 Chromium 强制重装"
        rm -rf "$BROWSERS_PATH"
    fi

    # 发现已有浏览器则直接复用，不自动删除重装
    if [ -d "$BROWSERS_PATH" ]; then
        CHROMIUM_PATH=$(find "$BROWSERS_PATH" -maxdepth 2 -name "chromium-*" -type d 2>/dev/null | head -n 1)
        if [ -n "$CHROMIUM_PATH" ]; then
            log_info "发现已安装的 Chromium: $(basename "$CHROMIUM_PATH")"
            export PLAYWRIGHT_BROWSERS_PATH="$BROWSERS_PATH"
            log_info "复用已安装 Chromium（不重新下载）✓"
            return
        fi
    fi

    log_info "未发现 Chromium，开始安装..."
    log_info "这可能需要 1-2 分钟，请耐心等待..."

    # 临时禁用 set -e，防止安装失败导致脚本退出
    set +e

    # 尝试使用国内镜像
    log_info "尝试使用国内镜像下载..."
    log_debug "使用镜像: $PLAYWRIGHT_DOWNLOAD_HOST"

    if command -v uv &> /dev/null; then
        CHROMIUM_OUTPUT=$(PLAYWRIGHT_BROWSERS_PATH="$BROWSERS_PATH" \
            uv run --no-project playwright install chromium 2>&1)
    else
        CHROMIUM_OUTPUT=$(PLAYWRIGHT_BROWSERS_PATH="$BROWSERS_PATH" \
            playwright install chromium 2>&1)
    fi
    CHROMIUM_EXIT_CODE=$?

    # 检查是否是 404 错误（镜像未同步最新版本）
    if [ $CHROMIUM_EXIT_CODE -ne 0 ] && echo "$CHROMIUM_OUTPUT" | grep -q "404\|NoSuchKey"; then
        log_warn "国内镜像未同步最新版本，尝试安装较旧的稳定版本..."

        # 回退到已知在镜像上可用的稳定版本
        FALLBACK_VERSION="${PLAYWRIGHT_VERSION:-1.49.1}"
        log_info "降级 playwright 到 ${FALLBACK_VERSION}..."

        if command -v uv &> /dev/null; then
            uv pip install "playwright==${FALLBACK_VERSION}" 2>&1 | grep -v "^$" || true
            CHROMIUM_OUTPUT=$(PLAYWRIGHT_BROWSERS_PATH="$BROWSERS_PATH" \
                uv run --no-project playwright install chromium 2>&1)
        else
            pip install "playwright==${FALLBACK_VERSION}" 2>&1 | grep -v "^$" || true
            CHROMIUM_OUTPUT=$(PLAYWRIGHT_BROWSERS_PATH="$BROWSERS_PATH" \
                playwright install chromium 2>&1)
        fi
        CHROMIUM_EXIT_CODE=$?

        # 如果还是失败，再尝试更老的版本
        if [ $CHROMIUM_EXIT_CODE -ne 0 ] && echo "$CHROMIUM_OUTPUT" | grep -q "404\|NoSuchKey"; then
            FALLBACK_VERSION="1.44.0"
            log_warn "版本 1.48.0 也不可用，尝试 ${FALLBACK_VERSION}..."

            if command -v uv &> /dev/null; then
                uv pip install "playwright==${FALLBACK_VERSION}" 2>&1 | grep -v "^$" || true
                CHROMIUM_OUTPUT=$(PLAYWRIGHT_BROWSERS_PATH="$BROWSERS_PATH" \
                    uv run --no-project playwright install chromium 2>&1)
            else
                pip install "playwright==${FALLBACK_VERSION}" 2>&1 | grep -v "^$" || true
                CHROMIUM_OUTPUT=$(PLAYWRIGHT_BROWSERS_PATH="$BROWSERS_PATH" \
                    playwright install chromium 2>&1)
            fi
            CHROMIUM_EXIT_CODE=$?
        fi
    fi

    # 重新启用 set -e
    set -e

    # 显示输出（过滤警告信息）
    echo "$CHROMIUM_OUTPUT" | grep -v "DeprecationWarning" | grep -v "url.parse" | grep -v "^$" | grep -v "NoSuchKey" | grep -v "xml version" | tail -10 || true

    # 检查 chromium 是否安装成功
    if [ $CHROMIUM_EXIT_CODE -eq 0 ] || echo "$CHROMIUM_OUTPUT" | grep -q "downloaded to\|is already installed"; then
        PW_VERSION=$(python -m pip show playwright 2>/dev/null | grep "^Version:" | awk '{print $2}' || echo "unknown")
        log_info "Chromium 安装成功 ✓ (playwright ${PW_VERSION})"
        log_info "浏览器安装路径: $BROWSERS_PATH"

        export PLAYWRIGHT_BROWSERS_PATH="$BROWSERS_PATH"
    else
        # 尝试带系统依赖重试（解决 slim 镜像缺少 Linux 库的问题）
        if echo "$CHROMIUM_OUTPUT" | grep -qi "dependencies\|missing\|host"; then
            log_warn "检测到可能缺少底层系统依赖，尝试自动安装依赖 (playwright install --with-deps)..."
            if command -v uv &> /dev/null; then
                PLAYWRIGHT_BROWSERS_PATH="$BROWSERS_PATH" uv run --no-project playwright install --with-deps chromium 2>&1 || true
            else
                PLAYWRIGHT_BROWSERS_PATH="$BROWSERS_PATH" playwright install --with-deps chromium 2>&1 || true
            fi
        fi

        if [ -d "$BROWSERS_PATH" ] && [ -n "$(find "$BROWSERS_PATH" -maxdepth 2 -name "chromium-*" -type d 2>/dev/null | head -n 1)" ]; then
            log_info "Chromium 最终安装完成 ✓"
            export PLAYWRIGHT_BROWSERS_PATH="$BROWSERS_PATH"
        else
            log_error "Chromium 安装失败！(退出码: $CHROMIUM_EXIT_CODE)"
            log_warn "playwright 功能可能不可用"
            log_warn "错误信息: $(echo "$CHROMIUM_OUTPUT" | grep -i "error\|failed" | tail -3)"
            log_warn "如需使用 Playwright，可进入容器执行: playwright install --with-deps chromium"
        fi
    fi
}

#######################################
# 4. 可选依赖处理 (OpenCV / Playwright)
#######################################
handle_optional_dependencies() {
    INSTALL_OPENCV="${INSTALL_OPENCV:-true}"
    INSTALL_PLAYWRIGHT="${INSTALL_PLAYWRIGHT:-false}"

    # --- 4.1 OpenCV 选装处理 ---
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

    # --- 4.2 Playwright 选装处理 ---
    if [ "$INSTALL_PLAYWRIGHT" = "true" ]; then
        log_info "选装组件 [Playwright]: 已启用"
        if [ -n "$PLAYWRIGHT_VERSION" ]; then
            # 显式指定版本时的检查与安装
            if python -c "import playwright; import sys; sys.exit(0 if playwright.__version__ == '${PLAYWRIGHT_VERSION}' else 1)" &> /dev/null; then
                log_info "Playwright 指定版本已满足 (${PLAYWRIGHT_VERSION}) ✓"
            else
                log_info "安装指定版本 playwright==${PLAYWRIGHT_VERSION}..."
                if command -v uv &> /dev/null; then
                    uv pip install "playwright==${PLAYWRIGHT_VERSION}" 2>&1 | grep -v "^$" || true
                else
                    pip install "playwright==${PLAYWRIGHT_VERSION}" 2>&1 | grep -v "^$" || true
                fi
            fi
        else
            # 未指定版本（公版环境默认推荐）：已安装则复用，未安装则自动安装适配版本
            if python -c "import playwright" &> /dev/null; then
                PW_VERSION=$(python -m pip show playwright 2>/dev/null | grep "^Version:" | awk '{print $2}' || echo "已安装")
                log_info "Playwright 已就绪 ✓ (${PW_VERSION})"
            else
                log_info "正在自动安装最新适配版 playwright..."
                if command -v uv &> /dev/null; then
                    uv pip install playwright 2>&1 | grep -v "^$" || true
                else
                    pip install playwright 2>&1 | grep -v "^$" || true
                fi
            fi
        fi

        # 检查并安装浏览器
        check_chromium
    else
        log_info "选装组件 [Playwright]: 未启用 (跳过安装浏览器内核与渲染套件，秒级启动)"
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
    export UV_INDEX_URL="$UV_INDEX_URL"
    export PLAYWRIGHT_DOWNLOAD_HOST="$PLAYWRIGHT_DOWNLOAD_HOST"
    export UV_LINK_MODE=copy
    
    # PLAYWRIGHT_BROWSERS_PATH 由 check_chromium 函数设置
    
    # 启动 core 命令
    if command -v uv &> /dev/null; then
        log_info "使用 uv run 启动 core 命令..."
        exec uv run --no-project core "$@"
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
