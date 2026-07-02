#!/usr/bin/env bash
#===============================================================================
# sk5 搭建/管理脚本 — 基于 GOST v3.2.6 的 SOCKS5 代理服务一键部署工具
#===============================================================================
set -euo pipefail

# ---- 默认配置 ----------------------------------------------------------------
GOST_VERSION="3.2.6"
GOST_BASE_URL="https://github.com/go-gost/gost/releases/download/v${GOST_VERSION}"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/gost"
CONFIG_FILE="${CONFIG_DIR}/config.yaml"
SERVICE_FILE="/etc/systemd/system/gost.service"
GOST_BIN="${INSTALL_DIR}/gost"

# 默认 SOCKS5 参数
DEFAULT_PORT="2080"
DEFAULT_USER="user4455"
DEFAULT_PASS="passwd4455"

# ---- 颜色输出 ----------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }
section() { echo -e "\n${CYAN}==>${NC} ${CYAN}$*${NC}"; }

# ---- 架构检测 ----------------------------------------------------------------
detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)         echo "amd64" ;;
        aarch64|arm64)  echo "arm64" ;;
        armv7l|armv7)   echo "armv7" ;;
        armv6l|armv6)   echo "armv6" ;;
        i386|i686)      echo "386" ;;
        mips)           echo "mips" ;;
        mips64)         echo "mips64" ;;
        mips64el)       echo "mips64le" ;;
        mipsel)         echo "mipsle" ;;
        riscv64)        echo "riscv64" ;;
        ppc64le)        echo "ppc64le" ;;
        s390x)          echo "s390x" ;;
        *)
            error "不支持的 CPU 架构: $arch"
            error "支持的架构: amd64, arm64, armv7, armv6, 386, mips, mips64, mips64le, mipsle, riscv64, ppc64le, s390x"
            exit 1
            ;;
    esac
}

# ---- 检查 root 权限 ----------------------------------------------------------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "此操作需要 root 权限，请使用 sudo 运行"
        exit 1
    fi
}

# ---- 检查是否已安装 ----------------------------------------------------------
is_installed() {
    if [[ -x "$GOST_BIN" ]] && [[ -f "$SERVICE_FILE" ]]; then
        return 0
    else
        return 1
    fi
}

# ---- 安装 GOST ---------------------------------------------------------------
install_gost() {
    section "开始安装 sk5 (GOST v${GOST_VERSION})"

    check_root

    local arch download_url tmpdir
    arch=$(detect_arch)
    download_url="${GOST_BASE_URL}/gost_${GOST_VERSION}_linux_${arch}.tar.gz"
    tmpdir=$(mktemp -d)

    info "检测到 CPU 架构: ${arch}"
    info "下载地址: ${download_url}"

    # 下载
    info "正在下载 GOST..."
    if ! curl -fSL --connect-timeout 30 --max-time 300 \
        -o "${tmpdir}/gost.tar.gz" "$download_url"; then
        error "下载失败，请检查网络连接或确认该架构版本是否存在"
        error "已尝试 URL: ${download_url}"
        rm -rf "$tmpdir"
        exit 1
    fi

    # 解压
    info "正在解压..."
    tar -xzf "${tmpdir}/gost.tar.gz" -C "$tmpdir"

    # 安装
    info "正在安装到 ${GOST_BIN}..."
    install -m 755 "${tmpdir}/gost" "$GOST_BIN"

    # 创建配置目录
    mkdir -p "$CONFIG_DIR"

    # 生成默认配置文件（如果不存在）
    if [[ ! -f "$CONFIG_FILE" ]]; then
        info "正在生成默认配置文件..."
        write_config "$DEFAULT_PORT" "$DEFAULT_USER" "$DEFAULT_PASS"
    else
        warn "配置文件已存在，跳过生成: ${CONFIG_FILE}"
    fi

    # 创建 systemd 服务
    info "正在创建 systemd 服务..."
    write_service_file

    # 清理
    rm -rf "$tmpdir"

    # 重载 systemd 并启用
    systemctl daemon-reload
    systemctl enable gost

    info "安装完成！"
    echo ""
    info "当前配置："
    echo "  端口:     $(grep 'addr:' "$CONFIG_FILE" | head -1 | awk '{print $2}' | tr -d ':')"
    echo "  用户名:   $(grep 'username:' "$CONFIG_FILE" | awk '{print $2}')"
    echo "  密码:     $(grep 'password:' "$CONFIG_FILE" | awk '{print $2}')"
    echo ""
    info "运行以下命令启动服务："
    echo "  sudo systemctl start gost"
}

