#!/bin/bash

# GsCore 初始化脚本
# 用于在 1Panel 中部署时进行必要的初始化操作

set -e

# 脚本所在目录及应用根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# 尝试寻找并载入 .env 配置
if [ -f "${BASE_DIR}/.env" ]; then
    source "${BASE_DIR}/.env"
elif [ -f "${SCRIPT_DIR}/.env" ]; then
    source "${SCRIPT_DIR}/.env"
elif [ -f "./.env" ]; then
    source ./.env
fi

# 兜底默认值
CODE_DIR="${CODE_DIR:-/opt/gsuid_core}"
CONTAINER_NAME="${CONTAINER_NAME:-gsuid-core}"
PANEL_APP_PORT_HTTP="${PANEL_APP_PORT_HTTP:-8765}"

echo "=========================================="
echo "  GsCore 初始化"
echo "=========================================="

# 检查代码目录是否存在
if [ ! -d "${CODE_DIR}" ]; then
    echo "代码目录不存在,正在创建: ${CODE_DIR}"
    mkdir -p "${CODE_DIR}"
    
    echo "提示: 请将 gsuid_core 项目代码放入 ${CODE_DIR} 目录"
    echo "您可以通过以下方式获取代码:"
    echo "  1. git clone https://github.com/Genshin-bots/gsuid_core ${CODE_DIR}"
    echo "  2. 或手动下载并解压到该目录"
else
    echo "代码目录已存在: ${CODE_DIR}"
fi

# 复制 bot.sh 启动脚本到代码目录
if [ -f "${SCRIPT_DIR}/bot.sh" ]; then
    echo "正在复制 bot.sh 启动脚本到代码目录..."
    cp -f "${SCRIPT_DIR}/bot.sh" "${CODE_DIR}/bot.sh"
    
    # 转换 Windows 换行符 (CRLF) 为 Unix 换行符 (LF)
    sed -i 's/\r$//' "${CODE_DIR}/bot.sh" 2>/dev/null || sed -i '' 's/\r$//' "${CODE_DIR}/bot.sh" 2>/dev/null || true
    
    chmod +x "${CODE_DIR}/bot.sh"
    echo "✓ bot.sh 启动脚本已复制并设置为可执行"
else
    echo "⚠ 警告: 未找到 bot.sh 模板文件"
fi

# 复制 update.sh 更新脚本到代码目录
if [ -f "${SCRIPT_DIR}/update.sh" ]; then
    echo "正在复制 update.sh 更新脚本到代码目录..."
    cp -f "${SCRIPT_DIR}/update.sh" "${CODE_DIR}/update.sh"
    
    # 转换 Windows 换行符 (CRLF) 为 Unix 换行符 (LF)
    sed -i 's/\r$//' "${CODE_DIR}/update.sh" 2>/dev/null || sed -i '' 's/\r$//' "${CODE_DIR}/update.sh" 2>/dev/null || true
    
    chmod +x "${CODE_DIR}/update.sh"
    echo "✓ update.sh 更新脚本已复制并设置为可执行"
else
    echo "⚠ 警告: 未找到 update.sh 模板文件"
fi


# 检查必要文件
if [ -f "${CODE_DIR}/pyproject.toml" ]; then
    echo "✓ 检测到 pyproject.toml"
else
    echo "⚠ 警告: 未检测到 pyproject.toml,请确保代码目录包含完整的 gsuid_core 项目"
fi


echo ""
echo "=========================================="
echo "  初始化完成"
echo "=========================================="
echo "代码目录: ${CODE_DIR}"
echo "容器名称: ${CONTAINER_NAME}"
echo "容器端口: ${PANEL_APP_PORT_HTTP}"
echo ""
echo "下一步:"
echo "  1. 确保代码目录包含完整的 gsuid_core 项目"
echo "  2. 启动容器后,访问 http://your-ip:${PANEL_APP_PORT_HTTP} 查看 WebUI"
echo "  3. 查看文档: https://docs.sayu-bot.com"
echo "=========================================="
