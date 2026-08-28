<div align="center">
  <h1>Mihomo (Clash.Meta)</h1>
  <p>⚡ 基于 Go 开发的现代化规则分流代理内核</p>
  <p>
    <a href="https://github.com/MetaCubeX/mihomo">GitHub 仓库</a> •
    <a href="https://wiki.metacubex.one">官方文档</a>
  </p>
</div>

---

## 📖 项目简介

**Mihomo**（原名 Clash.Meta）是由 MetaCubeX 团队维护的高性能规则代理内核，在原版 Clash 的基础上扩展了对众多现代化代理协议、高级路由规则、内置 DNS 以及 TUN 模式的支持，并提供完善的 RESTful API 控制接口。

---

## 🔒 1. 内网访问与防火墙

**Q：如果只在 Linux 服务器局域网 / 内网访问，需要开放公网防火墙吗？**

> **答：不需要！**
> 
> - **云服务器安全组（公网防火墙）**：如果您只在局域网内（或通过内网 IP / VPN / Tailscale 等）访问，**千万不要在公网安全组开放 9090 / 7890 / 7899 端口**，保持关闭即可，这样更加安全！
> - **内网访问方式**：直接通过服务器的**内网 IP**（如 `192.168.x.x` 或 `10.x.x.x`）访问面板和连接 API：
>   - Zashboard 网页：`http://<内网IP>:7899`
>   - Mihomo 控制器 Host：`<内网IP>`，Port：`9090`
> - **Linux 本机防火墙 (ufw/firewalld)**：Docker 容器端口映射通常会在系统防火墙中自动处理内网转发，一般无需额外配置。

---

## 🔗 2. 导入机场订阅链接的两种方法

### 方式 A：通过 `proxy-providers` 自动导入并定时拉取更新（🔥 强烈推荐）

Mihomo 原生支持订阅提供商机制，只需在 `data/config.yaml` 中配置订阅链接，Mihomo 会**自动拉取节点并按设定的时间间隔定时更新**！

在 `data/config.yaml` 中加入：

```yaml
# 1. 配置订阅链接
proxy-providers:
  my-airport:
    type: http
    url: "https://xxxx.com/api/v1/client/subscribe?token=xxxx" # 👈 粘贴你的订阅链接
    interval: 86400 # 每 24 小时自动更新一次
    path: ./proxy_providers/airport.yaml
    health-check:
      enable: true
      interval: 600
      url: https://www.gstatic.com/generate_204

# 2. 策略组中自动引用该订阅的所有节点
proxy-groups:
  - name: PROXY
    type: select
    use:
      - my-airport # 自动引入订阅中的所有节点
    proxies:
      - DIRECT

  - name: 自动优选
    type: url-test
    use:
      - my-airport
    url: https://www.gstatic.com/generate_204
    interval: 300

# 3. 基础分流规则
rules:
  - MATCH,PROXY
```

保存文件后在 1Panel 重启 Mihomo 容器，它就会自动从订阅链接下载全部节点并保持每日自动更新！

---

### 方式 B：使用 curl 命令一键下载整份订阅配置

如果您想直接使用机场提供的完整 Clash 配置文件覆盖：

在服务器终端执行以下命令（将 URL 替换为您的订阅地址）：

```bash
# 进入 1Panel Mihomo 数据目录并下载覆盖
curl -L -o /opt/1panel/apps/mihomo/mihomo/data/config.yaml "https://你的订阅链接"
```

下载完成后，打开 `config.yaml` 确认包含以下两项（用于面板通信）：
```yaml
external-controller: 0.0.0.0:9090
secret: "" # 若设置了密钥需一致
cors:
  allow-origins:
    - '*'
```
最后在 1Panel 中点击 **重启应用** 即可。

---

## 📱 3. 与 Zashboard 面板联动

1. 浏览器访问：`http://<内网IP>:7899`
2. 填写连接配置：
   - **Host**: `<内网IP>`
   - **Port**: `9090`
   - **Secret**: 您在 1Panel 中为 Mihomo 设置的密钥（留空则不填）
3. 即可在 Zashboard 中查看订阅导入的节点并进行节点测速与切换！
