#!/bin/bash

#######################################
# Docker 容器启动脚本
# 功能：检查依赖、安装项目特定依赖并运行项目
# 基于 bot.sh 优化，适配 Docker 环境
#######################################

set -e  # 遇到错误立即退出

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
echo "   GSUID Core Docker 容器启动"
echo "   Python: $(python --version 2>&1 | awk '{print $2}')"
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
# 3. 安装项目依赖
#######################################
install_dependencies() {
    log_info "检查项目依赖..."
    
    # 检查是否有 pyproject.toml
    if [ -f "pyproject.toml" ]; then
        log_info "检测到 pyproject.toml，安装项目依赖..."
        
        if command -v uv &> /dev/null; then
            log_info "使用 uv 安装依赖..."
            UV_INDEX_URL=https://mirrors.aliyun.com/pypi/simple \
            UV_LINK_MODE=copy \
            uv sync --no-dev 2>&1 | grep -v "DeprecationWarning" || {
                log_warn "uv sync 失败，尝试使用 uv pip install..."
                UV_INDEX_URL=https://mirrors.aliyun.com/pypi/simple \
                UV_LINK_MODE=copy \
                uv pip install -e . || {
                    log_error "依赖安装失败"
                    exit 1
                }
            }
            log_info "pyproject.toml 依赖安装完成 ✓"
            
            # 降级 playwright 到稳定版本，防止浏览器版本不匹配
            log_info "锁定 playwright 到稳定版本 1.48.0..."
            UV_INDEX_URL=https://mirrors.aliyun.com/pypi/simple \
            uv pip install "playwright==1.48.0" 2>&1 | grep -v "^$" || true
            
        else
            log_warn "uv 未安装，使用 pip..."
            pip install -e . || {
                log_error "依赖安装失败"
                exit 1
            }
            log_info "pyproject.toml 依赖安装完成 ✓"
        fi
        
    # 检查是否有 requirements.txt
    elif [ -f "requirements.txt" ]; then
        log_info "检测到 requirements.txt，安装项目依赖..."
        
        pip install -r requirements.txt -i https://mirrors.aliyun.com/pypi/simple
        
        log_info "requirements.txt 依赖安装完成 ✓"
    
    else
        log_warn "未检测到 pyproject.toml 或 requirements.txt"
        log_warn "跳过项目依赖安装"
    fi
}

#######################################
# 4. 检查可选依赖
#######################################
check_optional_deps() {
    log_info "检查可选依赖..."
    
    # 检查 opencv
    if python -c "import cv2" &> /dev/null; then
        CV_VERSION=$(python -c "import cv2; print(cv2.__version__)" 2>/dev/null)
        log_info "opencv-python 已安装 ✓ (${CV_VERSION})"
    else
        log_warn "opencv-python 未安装，图像处理功能可能不可用"
    fi
    
    # 检查 playwright
    if python -c "import playwright" &> /dev/null; then
        PW_VERSION=$(python -m pip show playwright 2>/dev/null | grep "^Version:" | awk '{print $2}' || echo "unknown")
        log_info "playwright 已安装 ✓ (${PW_VERSION})"
    else
        log_warn "playwright 未安装，浏览器功能不可用"
    fi
}

#######################################
# 4.5. 检查并安装 Chromium 浏览器
#######################################
check_chromium() {
    # 检查 playwright 是否已安装
    if ! python -c "import playwright" &> /dev/null; then
        log_debug "playwright 未安装，跳过浏览器检查"
        return
    fi
    
    log_info "检查 Chromium 浏览器..."
    
    # 定义浏览器路径
    VENV_ABS_PATH="/app/.venv"
    BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/ms-playwright}"
    
    log_debug "浏览器安装路径: $BROWSERS_PATH"
    
    # 获取当前 playwright 版本
    CURRENT_PW_VERSION=$(python -m pip show playwright 2>/dev/null | grep "^Version:" | awk '{print $2}' || echo "unknown")
    log_debug "当前 playwright 版本: $CURRENT_PW_VERSION"
    
    # 检查浏览器是否已安装
    NEED_INSTALL=false
    if [ -d "$BROWSERS_PATH" ]; then
        CHROMIUM_PATH=$(find "$BROWSERS_PATH" -maxdepth 2 -name "chromium-*" -type d 2>/dev/null | head -n 1)
        if [ -n "$CHROMIUM_PATH" ]; then
            log_info "发现已安装的 Chromium: $(basename $CHROMIUM_PATH)"
            
            # 尝试启动浏览器验证是否可用
            if PLAYWRIGHT_BROWSERS_PATH="$BROWSERS_PATH" python -c "
