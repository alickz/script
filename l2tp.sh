#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
#=======================================================================#
#   System Supported:  CentOS 6+ / Debian 7+ / Ubuntu 12+               #
#   Description: L2TP VPN Auto Installer                                #
#   Author:                                                             #
#   Intro:                                                              #
#=======================================================================#
cur_dir=`pwd`

libreswan_filename="libreswan-3.27"
download_root_url="https://dl.lamp.sh/files"

rootness(){
    if [[ $EUID -ne 0 ]]; then
       echo "错误：此脚本必须以 root 身份运行！" 1>&2
       exit 1
    fi
}

tunavailable(){
    if [[ ! -e /dev/net/tun ]]; then
        echo "错误：TUN/TAP 不可用！" 1>&2
        exit 1
    fi
}

disable_selinux(){
if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
    setenforce 0
fi
}

get_opsy(){
    [ -f /etc/redhat-release ] && awk '{print ($1,$3~/^[0-9]/?$3:$4)}' /etc/redhat-release && return
    [ -f /etc/os-release ] && awk -F'[= "]' '/PRETTY_NAME/{print $3,$4,$5}' /etc/os-release && return
    [ -f /etc/lsb-release ] && awk -F'[="]+' '/DESCRIPTION/{print $2}' /etc/lsb-release && return
}

get_os_info(){
    IP=$( ip addr | egrep -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | egrep -v "^192\.168|^172\.1[6-9]\.|^172\.2[0-9]\.|^172\.3[0-2]\.|^10\.|^127\.|^255\.|^0\." | head -n 1 )
    [ -z ${IP} ] && IP=$( wget -qO- -t1 -T2 ipv4.icanhazip.com )

    local cname=$( awk -F: '/model name/ {name=$2} END {print name}' /proc/cpuinfo | sed 's/^[ \t]*//;s/[ \t]*$//' )
    local cores=$( awk -F: '/model name/ {core++} END {print core}' /proc/cpuinfo )
    local freq=$( awk -F: '/cpu MHz/ {freq=$2} END {print freq}' /proc/cpuinfo | sed 's/^[ \t]*//;s/[ \t]*$//' )
    local tram=$( free -m | awk '/Mem/ {print $2}' )
    local swap=$( free -m | awk '/Swap/ {print $2}' )
    local up=$( awk '{a=$1/86400;b=($1%86400)/3600;c=($1%3600)/60;d=$1%60} {printf("%ddays, %d:%d:%d\n",a,b,c,d)}' /proc/uptime )
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
    echo "总内存              : ${tram} MB"
    echo "总交换空间          : ${swap} MB"
    echo "系统运行时间        : ${up}"
    echo "平均负载            : ${load}"
    echo "操作系统            : ${opsy}"
    echo "系统架构            : ${arch} (${lbit} 位)"
    echo "内核版本            : ${kern}"
    echo "主机名              : ${host}"
    echo "IPv4 地址           : ${IP}"
    echo 
    echo "########################################"
}

check_sys(){
    local checkType=$1
    local value=$2

    local release=''
    local systemPackage=''

    if [[ -f /etc/redhat-release ]]; then
        release="centos"
        systemPackage="yum"
    elif cat /etc/issue | grep -Eqi "debian"; then
        release="debian"
        systemPackage="apt"
    elif cat /etc/issue | grep -Eqi "ubuntu"; then
        release="ubuntu"
        systemPackage="apt"
    elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
        release="centos"
        systemPackage="yum"
    elif cat /proc/version | grep -Eqi "debian"; then
        release="debian"
        systemPackage="apt"
    elif cat /proc/version | grep -Eqi "ubuntu"; then
        release="ubuntu"
        systemPackage="apt"
    elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
        release="centos"
        systemPackage="yum"
    fi

    if [[ ${checkType} == "sysRelease" ]]; then
        if [ "$value" == "$release" ];then
            return 0
        else
            return 1
        fi
    elif [[ ${checkType} == "packageManager" ]]; then
        if [ "$value" == "$systemPackage" ];then
            return 0
        else
            return 1
        fi
    fi
}

rand(){
    index=0
    str=""
    for i in {a..z}; do arr[index]=${i}; index=`expr ${index} + 1`; done
    for i in {A..Z}; do arr[index]=${i}; index=`expr ${index} + 1`; done
    for i in {0..9}; do arr[index]=${i}; index=`expr ${index} + 1`; done
    for i in {1..10}; do str="$str${arr[$RANDOM%$index]}"; done
    echo ${str}
}

is_64bit(){
    if [ `getconf WORD_BIT` = '32' ] && [ `getconf LONG_BIT` = '64' ] ; then
        return 0
    else
        return 1
    fi
}

