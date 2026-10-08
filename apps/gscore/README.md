<div align="center">
  <h1>GsCore - 早柚核心</h1>
  <p>💖 一套业务逻辑,多个平台支持!</p>
  <p>异步核心框架 GsCore,为插件编写提供完善平台支持</p>
</div>

---

## 项目简介

**GsCore (早柚核心)** 是一个多平台游戏查询 Bot 框架,支持原神、星穹铁道、绝区零等多款游戏的数据查询。

### 核心特性

- 🔀 **异步优先**: 异步处理大量消息流,不会阻塞任务运行
- 🔧 **易于开发**: 即使完全没有接触过 Python,也能快速上手
- ♻ **热重载**: 修改插件配置、安装插件、更新插件,无需重启
- 🌎 **网页控制台**: 集成 WebUI,可通过浏览器直接操作
- 📄 **高度统一**: 统一所有插件的配置管理、数据库、权限控制
- 💻 **多元适配**: 支持 QQ、QQ频道、微信、Telegram、Discord 等多个平台
- 🚀 **作为插件**: 可作为 NoneBot2、Koishi、YunzaiBot 的插件使用

## 1Panel 部署说明

### 前置准备

1. **准备代码目录**: 在宿主机上准备 gsuid_core 项目代码
   ```bash
   # 方式一: 使用 git 克隆
   git clone https://github.com/Genshin-bots/gsuid_core /opt/gsuid_core
   
   # 方式二: 手动下载
   # 从 GitHub 下载最新版本并解压到指定目录
   ```

2. **确保目录结构**:
   ```
   /opt/gsuid_core/
   ├── pyproject.toml    # 项目配置文件
   ├── bot.sh            # 启动脚本
   ├── gsuid_core/       # 核心代码
   ├── plugins/          # 插件目录
   ├── data/             # 数据目录
   └── config/           # 配置目录
   ```

### 安装步骤

1. **在 1Panel 应用商店中搜索 "GsCore"**

2. **配置参数**:
   - **代码目录**: 填写宿主机上 gsuid_core 的绝对路径 (默认: `/opt/gsuid_core`)
   - **容器名称**: 自定义容器名称 (默认: `gsuid-core`)
   - **WebUI 端口**: WebUI 访问端口 (默认: `8765`)
   - **选装 OpenCV**: 是否安装 OpenCV 图像处理支持 (默认: `true`，自动安装 `opencv-python-headless`)

3. **点击安装**: 等待容器启动完成

4. **访问 WebUI**: 
   - 地址: `http://your-server-ip:8765`
   - 通过 WebUI 可以管理插件、配置、查看日志等

### 配置说明

#### 环境变量

| 变量名 | 说明 | 默认值 | 推荐配置 / 可选值 |
|--------|------|--------|------------------|
| `CODE_DIR` | 代码目录(宿主机绝对路径) | `/opt/gsuid_core` | 需挂载至宿主机的实际代码路径 |
| `CONTAINER_NAME` | 容器名称 | `gsuid-core` | 保持默认或自定义 |
| `PANEL_APP_PORT_HTTP` | WebUI 端口 | `8765` | 可自定义未占用端口 |
| `START_COMMAND` | 启动命令 | `bash /app/bot.sh` | 容器入口启动脚本 |
| `DOCKER_IMAGE` | Docker 基础镜像 | `python:3.13-slim` | 默认直接使用公版官方 Python 镜像 |
| `INSTALL_OPENCV` | 选装 OpenCV 依赖 | `true` | `true` (安装 headless 版免系统库) / `false` |

#### 目录挂载

- `/app`: 应用代码目录,挂载自宿主机的 `CODE_DIR`
- `/etc/localtime`: 时区配置 (只读)
- `/etc/timezone`: 时区配置 (只读)

### 使用 Docker 直接部署

如果不使用 1Panel,也可以直接使用 Docker Compose:

```bash
# 进入项目目录
cd gsuid-docker

# 复制环境变量配置
cp .env.example .env

# 编辑配置文件
nano .env

# 启动容器
docker-compose up -d

# 查看日志
docker-compose logs -f
```

### 启动流程说明

容器启动时会自动执行 `bot.sh` 脚本,该脚本会:

1. 检查底层系统基础依赖 (git, C 运行库)
2. 检查 Python 与 uv 环境
3. 创建并激活虚拟环境 (`.venv`)
4. 安装与同步项目依赖 (从 `pyproject.toml`)
5. 检查可选依赖 (OpenCV)
6. 启动应用

**首次启动可能需要 1-2 分钟**,需要下载依赖。

### 常见问题

#### 1. 容器启动失败

**检查代码目录**:
```bash
# 确保代码目录存在且包含必要文件
ls -la /opt/gsuid_core
```

**查看容器日志**:
```bash
docker logs gsuid-core
```

#### 2. WebUI 无法访问

**检查端口映射**:
```bash
docker ps | grep gsuid-core
```

**检查防火墙**:
```bash
# 开放端口 (如果使用防火墙)
firewall-cmd --add-port=8765/tcp --permanent
firewall-cmd --reload
```

#### 3. 依赖安装失败

容器会自动使用国内镜像源 (阿里云),如果仍然失败:

1. 检查网络连接
2. 查看容器日志获取详细错误信息
3. 尝试手动进入容器安装:
   ```bash
   docker exec -it gsuid-core bash
   source .venv/bin/activate
   uv sync
   ```

### 更新升级

#### 更新代码

```bash
# 进入代码目录
cd /opt/gsuid_core

# 拉取最新代码
git pull

# 重启容器
docker restart gsuid-core
```

#### 更新镜像

```bash
# 拉取最新镜像
docker pull strycn/gsuid-core:latest

# 重新创建容器
docker-compose up -d --force-recreate
```

### 插件管理

通过 WebUI 可以方便地管理插件:

1. 访问 `http://your-ip:8765`
2. 进入"插件管理"页面
3. 可以安装、更新、卸载插件
4. 修改插件配置

也可以通过命令行:

```bash
# 进入容器
docker exec -it gsuid-core bash

# 安装插件
uv run core install <plugin-name>

# 更新插件
uv run core update <plugin-name>
```

## 相关链接

- 📖 **官方文档**: https://docs.sayu-bot.com
- 🐙 **GitHub**: https://github.com/Genshin-bots/gsuid_core
- 💬 **QQ 群**: [加入讨论](https://docs.sayu-bot.com)
- 🔌 **插件市场**: https://docs.sayu-bot.com/InstallPlugins/PluginsList.html

## 开源协议

本项目采用 [GPL-3.0 License](https://github.com/Genshin-bots/gsuid_core/blob/master/LICENSE) 开源协议

## 致谢

感谢 [@KimigaiiWuyi](https://github.com/KimigaiiWuyi) 和所有贡献者的辛勤付出!

---

<div align="center">
  <p>如果觉得项目不错,请给个 ⭐ Star 支持一下!</p>
</div>