from playwright.sync_api import sync_playwright
try:
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        browser.close()
    exit(0)
except Exception as e:
    exit(1)
" &>/dev/null; then
                log_info "Chromium 浏览器可用 ✓"
                export PLAYWRIGHT_BROWSERS_PATH="$BROWSERS_PATH"
                return
            else
                log_warn "Chromium 浏览器版本不匹配或损坏，需要重新安装"
                NEED_INSTALL=true
                # 删除旧版本浏览器
                rm -rf "$BROWSERS_PATH"
            fi
        else
            NEED_INSTALL=true
        fi
    else
        NEED_INSTALL=true
    fi
    
    # 需要安装浏览器
    if [ "$NEED_INSTALL" = true ]; then
        log_info "正在安装 Chromium 浏览器..."
        log_info "这可能需要 1-2 分钟，请耐心等待..."
        
        # 临时禁用 set -e，防止安装失败导致脚本退出
        set +e
        
        # 尝试使用国内镜像
        log_info "尝试使用国内镜像下载..."
        log_debug "使用镜像: https://npmmirror.com/mirrors/playwright/"
        
        CHROMIUM_OUTPUT=$(PLAYWRIGHT_DOWNLOAD_HOST=https://npmmirror.com/mirrors/playwright/ \
            PLAYWRIGHT_BROWSERS_PATH="$BROWSERS_PATH" \
            uv run --no-project playwright install chromium 2>&1)
        CHROMIUM_EXIT_CODE=$?
        
        # 检查是否是 404 错误（镜像未同步最新版本）
        if [ $CHROMIUM_EXIT_CODE -ne 0 ] && echo "$CHROMIUM_OUTPUT" | grep -q "404\|NoSuchKey"; then
            log_warn "国内镜像未同步最新版本，尝试安装较旧的稳定版本..."
            
            # 回退到已知在镜像上可用的版本
            FALLBACK_VERSION="1.48.0"
            log_info "降级 playwright 到 ${FALLBACK_VERSION}..."
            
            UV_INDEX_URL=https://mirrors.aliyun.com/pypi/simple \
            uv pip install "playwright==${FALLBACK_VERSION}" 2>&1 | grep -v "^$" || true
            
            # 重新尝试用镜像下载
            CHROMIUM_OUTPUT=$(PLAYWRIGHT_DOWNLOAD_HOST=https://npmmirror.com/mirrors/playwright/ \
                PLAYWRIGHT_BROWSERS_PATH="$BROWSERS_PATH" \
                uv run --no-project playwright install chromium 2>&1)
            CHROMIUM_EXIT_CODE=$?
            
            # 如果还是失败，再尝试更老的版本
            if [ $CHROMIUM_EXIT_CODE -ne 0 ] && echo "$CHROMIUM_OUTPUT" | grep -q "404\|NoSuchKey"; then
                FALLBACK_VERSION="1.44.0"
                log_warn "版本 1.48.0 也不可用，尝试 ${FALLBACK_VERSION}..."
                
                UV_INDEX_URL=https://mirrors.aliyun.com/pypi/simple \
                uv pip install "playwright==${FALLBACK_VERSION}" 2>&1 | grep -v "^$" || true
                
                CHROMIUM_OUTPUT=$(PLAYWRIGHT_DOWNLOAD_HOST=https://npmmirror.com/mirrors/playwright/ \
                    PLAYWRIGHT_BROWSERS_PATH="$BROWSERS_PATH" \
                    uv run --no-project playwright install chromium 2>&1)
                CHROMIUM_EXIT_CODE=$?
            fi
        fi
        
        # 重新启用 set -e
        set -e
        
        # 显示输出（过滤警告信息）
        echo "$CHROMIUM_OUTPUT" | grep -v "DeprecationWarning" | grep -v "url.parse" | grep -v "^$" | grep -v "NoSuchKey" | grep -v "xml version" | tail -10 || true
        
        # 检查 chromium 是否安装成功
        if [ $CHROMIUM_EXIT_CODE -eq 0 ] || echo "$CHROMIUM_OUTPUT" | grep -q "downloaded to\|is already installed"; then
            # 获取实际安装的 playwright 版本
            PW_VERSION=$(python -m pip show playwright 2>/dev/null | grep "^Version:" | awk '{print $2}' || echo "unknown")
            log_info "Chromium 安装成功 ✓ (playwright ${PW_VERSION})"
            log_info "浏览器已安装到虚拟环境: $BROWSERS_PATH"
            
            # 设置环境变量
            export PLAYWRIGHT_BROWSERS_PATH="$BROWSERS_PATH"
            
            # 锁定 playwright 版本，防止被自动升级
            if [ "$PW_VERSION" != "unknown" ] && [ "$PW_VERSION" != "$CURRENT_PW_VERSION" ]; then
                log_info "锁定 playwright 版本为 ${PW_VERSION}，防止自动升级"
                # 使用 uv pip install --no-deps 防止依赖升级
                UV_INDEX_URL=https://mirrors.aliyun.com/pypi/simple \
                uv pip install --no-deps "playwright==${PW_VERSION}" &>/dev/null || true
            fi
            
            # 验证可执行文件是否存在
            CHROMIUM_PATH=$(find "$BROWSERS_PATH" -maxdepth 2 -name "chromium-*" -type d 2>/dev/null | head -n 1)
            if [ -n "$CHROMIUM_PATH" ]; then
                log_debug "Chromium 路径: $CHROMIUM_PATH"
            fi
        else
            log_error "Chromium 安装失败！(退出码: $CHROMIUM_EXIT_CODE)"
            log_warn "playwright 功能可能不可用"
            log_warn "错误信息: $(echo "$CHROMIUM_OUTPUT" | grep -i "error\|failed" | tail -3)"
            log_warn "请手动执行: PLAYWRIGHT_BROWSERS_PATH=$BROWSERS_PATH uv run --no-project playwright install chromium"
        fi
    fi
}

#######################################
# 6. 启动应用
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
    echo "   应用运行中"
    echo "   Python: ${PYTHON_VERSION}"
    echo "   工作目录: $(pwd)"
    echo "   启动用时: ${ELAPSED_STR}"
    echo "=========================================="
    echo ""
    
    # 设置环境变量
    export PYTHONUNBUFFERED=1
    export UV_INDEX_URL=https://mirrors.aliyun.com/pypi/simple
    export UV_LINK_MODE=copy
    
    # PLAYWRIGHT_BROWSERS_PATH 由 check_chromium 函数设置
    
    # 使用 uv run 启动 core 命令
    log_info "使用 uv run 启动 core 命令..."
    exec uv run --no-project core "$@"
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
    
    install_dependencies
    echo ""
    
    check_optional_deps
    echo ""
    
    check_chromium
    echo ""
    
    start_application "$@"
}

# 捕获 Ctrl+C
trap 'echo -e "\n${YELLOW}容器被用户中断${NC}"; exit 130' INT

# 捕获错误
trap 'echo -e "\n${RED}容器启动出错，退出码: $?${NC}"; exit 1' ERR

# 运行主函数（传递所有命令行参数）
main "$@"
