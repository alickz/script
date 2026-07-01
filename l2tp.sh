#!/usr/bin/env bash
#=======================================================================#
#   L2TP/IPSec VPN 一键安装脚本  v2.0                                    #
#   工作室: YUNYI         邮箱: hfyunyi@foxmail.com                       #
#                                                                       #
#   支持的 IPsec 实现:                                                   #
#     RHEL 8+ : strongSwan (解决 libreswan 4.x 不支持 modp1024 问题)     #
#     RHEL 7 / Debian / Ubuntu : libreswan                               #
#                                                                       #
#   支持系统:  CentOS 7 / Rocky 8-9 / Alma 8-9 / Debian 10-12 /         #
#             Ubuntu 20.04-24.04                                        #
#=======================================================================#

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

cur_dir=$(pwd)
SCRIPT_VER="2.0"

#============================ 工具函数 ==================================#

# 检查 root 权限
rootness(){
    if [[ $EUID -ne 0 ]]; then
        echo "错误: 本脚本必须以 root 身份运行！" 1>&2
        exit 1
    fi
}

# 检查 TUN/TAP 设备
tunavailable(){
    if [[ ! -e /dev/net/tun ]]; then
        echo "错误: TUN/TAP 设备不可用！" 1>&2
        exit 1
    fi
}

# 禁用 SELinux
disable_selinux(){
    if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
        setenforce 0
    fi
}

# 获取操作系统名称
get_opsy(){
    if [ -f /etc/os-release ]; then
        awk -F'[= "]' '/PRETTY_NAME/{print $3,$4,$5}' /etc/os-release && return
    fi
    [ -f /etc/redhat-release ] && awk '{print ($1,$3~/^[0-9]/?$3:$4)}' /etc/redhat-release && return
    [ -f /etc/lsb-release ] && awk -F'[="]+' '/DESCRIPTION/{print $2}' /etc/lsb-release && return
}

# 获取系统信息
get_os_info(){
    # 获取服务器 IP（优先公网，fallback 任意非 lo 地址）
    IP=$( ip addr | egrep -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' \
        | egrep -v "^192\.168|^172\.1[6-9]\.|^172\.2[0-9]\.|^172\.3[0-2]\.|^10\.|^127\.|^255\.|^0\." \
        | head -n 1 )
    [ -z "${IP}" ] && IP=$( wget -qO- -t1 -T2 ipv4.icanhazip.com 2>/dev/null )
    [ -z "${IP}" ] && IP=$( curl -s -m 2 ipv4.icanhazip.com 2>/dev/null )
    [ -z "${IP}" ] && IP=$( wget -qO- -t1 -T2 ifconfig.me 2>/dev/null )
    [ -z "${IP}" ] && IP=$( curl -s -m 2 ifconfig.me 2>/dev/null )
    # 还没有就用第一个非 lo 的内网地址
    [ -z "${IP}" ] && IP=$( ip addr | egrep -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | grep -v '^127\.' | head -n 1 )

    local cname=$( awk -F: '/model name/ {name=$2} END {print name}' /proc/cpuinfo | sed 's/^[ \t]*//;s/[ \t]*$//' )
    local cores=$( awk -F: '/model name/ {core++} END {print core}' /proc/cpuinfo )
    local freq=$( awk -F: '/cpu MHz/ {freq=$2} END {print freq}' /proc/cpuinfo | sed 's/^[ \t]*//;s/[ \t]*$//' )
    local tram=$( free -m | awk '/Mem/ {print $2}' )
    local swap=$( free -m | awk '/Swap/ {print $2}' )
    local up=$( awk '{a=$1/86400;b=($1%86400)/3600;c=($1%3600)/60;d=$1%60} {printf("%d天 %d:%d:%d\n",a,b,c,d)}' /proc/uptime )
    local load=$( w | head -1 | awk -F'load average:' '{print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//' )
    local opsy=$( get_opsy )
    local arch=$( uname -m )
    local lbit=$( getconf LONG_BIT )
    local host=$( hostname )
    local kern=$( uname -r )

    echo "########## 系统信息 ##########"
    echo
    echo "CPU 型号            : ${cname}"
    echo "CPU 核心数          : ${cores}"
    echo "CPU 频率            : ${freq} MHz"
    echo "内存总量            : ${tram} MB"
    echo "交换分区总量        : ${swap} MB"
    echo "系统运行时间        : ${up}"
    echo "系统负载            : ${load}"
    echo "操作系统            : ${opsy}"
    echo "架构                : ${arch} (${lbit} 位)"
    echo "内核版本            : ${kern}"
    echo "主机名              : ${host}"
    echo "IPv4 地址           : ${IP}"
    echo
    echo "########################################"
}

#=========================== 系统检测 ===================================#

# 检测操作系统 ID
detect_os_id(){
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "${ID}"
    elif [ -f /etc/redhat-release ]; then
        echo "centos"
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        echo "${DISTRIB_ID}" | tr '[:upper:]' '[:lower:]'
    else
        echo "unknown"
    fi
}

# 检测操作系统版本号
detect_os_version(){
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "${VERSION_ID}" | grep -oE '[0-9]+' | head -n 1
    elif [ -f /etc/redhat-release ]; then
        grep -oE '[0-9]+' /etc/redhat-release | head -n 1
    else
        echo "0"
    fi
}

# 检测包管理器
detect_pkg_manager(){
    local os_id=$(detect_os_id)
    local os_ver=$(detect_os_version)

    case "${os_id}" in
        centos|rocky|almalinux|rhel|ol|fedora|tencentos|anolis|opencloudos)
            if [ "${os_ver}" -ge 8 ] 2>/dev/null; then
                echo "dnf"
            else
                echo "yum"
            fi
            ;;
        debian|ubuntu|deepin|uos)
            echo "apt"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# 检查是否为 RHEL 系