# ---- 生成 YAML 配置文件 -------------------------------------------------------
write_config() {
    local port="${1:-$DEFAULT_PORT}"
    local user="${2:-$DEFAULT_USER}"
    local pass="${3:-$DEFAULT_PASS}"

    cat > "$CONFIG_FILE" << EOF
services:
- name: service-0
  addr: :${port}
  handler:
    type: socks5
    auth:
      username: ${user}
      password: ${pass}
    metadata:
      udp: true
      udpBufferSize: 4096
      bind: true
  listener:
    type: tcp
EOF
    info "配置文件已写入: ${CONFIG_FILE}"
}

# ---- 生成 systemd 服务文件 ----------------------------------------------------
write_service_file() {
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=GOST SOCKS5 Proxy Service (sk5)
Documentation=https://gost.run/
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
ExecStart=${GOST_BIN} -C ${CONFIG_FILE}
Restart=on-failure
RestartSec=10s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
    info "systemd 服务文件已写入: ${SERVICE_FILE}"
}

# ---- 卸载 GOST ---------------------------------------------------------------
uninstall_gost() {
    section "卸载 sk5 (GOST)"

    check_root

    if ! is_installed; then
        warn "GOST 未安装，无需卸载"
        return
    fi

    # 停止并禁用服务
    if systemctl is-active --quiet gost 2>/dev/null; then
        info "正在停止 gost 服务..."
        systemctl stop gost
    fi
    if systemctl is-enabled --quiet gost 2>/dev/null; then
        info "正在禁用开机自启..."
        systemctl disable gost
    fi

    # 删除文件
    rm -f "$SERVICE_FILE"
    rm -f "$GOST_BIN"
    rm -rf "$CONFIG_DIR"

    systemctl daemon-reload

    info "卸载完成"
}

# ---- 修改配置 ----------------------------------------------------------------
modify_config() {
    section "修改 sk5 配置"

    check_root

    if ! is_installed; then
        error "GOST 未安装，请先运行: $0 install"
        exit 1
    fi

    local current_port current_user current_pass
    current_port=$(grep 'addr:' "$CONFIG_FILE" | head -1 | awk '{print $2}' | tr -d ':')
    current_user=$(grep 'username:' "$CONFIG_FILE" | awk '{print $2}')
    current_pass=$(grep 'password:' "$CONFIG_FILE" | awk '{print $2}')

    echo "当前配置："
    echo "  1) 端口:     ${current_port}"
    echo "  2) 用户名:   ${current_user}"
    echo "  3) 密码:     ${current_pass}"
    echo ""

    local new_port="$current_port"
    local new_user="$current_user"
    local new_pass="$current_pass"

    # 如果传入了命令行参数，直接使用
    if [[ $# -ge 2 ]]; then
        case "$1" in
            port)    new_port="$2" ;;
            user)    new_user="$2" ;;
            pass)    new_pass="$2" ;;
            *)
                error "未知参数: $1"
                echo "用法: $0 modify port <新端口>"
                echo "用法: $0 modify user <新用户名>"
                echo "用法: $0 modify pass <新密码>"
                exit 1
                ;;
        esac
    else
        # 交互式修改
        read -rp "请输入新端口 [${current_port}]: " input
        new_port="${input:-$current_port}"

        read -rp "请输入新用户名 [${current_user}]: " input
        new_user="${input:-$current_user}"

        read -rp "请输入新密码 [${current_pass}]: " input
        new_pass="${input:-$current_pass}"
    fi

    # 验证端口
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [[ "$new_port" -lt 1 ]] || [[ "$new_port" -gt 65535 ]]; then
        error "无效的端口号: ${new_port}，端口范围 1-65535"
        exit 1
    fi

    # 写入新配置
    write_config "$new_port" "$new_user" "$new_pass"

    # 重启服务
    if systemctl is-active --quiet gost 2>/dev/null; then
        info "正在重启 gost 服务..."
        systemctl restart gost
        info "服务已重启，新配置已生效"
    else
        warn "gost 服务未运行，修改将在下次启动时生效"
    fi

    echo ""
    info "修改后的配置："
    echo "  端口:     ${new_port}"
    echo "  用户名:   ${new_user}"
    echo "  密码:     ${new_pass}"
}

