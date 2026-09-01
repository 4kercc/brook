# Brook 端口转发与 DDNS 管理脚本 (增强版)

基于 Brook 的 Linux 高性能端口转发一键管理脚本，支持 **TCP/UDP 端口转发**、**DDNS 动态域名解析与自动重载**、**Systemd 守护服务**、**全架构自动适配** 以及 **CLI 命令行极速配置**。

---

## 🌟 核心特性

- ⚡ **命令行极速添加规则**：支持 `bash brooks.sh 10000 1.1.1.1 10000` 单行快速配置，未安装时自动初始化。
- 🔄 **完善的 DDNS 域名支持**：支持以域名作为转发目标，内置 `dig` / `nslookup` / `getent` / `python` 多重容错解析，IP 变动自动平滑重载。
- ����️ **Systemd 标准服务化**：多规则并发管理，自带故障自动拉起与开机自启。
- 🌐 **多架构支持与镜像加速**：自动识别 `x86_64`、`i386`、`arm64`、`armv7`、`mips` 等全平台架构，内置多个镜像源保障下载速度。
- 🔥 **防火墙全自动协同**：智能适配 `iptables`、`ufw` 与 `firewalld`，添加/删除规则自动放行对应端口。

---

## 🚀 快速使用

### 一键运行脚本

```bash
wget -N --no-check-certificate https://raw.githubusercontent.com/4kercc/brook/main/brooks.sh && chmod +x brooks.sh && ./brooks.sh
```

### 1. 命令行快速模式（推荐）

```bash
# 转发本地 10000 端口 到 1.1.1.1 的 10000 端口
bash brooks.sh 10000 1.1.1.1 10000

# 转发本地 10000 端口 到 example.com 的 10000 端口 (支持 DDNS 动态解析)
bash brooks.sh 10000 example.com 10000
```

### 2. 交互式菜单管理

```bash
bash brooks.sh
```

进入终端菜单后，可直接进行安装、更新内核、增删查改转发规则、启停服务、开关 DDNS 动态监控等操作。