is_rhel_family(){
    local os_id=$(detect_os_id)
    case "${os_id}" in
        centos|rocky|almalinux|rhel|ol|fedora|tencentos|anolis|opencloudos)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# 检查是否为 Debian 系
is_debian_family(){
    local os_id=$(detect_os_id)
    case "${os_id}" in
        debian|ubuntu|deepin|uos)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# 版本支持检查
version_check(){
    local os_id=$(detect_os_id)
    local os_ver=$(detect_os_version)

    echo "检测到系统: ${os_id} (主版本: ${os_ver})"

    case "${os_id}" in
        centos|rhel|ol)
            if [ "${os_ver}" -lt 7 ] 2>/dev/null; then
                echo "错误: CentOS/RHEL ${os_ver} 不受支持，请使用 CentOS 7 或更高版本，或迁移至 Rocky/Alma Linux。"
                exit 1
            fi
            if [ "${os_ver}" -eq 8 ]; then
                echo "警告: CentOS 8 已停止维护，建议迁移至 Rocky Linux 8 或 AlmaLinux 8。"
                echo "继续安装请按任意键，或 Ctrl+C 取消..."
                local _char=$(get_char)
            fi
            ;;
        rocky|almalinux|tencentos|anolis|opencloudos)
            if [ "${os_ver}" -lt 8 ] 2>/dev/null; then
                echo "错误: ${os_id} ${os_ver} 不受支持，请使用 8 或更高版本。"
                exit 1
            fi
            ;;
        debian)
            if [ "${os_ver}" -lt 10 ] 2>/dev/null; then
                echo "错误: Debian ${os_ver} 不受支持，请使用 Debian 10 或更高版本。"
                exit 1
            fi
            ;;
        ubuntu)
            if [ "${os_ver}" -lt 20 ] 2>/dev/null; then
                echo "错误: Ubuntu ${os_ver} 不受支持，请使用 Ubuntu 20.04 或更高版本。"
                exit 1
            fi
            ;;
        *)
            echo "警告: 未能识别系统 (${os_id})，安装可能失败。"
            echo "继续安装请按任意键，或 Ctrl+C 取消..."
            local _char=$(get_char)
            ;;
    esac
}

#=========================== 辅助函数 ===================================#

# 生成随机密码
rand(){
    local chars="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local str=""
    for i in {1..12}; do
        str="${str}${chars:$(( RANDOM % 62 )):1}"
    done
    echo "${str}"
}

# 读取单个字符
get_char(){
    local savedstty=$(stty -g)
    stty -echo
    stty cbreak
    dd if=/dev/tty bs=1 count=1 2> /dev/null
    stty -raw
    stty echo
    stty "${savedstty}"
}

# 获取主网卡名称
get_primary_nic(){
    local nic=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}')
    if [ -z "${nic}" ]; then
        nic=$(ip link | grep -E '^[0-9]+:' | grep -v 'lo:' | head -n 1 | awk -F': ' '{print $2}' | awk '{print $1}')
    fi
    echo "${nic}"
}

