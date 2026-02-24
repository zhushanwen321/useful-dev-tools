# Debian 系统初始化配置工具

一键式 Debian 系统初始化配置工具，采用 TUI 界面，支持菜单式交互配置。

## 功能特性

- **一键式配置**: 支持交互模式和自动模式
- **国内网络优化**: 内置 Gitee 镜像、国内镜像源等
- **完整备份机制**: 修改前自动备份，支持一键恢复
- **模块化设计**: 可单独执行任意模块

## 支持的模块

| 模块 | 功能 |
|------|------|
| preflight | 前置检查 (权限、系统版本、网络) |
| apt | APT 源配置 (支持国内镜像) |
| locale | Locale 语言设置 |
| timezone | 时区和 NTP 配置 |
| ssh | SSH 安全配置 |
| firewall | 防火墙 (UFW/nftables) |
| fail2ban | Fail2ban 防暴力破解 |
| user | 用户管理 |
| bash | Bash 配置 (别名、代理函数) |
| zsh | Zsh + Oh My Zsh + 插件 |
| docker | Docker 安装和配置 |
| podman | Podman 安装和配置 |

## 快速开始

```bash
# 克隆或下载
git clone https://github.com/yourname/debian-init-tool.git
cd debian-init-tool

# 运行 (需要 root 权限)
sudo ./debian-init.sh
```

## 使用方法

### 交互模式

```bash
sudo ./debian-init.sh
```

### 自动模式

```bash
# 自动配置所有模块
sudo ./debian-init.sh --auto

# 仅配置 SSH 和 Docker
sudo ./debian-init.sh --auto --only ssh,docker

# 跳过 Zsh 配置
sudo ./debian-init.sh --auto --skip zsh
```

### 恢复备份

```bash
# 列出可用备份
sudo ./debian-init.sh --list-backups

# 恢复指定备份
sudo ./debian-init.sh --restore 2026-02-22_10-00-00
```

## 项目结构

```
debian-init-tool/
├── debian-init.sh           # 主入口脚本
├── lib/
│   ├── common.sh            # 公共函数库
│   ├── ui.sh                # TUI 界面函数
│   ├── network.sh           # 网络代理相关
│   ├── backup.sh            # 备份恢复函数
│   └── log.sh               # 日志函数
├── modules/
│   ├── 00_preflight.sh      # 前置检查
│   ├── 01_apt.sh            # APT 源配置
│   └── ...                  # 其他模块
├── config/
│   ├── mirrors.conf         # 镜像源配置
│   ├── plugins.conf         # Zsh 插件列表
│   └── defaults.conf        # 默认值配置
├── data/
│   ├── sources/             # APT 源模板
│   └── templates/           # 配置文件模板
└── logs/
    └── debian-init.log      # 运行日志
```

## 配置持久化

工具会将配置保存到 `/etc/debian-init-tool/config.conf`，包括：

- 代理设置
- 镜像源偏好
- 已完成模块记录

## 备份策略

- 所有修改前自动备份到 `/var/backups/debian-init-tool/`
- 使用时间戳命名，保留最近 5 个备份
- 支持一键恢复

## 国内网络优化

工具内置以下优化策略：

1. **镜像源**: 阿里云、清华、中科大等
2. **Gitee 镜像**: Oh My Zsh、Zsh 插件等
3. **代理支持**: 自动检测和配置代理

## 系统要求

- Debian 11 (Bullseye) 或 Debian 12 (Bookworm)
- Root 权限
- 网络连接 (配置时)

## 命令行选项

```
选项:
    -h, --help          显示帮助信息
    -v, --version       显示版本信息
    -a, --auto          自动模式 (非交互)
    -p, --profile       使用预设配置文件
    -o, --only          仅执行指定模块
    -s, --skip          跳过指定模块
    -r, --restore       恢复备份
    -l, --list-backups  列出可用备份
    --dry-run           模拟运行
    --debug             调试模式
```

## 许可证

MIT License
