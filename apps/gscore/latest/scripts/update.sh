#!/bin/bash

# GsCore 自动更新脚本
# 支持自动读取 .env 配置文件，并可通过 docker 容器动态检测容器名和挂载目录

# 脚本所在目录及根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# 尝试寻找并载入 .env 配置
ENV_FILE=""
if [ -f "${BASE_DIR}/.env" ]; then
    ENV_FILE="${BASE_DIR}/.env"
elif [ -f "${SCRIPT_DIR}/.env" ]; then
    ENV_FILE="${SCRIPT_DIR}/.env"
elif [ -f "./.env" ]; then
    ENV_FILE="./.env"
fi

if [ -n "$ENV_FILE" ]; then
    echo "正在从配置文件加载配置: $ENV_FILE"
    while IFS= read -r line || [ -n "$line" ]; do
        # 过滤空行和注释
        if [[ ! "$line" =~ ^# ]] && [[ "$line" =~ = ]]; then
            clean_line=$(echo "$line" | sed 's/\r$//')
            eval "export $clean_line" 2>/dev/null
        fi
    done < "$ENV_FILE"
fi

# 如果 CONTAINER_NAME 未定义，通过 docker 标签或名称精准查找容器
if [ -z "$CONTAINER_NAME" ]; then
    echo "未在配置中找到 CONTAINER_NAME，尝试从 Docker 容器中动态识别..."
    # 1. 优先通过唯一标签 app=gscore 精准匹配（不受改名或基础镜像影响）
    CONTAINER_NAME=$(docker ps -a --filter "label=app=gscore" --format "{{.Names}}" | head -n 1)
    # 2. 备选通过容器名称过滤
    if [ -z "$CONTAINER_NAME" ]; then
        CONTAINER_NAME=$(docker ps -a --filter "name=gsuid-core" --format "{{.Names}}" | head -n 1)
    fi
    # 3. 兜底通过镜像过滤
    if [ -z "$CONTAINER_NAME" ]; then
        CONTAINER_NAME=$(docker ps -a --filter "ancestor=${DOCKER_IMAGE:-python:3.13-slim}" --format "{{.Names}}" | head -n 1)
    fi
    # 4. 兜底模糊匹配
    if [ -z "$CONTAINER_NAME" ]; then
        CONTAINER_NAME=$(docker ps -a --format '{{.Names}}' | grep "gsuid-core" | head -n 1)
    fi
fi

# 如果 CODE_DIR 未定义，通过 docker inspect 查找容器挂载的宿主机路径
if [ -n "$CONTAINER_NAME" ] && [ -z "$CODE_DIR" ]; then
    echo "未在配置中找到 CODE_DIR，尝试从容器 $CONTAINER_NAME 的挂载信息中动态识别..."
    CODE_DIR=$(docker inspect --format '{{ range .Mounts }}{{ if eq .Destination "/app" }}{{ .Source }}{{ end }}{{ end }}' "$CONTAINER_NAME" 2>/dev/null)
fi

# 兜底默认值
CONTAINER_NAME=${CONTAINER_NAME:-"gsuid-core"}
CODE_DIR=${CODE_DIR:-"/opt/gsuid_core"}

echo "----------------------------------------"
echo "  配置信息:"
echo "  容器名称 (CONTAINER_NAME): $CONTAINER_NAME"
echo "  代码目录 (CODE_DIR):       $CODE_DIR"
echo "----------------------------------------"

# 检查代码目录是否存在
if [ ! -d "$CODE_DIR" ]; then
    echo "❌ 错误: 代码目录 $CODE_DIR 不存在，无法进行更新操作！"
    exit 1
fi

# 标志文件路径
FLAG_FILE="${CODE_DIR}/.update_flag"

# 清空旧的标志
rm -f "$FLAG_FILE"

echo "开始查找并更新所有 Git 仓库..."

# 遍历所有包含 .git 的子目录并执行 git pull
# 限制搜索深度，防止扫描过多无用目录
find "$CODE_DIR" -maxdepth 4 -type d -name ".git" | while read -r gitdir; do
    repo_dir=$(dirname "$gitdir")
    echo "进入目录: $repo_dir"
    cd "$repo_dir" || continue

    # 如果存在 uv.lock，提前清理以防止 git pull 冲突
    if [ -f "${repo_dir}/uv.lock" ]; then
        echo "发现 ${repo_dir}/uv.lock，正在清理以避免 git pull 冲突..."
        rm -f "${repo_dir}/uv.lock"
    fi

    echo "执行 git pull..."

    output=$(git pull 2>&1)
    echo "$output"
    echo "----------------------------------------"

    # 如果有更新，写入标志文件
    if echo "$output" | grep -qE "Updating|Fast-forward"; then
        echo "updated" >> "$FLAG_FILE"
    fi
done

# 判断是否需要重启容器
if [ -f "$FLAG_FILE" ]; then
    echo "检测到代码更新，准备重启容器: $CONTAINER_NAME"

    container_exists=$(docker ps -a --format '{{.Names}}' | grep -w "$CONTAINER_NAME")
    if [ -n "$container_exists" ]; then
        echo "停止容器: $CONTAINER_NAME"
        docker stop "$CONTAINER_NAME"
        echo "启动容器: $CONTAINER_NAME"
        docker start "$CONTAINER_NAME"
        echo "容器 $CONTAINER_NAME 重启完成 ✅"
    else
        # 兜底：如果没找到这个具体名字的容器，但有 docker-compose.yml 存在，则尝试在对应的目录下重启
        if [ -f "${BASE_DIR}/docker-compose.yml" ]; then
            echo "未找到名称为 $CONTAINER_NAME 的容器，尝试通过 docker-compose 重启..."
            cd "$BASE_DIR" && docker compose restart || docker-compose restart
        else
            echo "未找到容器: $CONTAINER_NAME，且未找到 docker-compose.yml，跳过重启。"
        fi
    fi
    rm -f "$FLAG_FILE"
else
    echo "未检测到任何更新，容器无需重启。"
fi

echo "操作完成 ✅"