# 检查服务是否正常启动，如内核模块缺失则提示重启
# 修复云厂商安全加固屏蔽 ESP 模块的问题
fix_esp_module(){
    # 检测并移除 modprobe.d 中屏蔽 esp4/esp6 的规则
    if grep -q 'install esp4 /bin/false' /etc/modprobe.d/*.conf 2>/dev/null; then
        echo "检测到 ESP 内核模块被屏蔽，正在修复..."
        sed -i '/install esp4 \/bin\/false/d' /etc/modprobe.d/*.conf 2>/dev/null
        sed -i '/install esp6 \/bin\/false/d' /etc/modprobe.d/*.conf 2>/dev/null
        modprobe esp4 2>/dev/null
        modprobe esp6 2>/dev/null
        echo "ESP 模块已启用。"
    fi
}

check_service_status(){
    echo
    systemctl status xl2tpd > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "\033[43;37m 注意: \033[0m xl2tpd 服务启动失败，可能原因："
        echo "  1. 内核模块 l2tp_ppp 未加载（安装了新内核但尚未重启）"
        echo "  2. 内核不支持 L2TP"
        echo
        modprobe l2tp_ppp 2>/dev/null
        if [ $? -ne 0 ]; then
            # 检查内核版本是否和已安装的内核包匹配
            local running_kernel=$(uname -r)
            local installed_kernel=""
            if [ -d /lib/modules ]; then
                installed_kernel=$(ls -1 /lib/modules/ 2>/dev/null | sort -V | tail -1)
            fi
            if [ "${running_kernel}" != "${installed_kernel}" ] && [ -n "${installed_kernel}" ]; then
                echo -e "\033[42;37m 建议: \033[0m 检测到已安装内核 ${installed_kernel}，当前运行 ${running_kernel}"
                echo "请执行 reboot 重启系统以加载新内核，重启后 L2TP VPN 将自动运行。"
            else
                echo "请尝试重启系统: reboot"
            fi
        else
            systemctl restart xl2tpd 2>/dev/null
            echo "内核模块已加载，已重新启动 xl2tpd 服务。"
        fi
    else
        echo "xl2tpd 服务运行正常。"
    fi
    echo
}

# 检测系统是否已安装 L2TP
is_installed(){
    if systemctl is-enabled ipsec &>/dev/null || systemctl is-enabled strongswan &>/dev/null || systemctl is-enabled xl2tpd &>/dev/null; then
        return 0
    fi
    if [ -f /etc/ipsec.conf ] || [ -f /etc/strongswan/swanctl/conf.d/l2tp.conf ] || [ -f /etc/xl2tpd/xl2tpd.conf ]; then
        return 0
    fi
    return 1
}

# 清理旧安装（停止服务、移除防火墙规则、删除配置文件）
clean_previous_install(){
    echo "正在停止服务..."
    systemctl stop ipsec 2>/dev/null
    systemctl stop strongswan 2>/dev/null
    systemctl stop xl2tpd 2>/dev/null
    systemctl disable ipsec 2>/dev/null
    systemctl disable strongswan 2>/dev/null
    systemctl disable xl2tpd 2>/dev/null

    echo "正在移除防火墙规则..."
    if is_rhel_family && command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --remove-service=ipsec 2>/dev/null
        firewall-cmd --permanent --remove-service=xl2tpd 2>/dev/null
        firewall-cmd --permanent --remove-masquerade 2>/dev/null
        firewall-cmd --reload 2>/dev/null
        rm -f /etc/firewalld/services/xl2tpd.xml
    fi

    echo "正在移除配置文件..."
    rm -f /etc/ipsec.conf /etc/ipsec.secrets
    rm -f /etc/strongswan/swanctl/conf.d/l2tp.conf
    rm -f /etc/xl2tpd/xl2tpd.conf
    rm -f /etc/ppp/options.xl2tpd /etc/ppp/chap-secrets
    rm -f /etc/sysctl.d/99-l2tp.conf
    rm -f /etc/iptables/rules.v4
    rm -f /etc/iptables/restore-rules.sh
    rm -f /etc/systemd/system/iptables-restore.service
    rm -f /etc/network/if-up.d/iptables

    echo "旧配置已清理完毕。"
    echo
}

# 处理已安装情况：提示用户选择
handle_existing_install(){
    # 非交互终端直接退出
    if [ ! -t 0 ]; then
        echo
        echo "检测到系统已安装 L2TP VPN，非交互模式无法继续。"
        echo "请在终端中直接运行脚本，或使用 l2tp -a/-d/-l/-m 管理用户。"
        echo
        exit 1
    fi

    echo
    echo "======================================================"
    echo "  检测到系统已安装 L2TP VPN，请选择操作:"
    echo "======================================================"
    echo "  1) 清理旧配置并重新安装（将覆盖所有配置）"
    echo "  2) 仅管理用户（添加/删除/修改/查看）"
    echo "  3) 退出"
    echo
    while :
    do
        read -p "请输入选项 (1/2/3): " choice
        case "${choice}" in
            1)
                echo
                clean_previous_install
                # 清理后继续安装流程
                return 0
                ;;
            2)
                echo
                echo "用户管理功能无需重新安装，请使用以下命令:"
                echo "  l2tp -a    添加用户"
                echo "  l2tp -d    删除用户"
                echo "  l2tp -l    列出所有用户"
                echo "  l2tp -m    修改用户密码"
                echo
                exit 0
                ;;
            3)
                echo "已退出。"
                exit 0
                ;;
            *)
                echo "无效选项，请输入 1、2 或 3。"
                ;;
        esac
    done
}

# 检测 Docker 是否在运行（Docker 与 firewalld 冲突，需要改用 iptables）
is_docker_present(){
    if command -v docker &>/dev/null && (systemctl is-active docker &>/dev/null || ps aux | grep -v grep | grep -q docker); then
        return 0
    fi
    return 1
}

#=========================== 安装前交互 ==================================#

preinstall_l2tp(){
    # 非交互终端检查
    if [ ! -t 0 ]; then
        echo "错误: 本脚本需要交互终端才能完成安装，请直接在终端中运行。"
        exit 1
    fi

    echo
    if [ -d "/proc/vz" ]; then
        echo -e "\033[41;37m 警告: \033[0m 您的 VPS 基于 OpenVZ，IPSec 可能不被内核支持。"
        echo "是否继续安装？(y/n)"
        read -p "(默认: n): " agree
        [ -z "${agree}" ] && agree="n"
        if [ "${agree}" == "n" ]; then
            echo
            echo "L2TP 安装已取消。"
            echo
            exit 0
        fi
    fi
    echo

    # IP 自动检测失败时提示手动输入
    if [ -z "${IP}" ]; then
        echo "未能自动检测到服务器 IP 地址，请手动输入:"
        read -p "" IP
        while [ -z "${IP}" ]; do
            echo "IP 地址不能为空，请重新输入:"
            read -p "" IP
        done
    fi

    echo "请输入客户端 IP 地址段:"
    read -p "(默认: 100.0.1): " iprange
    [ -z "${iprange}" ] && iprange="100.0.1"

    echo "请输入预共享密钥 (PSK):"
    read -p "(默认: alick): " mypsk
    [ -z "${mypsk}" ] && mypsk="alick"

    echo "请输入用户名:"
    read -p "(默认: alick): " username
    [ -z "${username}" ] && username="alick"

    password=$(rand)
    echo "请输入 ${username} 的密码:"
    read -p "(默认: ${password}): " tmppassword
    [ ! -z "${tmppassword}" ] && password="${tmppassword}"

    echo
    echo "============================================"
    echo "服务器公网 IP       : ${IP}"
    echo "服务器本地 IP       : ${iprange}.1"
    echo "客户端 IP 范围      : ${iprange}.2-${iprange}.254"
    echo "预共享密钥 (PSK)    : ${mypsk}"
    echo "用户名              : ${username}"
    echo "密码                : ${password}"
    echo "============================================"
    echo
    echo "按任意键开始安装... 或按 Ctrl+C 取消。"
    local _char=$(get_char)
}

#=========================== 配置文件生成 ===============================#

# libreswan 配置（RHEL 7 / Debian / Ubuntu）
generate_configs_libreswan(){
    cat > /etc/ipsec.conf <<EOF
version 2.0

config setup
    protostack=netkey
    uniqueids=no
    ikev1-policy=accept
    virtual_private=%v4:10.0.0.0/8,%v4:192.168.0.0/16,%v4:172.16.0.0/12,%v4:!${iprange}.0/24

conn L2TP-PSK
    type=transport
    left=%defaultroute
    leftid=${IP}
    leftprotoport=17/1701
    right=%any
    rightprotoport=17/%any
    rightsubnet=vhost:%priv,%no
    authby=secret
    pfs=no
    auto=add
    rekey=no
    ikelifetime=8h
    keylife=1h
    keyingtries=3
    ikev2=never
    dpddelay=40
    dpdtimeout=130
    dpdaction=clear
EOF

    cat > /etc/ipsec.secrets <<EOF
%any %any : PSK "${mypsk}"
EOF
}

# strongSwan 配置（RHEL 8+）
generate_configs_strongswan(){
    mkdir -p /etc/strongswan/swanctl/conf.d

    cat > /etc/strongswan/swanctl/conf.d/l2tp.conf <<EOF
connections {
    L2TP-PSK {
        version = 1
        proposals = aes256-sha1-modp2048,aes128-sha1-modp2048,aes256-sha1-modp1024,aes128-sha1-modp1024
        unique = never
        keyingtries = 3
        rekey_time = 0s
        over_time = 8h

        local {
            auth = psk
            id = ${IP}
        }
        remote {
            auth = psk
        }
        children {
            l2tp {
                mode = transport
                local_ts = dynamic[17/1701]
                remote_ts = dynamic[17/1701]
                esp_proposals = aes256-sha1-modp1024,aes128-sha1-modp1024,aes256-sha1,aes128-sha1
                life_time = 1h
                rekey_time = 0s
                dpd_action = clear
            }
        }
    }
}

secrets {
    ike-l2tp {
        secret = "${mypsk}"
    }
}
EOF
    chmod 640 /etc/strongswan/swanctl/conf.d/l2tp.conf
}

# xl2tpd + PPP + CHAP 配置（libreswan 和 strongSwan 共用）
generate_configs_l2tp(){
    cat > /etc/xl2tpd/xl2tpd.conf <<EOF
[global]
port = 1701

[lns default]
ip range = ${iprange}.2-${iprange}.254
local ip = ${iprange}.1
require chap = yes
refuse pap = yes
require authentication = yes
name = l2tpd
ppp debug = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

    # PPP 配置
    cat > /etc/ppp/options.xl2tpd <<EOF
ipcp-accept-local
ipcp-accept-remote
require-mschap-v2
ms-dns 8.8.8.8
ms-dns 8.8.4.4
noccp
auth
hide-password
idle 1800
mtu 1410
mru 1410
nodefaultroute
debug
proxyarp
connect-delay 5000
EOF

    # CHAP 认证
    rm -f /etc/ppp/chap-secrets
    cat > /etc/ppp/chap-secrets <<EOF
# Secrets for authentication using CHAP
# client    server    secret    IP addresses
${username}    l2tpd    ${password}       *
EOF
}

#=========================== 内核参数配置 ===============================#

setup_sysctl(){
    local sysctl_file="/etc/sysctl.d/99-l2tp.conf"

    cat > "${sysctl_file}" <<EOF
# L2TP VPN 内核参数
net.ipv4.ip_forward = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
EOF

    for each in $(ls /proc/sys/net/ipv4/conf/); do
        echo "net.ipv4.conf.${each}.accept_source_route=0" >> "${sysctl_file}"
        echo "net.ipv4.conf.${each}.accept_redirects=0" >> "${sysctl_file}"
        echo "net.ipv4.conf.${each}.send_redirects=0" >> "${sysctl_file}"
        echo "net.ipv4.conf.${each}.rp_filter=0" >> "${sysctl_file}"
    done

    sysctl -p "${sysctl_file}" > /dev/null 2>&1
    # 兼容：同时写入 /etc/sysctl.conf
    if [ -f /etc/sysctl.conf ]; then
        cp -f /etc/sysctl.conf /etc/sysctl.conf.bak.$(date +%Y%m%d%H%M%S) 2>/dev/null
        sed -i 's/net.ipv4.ip_forward = 0/net.ipv4.ip_forward = 1/g' /etc/sysctl.conf 2>/dev/null
        sysctl -p > /dev/null 2>&1
    fi
}

#=========================== 防火墙配置 ==================================#

setup_firewall_rhel(){
    # RHEL 系使用 firewalld
    systemctl enable firewalld

    # 添加 xl2tpd 服务定义
    if [ ! -f /etc/firewalld/services/xl2tpd.xml ]; then
        cat > /etc/firewalld/services/xl2tpd.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<service>
  <short>xl2tpd</short>
  <description>L2TP IPSec VPN</description>
  <port protocol="udp" port="500"/>
  <port protocol="udp" port="4500"/>
  <port protocol="udp" port="1701"/>
</service>
EOF
        chmod 640 /etc/firewalld/services/xl2tpd.xml
    fi

    systemctl status firewalld > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "firewalld 正在运行，添加防火墙规则..."
        firewall-cmd --reload > /dev/null 2>&1
        firewall-cmd --permanent --add-service=ipsec
        firewall-cmd --permanent --add-service=xl2tpd
        firewall-cmd --permanent --add-masquerade
        firewall-cmd --reload
        echo "防火墙规则添加完成。"
        firewall-cmd --list-all
    else
        echo "firewalld 未运行，尝试启动..."
        systemctl start firewalld
        if [ $? -eq 0 ]; then
            echo "firewalld 启动成功。"
            firewall-cmd --permanent --add-service=ipsec
            firewall-cmd --permanent --add-service=xl2tpd
            firewall-cmd --permanent --add-masquerade
            firewall-cmd --reload
            echo "防火墙规则添加完成。"
            firewall-cmd --list-all
        else
            echo "警告: firewalld 启动失败，请手动放行 UDP 端口 500、4500、1701。"
        fi
    fi
}

setup_firewall_debian(){
    # Debian 系使用 iptables
    local nic=$(get_primary_nic)

    echo "正在配置 iptables 防火墙..."

    # 备份现有规则
    if [ -f /etc/iptables.rules ]; then
        cp -pf /etc/iptables.rules /etc/iptables.rules.bak.$(date +%Y%m%d%H%M%S)
    fi

    # 清理并重建规则
    iptables -F 2>/dev/null
    iptables -X 2>/dev/null
    iptables -t nat -F 2>/dev/null
    iptables -t nat -X 2>/dev/null

    # 基础规则
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT

    iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -A INPUT -p icmp -j ACCEPT
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    iptables -A INPUT -p udp -m multiport --dports 500,4500,1701 -j ACCEPT

    iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -s ${iprange}.0/24 -j ACCEPT

    iptables -t nat -A POSTROUTING -s ${iprange}.0/24 -j SNAT --to-source ${IP}

    # 保存规则
    mkdir -p /etc/iptables/
    iptables-save > /etc/iptables/rules.v4

    # 创建开机自启脚本
    cat > /etc/iptables/restore-rules.sh <<EOF
#!/bin/sh
/sbin/iptables-restore < /etc/iptables/rules.v4
EOF
    chmod +x /etc/iptables/restore-rules.sh

    # 创建 systemd 服务
    cat > /etc/systemd/system/iptables-restore.service <<EOF
[Unit]
Description=Restore iptables rules
After=network.target

[Service]
Type=oneshot
ExecStart=/etc/iptables/restore-rules.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable iptables-restore.service

    # 同时尝试 ip up 钩子方式作为备用
    mkdir -p /etc/network/if-up.d/
    cat > /etc/network/if-up.d/iptables <<EOD
#!/bin/sh
/sbin/iptables-restore < /etc/iptables/rules.v4
EOD
    chmod +x /etc/network/if-up.d/iptables

    echo "iptables 防火墙配置完成。"
}

#=========================== NSS 数据库初始化 ===========================#

init_nss_db(){
    # 初始化 NSS 证书数据库（如果不存在）
    if [ ! -f /etc/ipsec.d/cert9.db ] && [ ! -f /etc/ipsec.d/cert8.db ]; then
        echo "正在初始化 NSS 证书数据库..."
        # 尝试使用 ipsec initnss（libreswan 3.23+）
        if command -v ipsec &> /dev/null; then
            ipsec initnss 2>/dev/null
        fi
        # 如果仍未创建，手动创建
        if [ ! -f /etc/ipsec.d/cert9.db ] && [ ! -f /etc/ipsec.d/cert8.db ]; then
            echo "手动创建 NSS 数据库..."
            echo "" > /var/tmp/libreswan-nss-pwd 2>/dev/null
            certutil -N -f /var/tmp/libreswan-nss-pwd -d sql:/etc/ipsec.d 2>/dev/null || \
            certutil -N -f /var/tmp/libreswan-nss-pwd -d /etc/ipsec.d 2>/dev/null
            rm -f /var/tmp/libreswan-nss-pwd
        fi
    fi
}

#========================= RHEL 系安装 ==================================#

# 配置 EPEL 仓库，自动检测并切换到国内镜像
configure_epel(){
    local os_ver=$(detect_os_version)
    local pkg_mgr=$(detect_pkg_manager)

    echo "正在配置 EPEL 仓库..."
    ${pkg_mgr} -y install epel-release 2>/dev/null

    # 检测 EPEL 是否可用
    ${pkg_mgr} makecache --refresh 2>&1 | tail -1
    if ${pkg_mgr} repolist epel 2>&1 | grep -qi 'epel'; then
        echo "EPEL 仓库连接正常。"
        return 0
    fi

    # EPEL 不可用，根据版本切换镜像
    echo "默认 EPEL 仓库不可用，切换备用镜像..."

    if [ "${os_ver}" -eq 7 ] 2>/dev/null; then
        # CentOS/RHEL 7 已 EOL，EPEL 移入存档
        cat > /etc/yum.repos.d/epel-aliyun.repo <<REPO
[epel-aliyun]
name=Extra Packages for Enterprise Linux 7 - AliYun Vault
baseurl=https://mirrors.aliyun.com/epel-archive/7/x86_64/
        https://archives.fedoraproject.org/pub/archive/epel/7/x86_64/
enabled=1
gpgcheck=0
REPO
    else
        # EL8+ 使用阿里云 EPEL 镜像
        cat > /etc/yum.repos.d/epel-aliyun.repo <<REPO
[epel-aliyun]
name=Extra Packages for Enterprise Linux \$releasever - AliYun
baseurl=https://mirrors.aliyun.com/epel/\$releasever/Everything/\$basearch/
enabled=1
gpgcheck=0
REPO
    fi

    # 禁用失败的默认 epel 仓库
    if [ -f /etc/yum.repos.d/epel.repo ]; then
        sed -i 's/^enabled=1/enabled=0/' /etc/yum.repos.d/epel.repo 2>/dev/null
    fi
    # 禁用 epel-cisco-openh264（国内通常连不上）
    if [ -f /etc/yum.repos.d/epel-cisco-openh264.repo ]; then
        sed -i 's/^enabled=1/enabled=0/' /etc/yum.repos.d/epel-cisco-openh264.repo 2>/dev/null
    fi

    ${pkg_mgr} makecache 2>&1 | tail -3
    echo "已切换至备用 EPEL 镜像。"
}

install_rhel(){
    local os_ver=$(detect_os_version)
    local pkg_mgr=$(detect_pkg_manager)

    echo "使用 ${pkg_mgr} 安装依赖..."

    # 配置 EPEL 仓库（自动切换国内镜像）
    configure_epel

    # RHEL 8+ 用 strongSwan（libreswan 4.x 不支持 modp1024，Windows L2TP 客户端无法连接）
    if [ "${os_ver}" -ge 8 ] 2>/dev/null; then
        local pkgs="strongswan xl2tpd firewalld ppp"
        echo "正在安装 L2TP/IPSec 相关软件包 (strongSwan)..."
        echo "注意: 如果系统较旧，dnf 可能会连带升级依赖包（如 openssl、systemd 等）"
        ${pkg_mgr} -y install ${pkgs}

        if [ $? -ne 0 ]; then
            echo "错误: 软件包安装失败，请检查网络及软件源配置。"
            exit 1
        fi

        # 生成 strongSwan + L2TP 配置
        generate_configs_strongswan
        generate_configs_l2tp

        # 内核参数
        setup_sysctl

        # 防火墙
        if is_docker_present; then
            echo "检测到 Docker，改用 iptables 代替 firewalld..."
            systemctl disable firewalld 2>/dev/null
            systemctl stop firewalld 2>/dev/null
            setup_firewall_debian
        else
            setup_firewall_rhel
        fi

        # 停用 libreswan（如已安装），启用 strongSwan
        systemctl disable ipsec 2>/dev/null
        systemctl stop ipsec 2>/dev/null
        systemctl enable strongswan
        systemctl enable xl2tpd

        echo "正在启动服务..."
        systemctl restart strongswan
        systemctl restart xl2tpd

        echo "服务启动完成。"

    else
        # RHEL 7 使用 libreswan
        local pkgs="libreswan xl2tpd firewalld ppp"
        echo "正在安装 L2TP/IPSec 相关软件包 (libreswan)..."
        ${pkg_mgr} -y install ${pkgs}

        if [ $? -ne 0 ]; then
            echo "错误: 软件包安装失败，请检查网络及软件源配置。"
            exit 1
        fi

        # 生成 libreswan + L2TP 配置
        generate_configs_libreswan
        generate_configs_l2tp

        # 内核参数
        setup_sysctl

        # 防火墙
        if is_docker_present; then
            echo "检测到 Docker，改用 iptables 代替 firewalld..."
            systemctl disable firewalld 2>/dev/null
            systemctl stop firewalld 2>/dev/null
            setup_firewall_debian
        else
            setup_firewall_rhel
        fi

        # NSS 数据库
        init_nss_db

        # 启用服务
        systemctl enable ipsec
        systemctl enable xl2tpd

        echo "正在启动服务..."
        systemctl restart ipsec
        systemctl restart xl2tpd

        echo "服务启动完成。"
    fi

    # 修复 ESP 模块屏蔽、检查服务状态
    fix_esp_module
    check_service_status
}

#========================= Debian 系安装 ================================#

install_debian(){
    local os_id=$(detect_os_id)

    # 如果为 Ubuntu，启用 universe 仓库
    if [ "${os_id}" == "ubuntu" ]; then
        add-apt-repository -y universe 2>/dev/null
    fi

    echo "正在更新软件包列表..."
    apt-get -y update

    # 安装必要的包
    local pkgs="libreswan xl2tpd iptables ppp wget"
    echo "正在安装 L2TP/IPSec 相关软件包..."
    apt-get -y install ${pkgs}

    if [ $? -ne 0 ]; then
        echo "错误: 软件包安装失败，请检查网络及软件源配置。"
        exit 1
    fi

    # 生成配置
    generate_configs_libreswan
    generate_configs_l2tp

    # 内核参数
    setup_sysctl

    # 防火墙
    setup_firewall_debian

    # NSS 数据库
    init_nss_db

    # 启用服务
    systemctl enable ipsec 2>/dev/null
    systemctl enable xl2tpd 2>/dev/null

    # 更新 rc.local（备用方式）
    if [ -f /etc/rc.local ]; then
        cp -f /etc/rc.local /etc/rc.local.bak.$(date +%Y%m%d%H%M%S) 2>/dev/null
        sed --follow-symlinks -i -e '/^exit 0/d' /etc/rc.local 2>/dev/null
        cat >> /etc/rc.local <<EOF

# L2TP VPN
echo 1 > /proc/sys/net/ipv4/ip_forward
/sbin/iptables-restore < /etc/iptables/rules.v4
/usr/sbin/ipsec start
exit 0
EOF
        chmod +x /etc/rc.local
    fi

    # 立即生效
    echo 1 > /proc/sys/net/ipv4/ip_forward
    iptables-restore < /etc/iptables/rules.v4 2>/dev/null

    # 启动服务
    echo "正在启动服务..."
    systemctl restart ipsec 2>/dev/null
    systemctl restart xl2tpd 2>/dev/null

    echo "服务启动完成。"

    # 检查服务状态
    check_service_status
}

#========================= 安装入口 ======================================#

install_l2tp(){
    if is_rhel_family; then
        echo "检测到 RHEL 系列系统，使用 $(detect_pkg_manager) 包管理器安装..."
        install_rhel
    elif is_debian_family; then
        echo "检测到 Debian 系列系统，使用 apt 包管理器安装..."
        install_debian
    else
        echo "错误: 无法识别的操作系统，安装中止。"
        exit 1
    fi
}

#========================= 安装完成 ======================================#

finally(){
    cd "${cur_dir}"

    # 复制自身到 /usr/bin 方便后续管理
    cp -f "${cur_dir}/$(basename $0)" /usr/bin/l2tp 2>/dev/null

    echo "请稍候..."
    sleep 3

    echo
    echo "======================= 连接验证 ======================="
    if systemctl is-active strongswan &>/dev/null; then
        echo "strongSwan 已运行，当前连接状态:"
        swanctl --list-sas 2>&1 | grep -E 'ESTABLISHED|INSTALLED|bytes' || echo "  暂无活动连接（等待客户端连接后可见）"
    elif systemctl is-active ipsec &>/dev/null; then
        ipsec verify 2>&1
    fi
    echo "========================================================="
    echo

    echo "###############################################################"
    echo "#                L2TP VPN 一键安装脚本  v${SCRIPT_VER}                    #"
    echo "#  RHEL 8+ : strongSwan (modp1024支持)                        #"
    echo "#  RHEL 7 / Debian / Ubuntu : libreswan                       #"
    echo "###############################################################"
    echo

    echo "您可以使用以下信息连接 L2TP VPN:"
    echo
    echo "服务器 IP         : ${IP}"
    echo "预共享密钥 (PSK)  : ${mypsk}"
    echo "用户名            : ${username}"
    echo "密码              : ${password}"
    echo
    echo "如需管理用户，请使用以下命令:"
    echo "  l2tp -a    添加用户"
    echo "  l2tp -d    删除用户"
    echo "  l2tp -l    列出所有用户"
    echo "  l2tp -m    修改用户密码"
    echo
    echo "祝使用愉快！"
    echo
}

#========================================================================#
#                          用户管理功能                                    #
#========================================================================#

list_users(){
    if [ ! -f /etc/ppp/chap-secrets ]; then
        echo "错误: /etc/ppp/chap-secrets 文件不存在。"
        exit 1
    fi
    local line="+-------------------------------------------+\n"
    local string=%20s
    printf "${line}|${string} |${string} |\n${line}" 用户名 密码
    grep -v "^#" /etc/ppp/chap-secrets | awk '{printf "|'${string}' |'${string}' |\n", $1, $3}'
    printf ${line}
}

add_user(){
    while :
    do
        read -p "请输入用户名: " user
        if [ -z "${user}" ]; then
            echo "用户名不能为空！"
        else
            grep -w "${user}" /etc/ppp/chap-secrets > /dev/null 2>&1
            if [ $? -eq 0 ]; then
                echo "用户名 (${user}) 已存在，请重新输入。"
            else
                break
            fi
        fi
    done
    local pass=$(rand)
    echo "请输入 ${user} 的密码:"
    read -p "(默认密码: ${pass}): " tmppass
    [ ! -z "${tmppass}" ] && pass="${tmppass}"
    echo "${user}    l2tpd    ${pass}       *" >> /etc/ppp/chap-secrets
    echo "用户名 (${user}) 添加成功。"
}

del_user(){
    while :
    do
        read -p "请输入要删除的用户名: " user
        if [ -z "${user}" ]; then
            echo "用户名不能为空！"
        else
            grep -w "${user}" /etc/ppp/chap-secrets >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                break
            else
                echo "用户名 (${user}) 不存在，请重新输入。"
            fi
        fi
    done
    sed -i "/^\<${user}\>/d" /etc/ppp/chap-secrets
    echo "用户名 (${user}) 已删除。"
}

mod_user(){
    while :
    do
        read -p "请输入要修改密码的用户名: " user
        if [ -z "${user}" ]; then
            echo "用户名不能为空！"
        else
            grep -w "${user}" /etc/ppp/chap-secrets >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                break
            else
                echo "用户名 (${user}) 不存在，请重新输入。"
            fi
        fi
    done
    local pass=$(rand)
    echo "请输入 ${user} 的新密码:"
    read -p "(默认密码: ${pass}): " tmppass
    [ ! -z "${tmppass}" ] && pass="${tmppass}"
    sed -i "/^\<${user}\>/d" /etc/ppp/chap-secrets
    echo "${user}    l2tpd    ${pass}       *" >> /etc/ppp/chap-secrets
    echo "用户 ${user} 的密码已修改。"
}

#========================================================================#
#                            启动横幅                                      #
#========================================================================#

show_banner(){
    clear
    echo
    echo -e "  \033[1;35m ██╗   ██╗██╗   ██╗███╗   ██╗██╗   ██╗██╗\033[0m"
    echo -e "  \033[1;35m ╚██╗ ██╔╝██║   ██║████╗  ██║╚██╗ ██╔╝██║\033[0m"
    echo -e "  \033[1;35m  ╚████╔╝ ██║   ██║██╔██╗ ██║ ╚████╔╝ ██║\033[0m"
    echo -e "  \033[1;35m   ╚██╔╝  ██║   ██║██║╚██╗██║  ╚██╔╝  ██║\033[0m"
    echo -e "  \033[1;35m    ██║   ╚██████╔╝██║ ╚████║   ██║   ██║\033[0m"
    echo -e "  \033[1;35m    ╚═╝    ╚═════╝ ╚═╝  ╚═══╝   ╚═╝   ╚═╝\033[0m"
    echo
    echo -e "  \033[36mYUNYI 工作室 · hfyunyi@foxmail.com\033[0m"
    echo -e "  \033[1;37mL2TP / IPSec VPN  一键安装脚本  \033[33mv${SCRIPT_VER}\033[0m"
    echo
    echo -e "  \033[37mRHEL 8+ 使用 strongSwan | RHEL 7 / Debian / Ubuntu 使用 libreswan\033[0m"
    echo -e "  \033[90m支持: CentOS 7 | Rocky 8-9 | Alma 8-9 | Debian 10-12 | Ubuntu 20.04-24.04\033[0m"
    echo
}

#========================================================================#
#                            程序入口                                      #
#========================================================================#

action=$1
if [ -z "${action}" ] && [ "$(basename $0)" != "l2tp" ]; then
    action=install
fi

case "${action}" in
    install)
        # 显示横幅
        show_banner
        # 安装前检查
        rootness
        tunavailable
        disable_selinux
        # 检测是否已安装
        if is_installed; then
            handle_existing_install
        fi
        version_check
        get_os_info
        preinstall_l2tp
        install_l2tp
        finally
        ;;
    -l|--list)
        list_users
        ;;
    -a|--add)
        add_user
        ;;
    -d|--del)
        del_user
        ;;
    -m|--mod)
        mod_user
        ;;
    -h|--help)
        echo "用法: $(basename $0) [选项]"
        echo
        echo "  (无参数)           安装 L2TP VPN"
        echo "  -l, --list         列出所有用户"
        echo "  -a, --add           添加新用户"
        echo "  -d, --del           删除用户"
        echo "  -m, --mod           修改用户密码"
        echo "  -h, --help          显示本帮助信息"
        ;;
    *)
        echo "用法: $(basename $0) [-l|--list|-a|--add|-d|--del|-m|--mod|-h|--help]"
        exit 1
        ;;
esac