download_file(){
    if [ -s ${1} ]; then
        echo "$1 [已找到]"
    else
        echo "$1 未找到！！！现在开始下载..."
        if ! wget -c -t3 -T60 ${download_root_url}/${1}; then
            echo "下载 $1 失败，请手动下载到 ${cur_dir} 目录后重试。"
            exit 1
        fi
    fi
}

versionget(){
    if [[ -s /etc/redhat-release ]];then
        grep -oE  "[0-9.]+" /etc/redhat-release
    else
        grep -oE  "[0-9.]+" /etc/issue
    fi
}

centosversion(){
    if check_sys sysRelease centos;then
        local code=${1}
        local version="`versionget`"
        local main_ver=${version%%.*}
        if [ "${main_ver}" == "${code}" ];then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

debianversion(){
    if check_sys sysRelease debian;then
        local version=$( get_opsy )
        local code=${1}
        local main_ver=$( echo ${version} | sed 's/[^0-9]//g')
        if [ "${main_ver}" == "${code}" ];then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

version_check(){
    if check_sys packageManager yum; then
        if centosversion 5; then
            echo "错误：不支持 CentOS 5，请重新安装操作系统后再试。"
            exit 1
        fi
    fi
}

get_char(){
    SAVEDSTTY=`stty -g`
    stty -echo
    stty cbreak
    dd if=/dev/tty bs=1 count=1 2> /dev/null
    stty -raw
    stty echo
    stty $SAVEDSTTY
}

# 检查是否已安装 L2TP VPN
check_installed(){
    if [ -f /etc/ipsec.conf ] && [ -f /etc/xl2tpd/xl2tpd.conf ] && [ -f /etc/ppp/chap-secrets ]; then
        return 0
    else
        return 1
    fi
}

# 卸载 L2TP VPN
uninstall_l2tp(){
    echo "开始卸载 L2TP VPN..."

    # 停止服务
    if check_sys packageManager yum; then
        if centosversion 6; then
            /etc/init.d/ipsec stop >/dev/null 2>&1
            /etc/init.d/xl2tpd stop >/dev/null 2>&1
            chkconfig --del ipsec >/dev/null 2>&1
            chkconfig --del xl2tpd >/dev/null 2>&1
        else
            systemctl stop ipsec xl2tpd >/dev/null 2>&1
            systemctl disable ipsec xl2tpd >/dev/null 2>&1
        fi
    else
        service ipsec stop >/dev/null 2>&1
        service xl2tpd stop >/dev/null 2>&1
        update-rc.d -f ipsec remove >/dev/null 2>&1
        update-rc.d -f xl2tpd remove >/dev/null 2>&1
    fi

    # 删除软件包（保留 ppp，因为可能被其他服务使用）
    if check_sys packageManager yum; then
        yum -y remove libreswan xl2tpd >/dev/null 2>&1
    else
        apt-get -y purge libreswan xl2tpd >/dev/null 2>&1
        apt-get -y autoremove >/dev/null 2>&1
    fi

    # 删除配置文件
    rm -f /etc/ipsec.conf /etc/ipsec.secrets /etc/ipsec.d/cert9.db
    rm -rf /etc/xl2tpd/
    rm -f /etc/ppp/options.xl2tpd
    # 删除 chap-secrets 中的 L2TP 条目，但保留其他可能存在的条目
    if [ -f /etc/ppp/chap-secrets ]; then
        sed -i '/l2tpd/d' /etc/ppp/chap-secrets
    fi

    # 清理 ip-up 和 ip-down 中的反向代理标记块
    for file in /etc/ppp/ip-up /etc/ppp/ip-down; do
        if [ -f "$file" ]; then
            sed -i '/### L2TP VPN Reverse Proxy Begin/,/### L2TP VPN Reverse Proxy End/d' "$file"
        fi
    done

    # 删除 iptables 规则（尽力删除，不保证完全恢复）
    iptables-save | grep -v "L2TP" | iptables-restore 2>/dev/null

    # 删除 sysctl 中 L2TP 添加的配置
    if [ -f /etc/sysctl.conf ]; then
        sed -i '/# Added by L2TP VPN/d' /etc/sysctl.conf
        sed -i '/net.ipv4.ip_forward=1/d' /etc/sysctl.conf
        sed -i '/net.ipv4.conf.*.accept_source_route=0/d' /etc/sysctl.conf
        sed -i '/net.ipv4.conf.*.accept_redirects=0/d' /etc/sysctl.conf
        sed -i '/net.ipv4.conf.*.send_redirects=0/d' /etc/sysctl.conf
        sed -i '/net.ipv4.conf.*.rp_filter=0/d' /etc/sysctl.conf
        sysctl -p >/dev/null 2>&1
    fi

    # 删除命令行工具
    rm -f /usr/bin/l2tp

    echo "卸载完成！"
    exit 0
}

# 修复模式：重新生成配置并重启服务
repair_l2tp(){
    echo "进入修复模式..."
    # 获取用户输入（可复用原有配置或重新输入）
    echo
    echo "请输入 IP 地址段："
    read -p "(默认网段: 100.0.1):" iprange
    [ -z ${iprange} ] && iprange="100.0.1"

    echo "请输入预共享密钥 (PSK)："
    read -p "(默认 PSK: helium):" mypsk
    [ -z ${mypsk} ] && mypsk="helium"

    echo "请输入用户名："
    read -p "(默认用户名: helium):" username
    [ -z ${username} ] && username="helium"

    password=`rand`
    echo "请输入 ${username} 的密码："
    read -p "(默认密码: ${password}):" tmppassword
    [ ! -z ${tmppassword} ] && password=${tmppassword}

    # 重新生成配置
    config_install
    # 重新配置防火墙
    configure_firewall
    # 重新设置反向代理
    reverse_proxy
    # 重启服务
    restart_services
    echo "修复完成。"
    exit 0
}

preinstall_l2tp(){

    echo
    if [ -d "/proc/vz" ]; then
        echo -e "\033[41;37m 警告： \033[0m 您的 VPS 基于 OpenVZ，内核可能不支持 IPSec。"
        echo "是否继续安装？(y/n)"
        read -p "(默认: n)" agree
        [ -z ${agree} ] && agree="n"
        if [ "${agree}" == "n" ]; then
            echo
            echo "L2TP 安装已取消。"
            echo
            exit 0
        fi
    fi
    echo
    echo "请输入 IP 地址段："
    read -p "(默认网段: 100.0.1):" iprange
    [ -z ${iprange} ] && iprange="100.0.1"

    echo "请输入预共享密钥 (PSK)："
    read -p "(默认 PSK: helium):" mypsk
    [ -z ${mypsk} ] && mypsk="helium"

    echo "请输入用户名："
    read -p "(默认用户名: helium):" username
    [ -z ${username} ] && username="helium"

    password=`rand`
    echo "请输入 ${username} 的密码："
    read -p "(默认密码: ${password}):" tmppassword
    [ ! -z ${tmppassword} ] && password=${tmppassword}

    echo
    echo "服务器 IP:${IP}"
    echo "服务器本地 IP:${iprange}.1"
    echo "客户端远程 IP 范围:${iprange}.2-${iprange}.254"
    echo "预共享密钥 (PSK):${mypsk}"
    echo
    echo "按任意键开始安装... 或按 Ctrl + C 取消。"
    char=`get_char`

}

install_l2tp(){

    mknod /dev/random c 1 9

    if check_sys packageManager apt; then
        apt-get -y update

        if debianversion 7; then
            if is_64bit; then
                local libnspr4_filename1="libnspr4_4.10.7-1_amd64.deb"
                local libnspr4_filename2="libnspr4-0d_4.10.7-1_amd64.deb"
                local libnspr4_filename3="libnspr4-dev_4.10.7-1_amd64.deb"
                local libnspr4_filename4="libnspr4-dbg_4.10.7-1_amd64.deb"
                local libnss3_filename1="libnss3_3.17.2-1.1_amd64.deb"
                local libnss3_filename2="libnss3-1d_3.17.2-1.1_amd64.deb"
                local libnss3_filename3="libnss3-tools_3.17.2-1.1_amd64.deb"
                local libnss3_filename4="libnss3-dev_3.17.2-1.1_amd64.deb"
                local libnss3_filename5="libnss3-dbg_3.17.2-1.1_amd64.deb"
            else
                local libnspr4_filename1="libnspr4_4.10.7-1_i386.deb"
                local libnspr4_filename2="libnspr4-0d_4.10.7-1_i386.deb"
                local libnspr4_filename3="libnspr4-dev_4.10.7-1_i386.deb"
                local libnspr4_filename4="libnspr4-dbg_4.10.7-1_i386.deb"
                local libnss3_filename1="libnss3_3.17.2-1.1_i386.deb"
                local libnss3_filename2="libnss3-1d_3.17.2-1.1_i386.deb"
                local libnss3_filename3="libnss3-tools_3.17.2-1.1_i386.deb"
                local libnss3_filename4="libnss3-dev_3.17.2-1.1_i386.deb"
                local libnss3_filename5="libnss3-dbg_3.17.2-1.1_i386.deb"
            fi
            rm -rf ${cur_dir}/l2tp
            mkdir -p ${cur_dir}/l2tp
            cd ${cur_dir}/l2tp
            download_file "${libnspr4_filename1}"
            download_file "${libnspr4_filename2}"
            download_file "${libnspr4_filename3}"
            download_file "${libnspr4_filename4}"
            download_file "${libnss3_filename1}"
            download_file "${libnss3_filename2}"
            download_file "${libnss3_filename3}"
            download_file "${libnss3_filename4}"
            download_file "${libnss3_filename5}"
            dpkg -i ${libnspr4_filename1} ${libnspr4_filename2} ${libnspr4_filename3} ${libnspr4_filename4}
            dpkg -i ${libnss3_filename1} ${libnss3_filename2} ${libnss3_filename3} ${libnss3_filename4} ${libnss3_filename5}

            apt-get -y install wget gcc ppp flex bison make pkg-config libpam0g-dev libcap-ng-dev iptables \
                               libcap-ng-utils libunbound-dev libevent-dev libcurl4-nss-dev libsystemd-daemon-dev
        else
            apt-get -y install wget gcc ppp flex bison make python libnss3-dev libnss3-tools libselinux-dev iptables \
                               libnspr4-dev pkg-config libpam0g-dev libcap-ng-dev libcap-ng-utils libunbound-dev \
                               libevent-dev libcurl4-nss-dev libsystemd-dev
        fi
        apt-get -y --no-install-recommends install xmlto
        apt-get -y install xl2tpd

        compile_install
    elif check_sys packageManager yum; then
        echo "正在添加 EPEL 仓库..."
        yum -y install epel-release yum-utils
        [ ! -f /etc/yum.repos.d/epel.repo ] && echo "安装 EPEL 仓库失败，请检查。" && exit 1
        yum-config-manager --enable epel
        echo "添加 EPEL 仓库完成..."

        if centosversion 7; then
            yum -y install ppp libreswan xl2tpd firewalld
            yum_install
        elif centosversion 6; then
            yum -y remove libevent-devel
            yum -y install libevent2-devel
            yum -y install nss-devel nspr-devel pkgconfig pam-devel \
                           libcap-ng-devel libselinux-devel lsof \
                           curl-devel flex bison gcc ppp make iptables gmp-devel \
                           fipscheck-devel unbound-devel xmlto libpcap-devel xl2tpd

            compile_install
        fi
    fi

}

config_install(){

    cat > /etc/ipsec.conf<<EOF
version 2.0

config setup
    protostack=netkey
    nhelpers=0
    uniqueids=no
    interfaces=%defaultroute
    virtual_private=%v4:10.0.0.0/8,%v4:192.168.0.0/16,%v4:172.16.0.0/12,%v4:!${iprange}.0/24

conn l2tp-psk
    rightsubnet=vhost:%priv
    also=l2tp-psk-nonat

conn l2tp-psk-nonat
    authby=secret
    pfs=no
    auto=add
    keyingtries=3
    rekey=no
    ikelifetime=8h
    keylife=1h
    type=transport
    left=%defaultroute
    leftid=${IP}
    leftprotoport=17/1701
    right=%any
    rightprotoport=17/%any
    dpddelay=40
    dpdtimeout=130
    dpdaction=clear
    sha2-truncbug=yes
EOF

    cat > /etc/ipsec.secrets<<EOF
%any %any : PSK "${mypsk}"
EOF

    cat > /etc/xl2tpd/xl2tpd.conf<<EOF
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

    cat > /etc/ppp/options.xl2tpd<<EOF
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

    rm -f /etc/ppp/chap-secrets
    cat > /etc/ppp/chap-secrets<<EOF
# Secrets for authentication using CHAP
# client    server    secret    IP addresses
${username}    l2tpd    ${password}       *
EOF

}

compile_install(){

    rm -rf ${cur_dir}/l2tp
    mkdir -p ${cur_dir}/l2tp
    cd ${cur_dir}/l2tp
    download_file "${libreswan_filename}.tar.gz"
    tar -zxf ${libreswan_filename}.tar.gz

    cd ${cur_dir}/l2tp/${libreswan_filename}
        cat > Makefile.inc.local <<'EOF'
WERROR_CFLAGS =
USE_DNSSEC = false
USE_DH31 = false
USE_GLIBC_KERN_FLIP_HEADERS = true
EOF
    make programs && make install

    /usr/local/sbin/ipsec --version >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "${libreswan_filename} 安装失败。"
        exit 1
    fi

    config_install

    cp -pf /etc/sysctl.conf /etc/sysctl.conf.bak

    sed -i 's/net.ipv4.ip_forward = 0/net.ipv4.ip_forward = 1/g' /etc/sysctl.conf

    for each in `ls /proc/sys/net/ipv4/conf/`; do
        echo "net.ipv4.conf.${each}.accept_source_route=0" >> /etc/sysctl.conf
        echo "net.ipv4.conf.${each}.accept_redirects=0" >> /etc/sysctl.conf
        echo "net.ipv4.conf.${each}.send_redirects=0" >> /etc/sysctl.conf
        echo "net.ipv4.conf.${each}.rp_filter=0" >> /etc/sysctl.conf
    done
    sysctl -p

    if centosversion 6; then
        [ -f /etc/sysconfig/iptables ] && cp -pf /etc/sysconfig/iptables /etc/sysconfig/iptables.old.`date +%Y%m%d`

        if [ "`iptables -L -n | grep -c '\-\-'`" == "0" ]; then
            cat > /etc/sysconfig/iptables <<EOF
# Added by L2TP VPN script
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
-A INPUT -p icmp -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -p tcp --dport 22 -j ACCEPT
-A INPUT -p udp -m multiport --dports 500,4500,1701 -j ACCEPT
-A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
-A FORWARD -s ${iprange}.0/24  -j ACCEPT
COMMIT
*nat
:PREROUTING ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s ${iprange}.0/24 -j SNAT --to-source ${IP}
COMMIT
EOF
        else
            iptables -I INPUT -p udp -m multiport --dports 500,4500,1701 -j ACCEPT
            iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
            iptables -I FORWARD -s ${iprange}.0/24  -j ACCEPT
            iptables -t nat -A POSTROUTING -s ${iprange}.0/24 -j SNAT --to-source ${IP}
            /etc/init.d/iptables save
        fi

        if [ ! -f /etc/ipsec.d/cert9.db ]; then
           echo > /var/tmp/libreswan-nss-pwd
           certutil -N -f /var/tmp/libreswan-nss-pwd -d /etc/ipsec.d
           rm -f /var/tmp/libreswan-nss-pwd
        fi

        chkconfig --add iptables
        chkconfig iptables on
        chkconfig --add ipsec
        chkconfig ipsec on
        chkconfig --add xl2tpd
        chkconfig xl2tpd on

        /etc/init.d/iptables restart
        /etc/init.d/ipsec start
        /etc/init.d/xl2tpd start

    else
        [ -f /etc/iptables.rules ] && cp -pf /etc/iptables.rules /etc/iptables.rules.old.`date +%Y%m%d`

        if [ "`iptables -L -n | grep -c '\-\-'`" == "0" ]; then
            cat > /etc/iptables.rules <<EOF
# Added by L2TP VPN script
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
-A INPUT -p icmp -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -p tcp --dport 22 -j ACCEPT
-A INPUT -p udp -m multiport --dports 500,4500,1701 -j ACCEPT
-A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
-A FORWARD -s ${iprange}.0/24  -j ACCEPT
COMMIT
*nat
:PREROUTING ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s ${iprange}.0/24 -j SNAT --to-source ${IP}
COMMIT
EOF
        else
            iptables -I INPUT -p udp -m multiport --dports 500,4500,1701 -j ACCEPT
            iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
            iptables -I FORWARD -s ${iprange}.0/24  -j ACCEPT
            iptables -t nat -A POSTROUTING -s ${iprange}.0/24 -j SNAT --to-source ${IP}
            /sbin/iptables-save > /etc/iptables.rules
        fi

        cat > /etc/network/if-up.d/iptables <<EOF
#!/bin/sh
/sbin/iptables-restore < /etc/iptables.rules
EOF
        chmod +x /etc/network/if-up.d/iptables

        if [ ! -f /etc/ipsec.d/cert9.db ]; then
           echo > /var/tmp/libreswan-nss-pwd
           certutil -N -f /var/tmp/libreswan-nss-pwd -d /etc/ipsec.d
           rm -f /var/tmp/libreswan-nss-pwd
        fi

        update-rc.d -f xl2tpd defaults

        cp -f /etc/rc.local /etc/rc.local.old.`date +%Y%m%d`
        sed --follow-symlinks -i -e '/^exit 0/d' /etc/rc.local
        cat >> /etc/rc.local <<EOF

# Added by L2TP VPN script
echo 1 > /proc/sys/net/ipv4/ip_forward
/usr/sbin/service ipsec start
exit 0
EOF
        chmod +x /etc/rc.local
        echo 1 > /proc/sys/net/ipv4/ip_forward

        /sbin/iptables-restore < /etc/iptables.rules
        /usr/sbin/service ipsec start
        /usr/sbin/service xl2tpd restart

    fi

}

yum_install(){

    config_install

    cp -pf /etc/sysctl.conf /etc/sysctl.conf.bak

    echo "# Added by L2TP VPN" >> /etc/sysctl.conf
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_syncookies=1" >> /etc/sysctl.conf
    echo "net.ipv4.icmp_echo_ignore_broadcasts=1" >> /etc/sysctl.conf
    echo "net.ipv4.icmp_ignore_bogus_error_responses=1" >> /etc/sysctl.conf

    for each in `ls /proc/sys/net/ipv4/conf/`; do
        echo "net.ipv4.conf.${each}.accept_source_route=0" >> /etc/sysctl.conf
        echo "net.ipv4.conf.${each}.accept_redirects=0" >> /etc/sysctl.conf
        echo "net.ipv4.conf.${each}.send_redirects=0" >> /etc/sysctl.conf
        echo "net.ipv4.conf.${each}.rp_filter=0" >> /etc/sysctl.conf
    done
    sysctl -p

    cat > /etc/firewalld/services/xl2tpd.xml<<EOF
<?xml version="1.0" encoding="utf-8"?>
<service>
  <short>xl2tpd</short>
  <description>L2TP IPSec</description>
  <port protocol="udp" port="4500"/>
  <port protocol="udp" port="1701"/>
</service>
EOF
    chmod 640 /etc/firewalld/services/xl2tpd.xml

    systemctl enable ipsec
    systemctl enable xl2tpd
    systemctl enable firewalld

    systemctl status firewalld > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        firewall-cmd --reload
        echo "检查 firewalld 状态..."
        firewall-cmd --list-all
        echo "添加 firewalld 规则..."
        firewall-cmd --permanent --add-service=ipsec
        firewall-cmd --permanent --add-service=xl2tpd
        firewall-cmd --permanent --add-masquerade
        firewall-cmd --reload
    else
        echo "Firewalld 似乎未运行，正在尝试启动..."
        systemctl start firewalld
        if [ $? -eq 0 ]; then
            echo "Firewalld 启动成功..."
            firewall-cmd --reload
            echo "检查 firewalld 状态..."
            firewall-cmd --list-all
            echo "添加 firewalld 规则..."
            firewall-cmd --permanent --add-service=ipsec
            firewall-cmd --permanent --add-service=xl2tpd
            firewall-cmd --permanent --add-masquerade
            firewall-cmd --reload
        else
            echo "启动 firewalld 失败，如需请手动开放 UDP 端口 500、4500、1701。"
        fi
    fi

    systemctl restart ipsec
    systemctl restart xl2tpd
    echo "检查 ipsec 状态..."
    systemctl -a | grep ipsec
    echo "检查 xl2tpd 状态..."
    systemctl -a | grep xl2tpd
    echo "检查 firewalld 状态..."
    firewall-cmd --list-all

}

configure_firewall(){
    # 已集成在安装过程中，单独抽出来供修复使用
    if check_sys packageManager yum; then
        if centosversion 6; then
            # CentOS 6 已在 compile_install 中配置 iptables，此处无需重复
            /etc/init.d/iptables restart >/dev/null 2>&1
        else
            # CentOS 7+ 使用 firewalld
            systemctl restart firewalld >/dev/null 2>&1
        fi
    else
        # Debian/Ubuntu
        /sbin/iptables-restore < /etc/iptables.rules >/dev/null 2>&1
    fi
}

restart_services(){
    if check_sys packageManager yum; then
        if centosversion 6; then
            /etc/init.d/ipsec restart >/dev/null 2>&1
            /etc/init.d/xl2tpd restart >/dev/null 2>&1
        else
            systemctl restart ipsec xl2tpd >/dev/null 2>&1
        fi
    else
        service ipsec restart >/dev/null 2>&1
        service xl2tpd restart >/dev/null 2>&1
    fi
}

# 反向代理配置：使用标记块避免重复
reverse_proxy(){
    # 删除已有标记块
    for file in /etc/ppp/ip-up /etc/ppp/ip-down; do
        if [ -f "$file" ]; then
            sed -i '/### L2TP VPN Reverse Proxy Begin/,/### L2TP VPN Reverse Proxy End/d' "$file"
        fi
    done

    cat >> "/etc/ppp/ip-up" <<EOF
### L2TP VPN Reverse Proxy Begin
    eth0_addr=\`ifconfig eth0|grep -E 'inet'|awk '{print \$2}'|head -n 1\`
    iptables -t nat -A PREROUTING -d \$eth0_addr -p tcp -m tcp --dport 44158 -j DNAT --to-destination \$5:44158
    iptables -t nat -A PREROUTING -d \$eth0_addr -p tcp -m tcp --dport 80 -j DNAT --to-destination \$5:80
    echo "---------------Login---------------------------------------" >> /var/log/l2tp.log
    echo "time: \`date -d today +%F_%T\`" >> /var/log/pptpd.log
    echo "clientIP: \$6" >> /var/log/l2tp.log
    echo "username: \$PEERNAME" >> /var/log/l2tp.log
    echo "device: \$1" >> /var/log/l2tp.log
    echo "vpnIP: \$4" >> /var/log/l2tp.log
    echo "assignIP: \$5" >> /var/log/l2tp.log
    echo "-----------------------------------------------------------" >> /var/log/l2tp.log
    exit 0
### L2TP VPN Reverse Proxy End
EOF

    cat >> "/etc/ppp/ip-down" <<EOF
### L2TP VPN Reverse Proxy Begin
    eth0_addr=\`ifconfig eth0|grep -E 'inet'|awk '{print \$2}'|head -n 1\`
    iptables -t nat -D PREROUTING -d \$eth0_addr -p tcp -m tcp --dport 44158 -j DNAT --to-destination \$5:44158
    iptables -t nat -D PREROUTING -d \$eth0_addr -p tcp -m tcp --dport 80 -j DNAT --to-destination \$5:80
    echo "---------------Logout--------------------------------------" >> /var/log/l2tp.log
    echo "time: \`date -d today +%F_%T\`" >> /var/log/l2tp.log
    echo "clientIP: \$6" >> /var/log/l2tp.log
    echo "username: \$PEERNAME" >> /var/log/l2tp.log
    echo "device: \$1" >> /var/log/l2tp.log
    echo "vpnIP: \$4" >> /var/log/l2tp.log
    echo "assignIP: \$5" >> /var/log/l2tp.log
    echo "-----------------------------------------------------------" >> /var/log/l2tp.log
    exit 0
### L2TP VPN Reverse Proxy End
EOF
}

finally(){

    cd ${cur_dir}
    rm -fr ${cur_dir}/l2tp
    # create l2tp command
    cp -f ${cur_dir}/`basename $0` /usr/bin/l2tp

    reverse_proxy

    echo "请稍等..."
    sleep 5
    ipsec verify
    echo
    echo "###############################################################"
    echo "# L2TP VPN 自动安装脚本                                       #"
    echo "# 支持系统：CentOS 6+ / Debian 7+ / Ubuntu 12+                #"
    echo "# 功能：反向代理 TCP 端口 44158 和 80                         #"
    echo "# 作者：                                                      #"
    echo "###############################################################"
    echo "如果上方没有 [FAILED] 输出，您可以使用以下默认用户名/密码连接 L2TP VPN："
    echo
    echo "服务器 IP: ${IP}"
    echo "预共享密钥 (PSK) : ${mypsk}"
    echo "用户名 : ${username}"
    echo "密码 : ${password}"
    echo
    echo "如需修改用户设置，请使用以下命令："
    echo "l2tp -a (添加用户)"
    echo "l2tp -d (删除用户)"
    echo "l2tp -l (列出所有用户)"
    echo "l2tp -m (修改用户密码)"
    echo
    echo "祝您使用愉快！"
    echo
}

# ==================== 新增 TCP 加速功能 ====================
run_tcp_accelerator(){
    local tcp_url="https://raw.githubusercontent.com/alickz/script/refs/heads/main/tcp.sh"

    # 检查 curl 命令是否存在
    if ! command -v curl &>/dev/null; then
        echo "curl 未安装，尝试自动安装..."
        if check_sys packageManager yum; then
            yum install -y curl >/dev/null 2>&1
        else
            apt-get update -y >/dev/null 2>&1
            apt-get install -y curl >/dev/null 2>&1
        fi
        if ! command -v curl &>/dev/null; then
            echo "curl 安装失败，请手动安装后重试。"
            echo "按任意键返回主菜单..."
            read -n 1
            return
        fi
    fi

    echo "=========================================="
    echo "           TCP 加速脚本 (BBRplus 等)"
    echo "=========================================="
    echo "说明："
    echo "1. 首次运行请选择「安装 BBRplus 内核」，安装后系统会提示重启。"
    echo "2. 重启后再次运行此选项，选择「启用 BBRplus」即可完成加速。"
    echo "3. 如果您已经安装过内核，直接选择启用即可。"
    echo
    echo "正在执行 TCP 加速脚本..."
    echo "------------------------------------------"
    bash <(curl -s  "${tcp_url}")
    echo "------------------------------------------"
    echo "TCP 加速脚本执行完毕。"
    echo
    echo "重要提示："
    echo "如果刚刚安装了新内核，请务必手动重启系统："
    echo "  reboot"
    echo "重启后再次运行本脚本（l2tp），选择「TCP 加速」并启用 BBRplus。"
    echo
    echo "按任意键返回主菜单..."
    read -n 1
}
# =======================================================

l2tp(){
    clear
    echo
    echo "###############################################################"
    echo "# L2TP VPN 自动安装脚本                                       #"
    echo "# 支持系统：CentOS 6+ / Debian 7+ / Ubuntu 12+                #"
    echo "###############################################################"
    echo
    rootness
    tunavailable
    disable_selinux
    version_check
    get_os_info

    # 检测是否已安装
    if check_installed; then
        echo "检测到系统已安装 L2TP VPN。"
        echo "请选择操作："
        echo "1) 修复（重新配置并重启服务）"
        echo "2) 卸载（彻底清除所有组件）"
        echo "3) TCP 加速（BBRplus 等）"
        echo "4) 退出"
        read -p "请输入选项 [1-4]: " choice
        case $choice in
            1)
                repair_l2tp
                ;;
            2)
                uninstall_l2tp
                ;;
            3)
                run_tcp_accelerator
                # 执行完后重新显示菜单（通过再次调用 l2tp 实现，但为避免递归，直接退出）
                # 实际上 run_tcp_accelerator 返回后用户按任意键，这里直接退出脚本，让用户重新运行。
                exit 0
                ;;
            *)
                echo "已取消。"
                exit 0
                ;;
        esac
    else
        preinstall_l2tp
        install_l2tp
        finally
    fi
}

list_users(){
    if [ ! -f /etc/ppp/chap-secrets ];then
        echo "错误：未找到 /etc/ppp/chap-secrets 文件。"
        exit 1
    fi
    local line="+-------------------------------------------+\n"
    local string=%20s
    printf "${line}|${string} |${string} |\n${line}" 用户名 密码
    grep -v "^#" /etc/ppp/chap-secrets | awk '{printf "|'${string}' |'${string}' |\n", $1,$3}'
    printf ${line}
}

add_user(){
    while :
    do
        read -p "请输入用户名：" user
        if [ -z ${user} ]; then
            echo "用户名不能为空"
        else
            grep -w "${user}" /etc/ppp/chap-secrets > /dev/null 2>&1
            if [ $? -eq 0 ];then
                echo "用户名 (${user}) 已存在，请重新输入。"
            else
                break
            fi
        fi
    done
    pass=`rand`
    echo "请输入 ${user} 的密码："
    read -p "(默认密码: ${pass}):" tmppass
    [ ! -z ${tmppass} ] && pass=${tmppass}
    echo "${user}    l2tpd    ${pass}       *" >> /etc/ppp/chap-secrets
    echo "用户名 (${user}) 添加完成。"
}

del_user(){
    while :
    do
        read -p "请输入要删除的用户名：" user
        if [ -z ${user} ]; then
            echo "用户名不能为空"
        else
            grep -w "${user}" /etc/ppp/chap-secrets >/dev/null 2>&1
            if [ $? -eq 0 ];then
                break
            else
                echo "用户名 (${user}) 不存在，请重新输入。"
            fi
        fi
    done
    sed -i "/^\<${user}\>/d" /etc/ppp/chap-secrets
    echo "用户名 (${user}) 删除完成。"
}

mod_user(){
    while :
    do
        read -p "请输入要修改密码的用户名：" user
        if [ -z ${user} ]; then
            echo "用户名不能为空"
        else
            grep -w "${user}" /etc/ppp/chap-secrets >/dev/null 2>&1
            if [ $? -eq 0 ];then
                break
            else
                echo "用户名 (${user}) 不存在，请重新输入。"
            fi
        fi
    done
    pass=`rand`
    echo "请输入 ${user} 的新密码："
    read -p "(默认密码: ${pass}):" tmppass
    [ ! -z ${tmppass} ] && pass=${tmppass}
    sed -i "/^\<${user}\>/d" /etc/ppp/chap-secrets
    echo "${user}    l2tpd    ${pass}       *" >> /etc/ppp/chap-secrets
    echo "用户名 ${user} 的密码已修改。"
}

# Main process
action=$1
if [ -z ${action} ] && [ "`basename $0`" != "l2tp" ]; then
    action=install
fi

case ${action} in
    install)
        l2tp 2>&1 | tee ${cur_dir}/l2tp.log
        ;;
    uninstall)
        uninstall_l2tp
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
        echo "用法：`basename $0` -l,--list   列出所有用户"
        echo "       `basename $0` -a,--add    添加用户"
        echo "       `basename $0` -d,--del    删除用户"
        echo "       `basename $0` -m,--mod    修改用户密码"
        echo "       `basename $0` -h,--help   显示此帮助信息"
        echo "       `basename $0` uninstall   卸载 L2TP VPN"
        ;;
    *)
        echo "用法：`basename $0` [-l,--list|-a,--add|-d,--del|-m,--mod|-h,--help|uninstall]" && exit
        ;;
esac