# ---- 状态查看 ----------------------------------------------------------------
show_status() {
    section "sk5 状态"

    if ! is_installed; then
        warn "GOST 未安装"
        exit 1
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  安装状态"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  GOST 版本:   v${GOST_VERSION}"
    echo "  二进制路径:  ${GOST_BIN}"
    echo "  配置文件:    ${CONFIG_FILE}"
    echo ""

    local port user pass
    port=$(grep 'addr:' "$CONFIG_FILE" | head -1 | awk '{print $2}' | tr -d ':')
    user=$(grep 'username:' "$CONFIG_FILE" | awk '{print $2}')
    pass=$(grep 'password:' "$CONFIG_FILE" | awk '{print $2}')

    echo "  SOCKS5 端口: ${port}"
    echo "  用户名:      ${user}"
    echo "  密码:        ${pass}"
    echo ""

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  服务状态"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if systemctl is-active --quiet gost 2>/dev/null; then
        echo -e "  运行状态:    ${GREEN}● 运行中${NC}"
    else
        echo -e "  运行状态:    ${RED}○ 已停止${NC}"
    fi

    if systemctl is-enabled --quiet gost 2>/dev/null; then
        echo -e "  开机自启:    ${GREEN}● 已启用${NC}"
    else
        echo -e "  开机自启:    ${RED}○ 已禁用${NC}"
    fi

    echo ""

    # 显示最近的日志
    if systemctl is-active --quiet gost 2>/dev/null; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  最近日志 (journalctl)"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        journalctl -u gost --no-pager -n 10 2>/dev/null || true
    fi
}

# ---- 启动/停止/重启 ----------------------------------------------------------
svc_start() {
    check_root
    info "正在启动 gost 服务..."
    systemctl start gost
    info "已启动"
}

svc_stop() {
    check_root
    info "正在停止 gost 服务..."
    systemctl stop gost
    info "已停止"
}

svc_restart() {
    check_root
    info "正在重启 gost 服务..."
    systemctl restart gost
    info "已重启"
}

svc_logs() {
    journalctl -u gost -f
}

# ---- 帮助信息 ----------------------------------------------------------------
show_help() {
    cat << EOF
用法: $0 <命令> [参数]

命令:
  install                  安装 GOST (自动检测架构 + 配置 + 开机自启)
  uninstall                卸载 GOST (停止服务 + 删除文件)
  modify [key] [value]     修改配置
  status                   查看安装状态和服务状态
  start                    启动服务
  stop                     停止服务
  restart                  重启服务
  logs                     实时查看服务日志
  help                     显示此帮助信息

修改配置示例:
  $0 modify                          交互式修改（会提示输入）
  $0 modify port 2080                修改端口为 2080
  $0 modify user admin               修改用户名为 admin
  $0 modify pass newpass123          修改密码为 newpass123

安装示例:
  sudo $0 install                    安装 GOST（默认端口 ${DEFAULT_PORT}）

GOST 版本: v${GOST_VERSION}
项目地址: https://github.com/go-gost/gost
EOF
}

# ---- 入口 --------------------------------------------------------------------
main() {
    local cmd="${1:-install}"
    shift || true

    case "$cmd" in
        install)
            install_gost "$@"
            ;;
        uninstall)
            uninstall_gost
            ;;
        modify)
            modify_config "$@"
            ;;
        status)
            show_status
            ;;
        start)
            svc_start
            ;;
        stop)
            svc_stop
            ;;
        restart)
            svc_restart
            ;;
        logs)
            svc_logs
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            error "未知命令: ${cmd}"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
