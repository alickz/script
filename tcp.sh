#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

#=================================================
#	System Required: CentOS 6/7,Debian 8/9,Ubuntu 16+
#	Description: BBR+BBR魔改版+BBRplus+Lotserver
#	Version: 1.3.2
#	Author: 千影,cx9208
#	Blog: https://www.94ish.me/
#=================================================

sh_ver="1.3.2"
github="raw.githubusercontent.com/chiakge/Linux-NetSpeed/master"

Green_font_prefix="\033[32m" && Red_font_prefix="\033[31m" && Green_background_prefix="\033[42;37m" && Red_background_prefix="\033[41;37m" && Font_color_suffix="\033[0m"
Info="${Green_font_prefix}[信息]${Font_color_suffix}"
Error="${Red_font_prefix}[错误]${Font_color_suffix}"
Tip="${Green_font_prefix}[注意]${Font_color_suffix}"

# 检查wget是否已安装
if ! command -v wget &>/dev/null; then
    echo "wget未安装，开始自动安装..."
    yum install -y wget >/dev/null 2>&1
    if command -v wget &>/dev/null; then
        echo "wget安装成功！"
    else
        echo "wget安装失败，请检查网络或yum仓库配置！" >&2
        exit 1
    fi
fi

#开始菜单
start_menu(){
clear
check_status
if [[ ${kernel_status} == "noinstall" ]]; then
    echo -e " 当前状态: ${Green_font_prefix}未安装${Font_color_suffix} 加速内核 ${Red_font_prefix}请先安装内核${Font_color_suffix}"
    check_sys_bbrplus
else
    echo -e " 当前状态: ${Green_font_prefix}已安装${Font_color_suffix} ${_font_prefix}${kernel_status}${Font_color_suffix} 加速内核 , ${Green_font_prefix}${run_status}${Font_color_suffix}"
    if [[ ${kernel_status} != "BBRplus" ]]; then
        check_sys_bbrplus
    else
        if [[ ${run_status} != "BBRplus启动成功" ]]; then
            startbbrplus
        fi
    fi
fi
}

check_sys_bbrplus(){
    check_version
    if [[ "${release}" == "centos" ]]; then
        if [[ ${version} -ge "6" ]]; then
            installbbrplus
        else
            echo -e "${Error} BBRplus内核不支持当前系统 ${release} ${version} ${bit} !" && exit 1
        fi
    elif [[ "${release}" == "debian" ]]; then
        if [[ ${version} -ge "8" ]]; then
            installbbrplus
        else
            echo -e "${Error} BBRplus内核不支持当前系统 ${release} ${version} ${bit} !" && exit 1
        fi
    elif [[ "${release}" == "ubuntu" ]]; then
        if [[ ${version} -ge "14" ]]; then
            installbbrplus
        else
            echo -e "${Error} BBRplus内核不支持当前系统 ${release} ${version} ${bit} !" && exit 1
        fi
    else
        echo -e "${Error} BBRplus内核不支持当前系统 ${release} ${version} ${bit} !" && exit 1
    fi
}

#安装BBRplus内核
installbbrplus(){
    kernel_version="4.14.129-bbrplus"
    if [[ "${release}" == "centos" ]]; then
        echo -e "${Info} 开始下载 BBRplus 内核..."
        wget -N --no-check-certificate https://${github}/bbrplus/${release}/${version}/kernel-${kernel_version}.rpm
        if [ $? -ne 0 ]; then
            echo -e "${Error} 内核下载失败，请检查网络连接！"
            exit 1
        fi
        echo -e "${Info} 开始安装 BBRplus 内核..."
        yum install -y kernel-${kernel_version}.rpm
        rm -f kernel-${kernel_version}.rpm
        kernel_version="4.14.129_bbrplus" #fix a bug
    elif [[ "${release}" == "debian" || "${release}" == "ubuntu" ]]; then
        mkdir bbrplus && cd bbrplus
        wget -N --no-check-certificate http://${github}/bbrplus/debian-ubuntu/${bit}/linux-headers-${kernel_version}.deb
        wget -N --no-check-certificate http://${github}/bbrplus/debian-ubuntu/${bit}/linux-image-${kernel_version}.deb
        dpkg -i linux-headers-${kernel_version}.deb
        dpkg -i linux-image-${kernel_version}.deb
        cd .. && rm -rf bbrplus
    fi
    
    detele_kernel
    BBR_grub
    echo -e "${Tip} 重启VPS后，请重新运行脚本开启${Red_font_prefix}BBRplus${Font_color_suffix}"
    
    # 添加安全的重启确认
    # echo -e "${Info} 系统将在 10 秒后重启..."
    # echo -e "${Tip} 按 Ctrl+C 取消重启"
    # sleep 10
    # shutdown -r now
}

#启用BBRplus
startbbrplus(){
    remove_all
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbrplus" >> /etc/sysctl.conf
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    sysctl -p
    echo -e "${Info}BBRplus启动成功！"
}

#卸载全部加速
remove_all(){
    rm -rf bbrmod
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    sed -i '/fs.file-max/d' /etc/sysctl.conf
    sed -i '/net.core.rmem_max/d' /etc/sysctl.conf
    sed -i '/net.core.wmem_max/d' /etc/sysctl.conf
    sed -i '/net.core.rmem_default/d' /etc/sysctl.conf
    sed -i '/net.core.wmem_default/d' /etc/sysctl.conf
    sed -i '/net.core.netdev_max_backlog/d' /etc/sysctl.conf
    sed -i '/net.core.somaxconn/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_syncookies/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_tw_reuse/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_tw_recycle/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_fin_timeout/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_keepalive_time/d' /etc/sysctl.conf
    sed -i '/net.ipv4.ip_local_port_range/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_max_syn_backlog/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_max_tw_buckets/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_rmem/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_wmem/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_mtu_probing/d' /etc/sysctl.conf
    sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
    sed -i '/fs.inotify.max_user_instances/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_syncookies/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_fin_timeout/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_tw_reuse/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_max_syn_backlog/d' /etc/sysctl.conf
    sed -i '/net.ipv4.ip_local_port_range/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_max_tw_buckets/d' /etc/sysctl.conf
    sed -i '/net.ipv4.route.gc_timeout/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_synack_retries/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_syn_retries/d' /etc/sysctl.conf
    sed -i '/net.core.somaxconn/d' /etc/sysctl.conf
    sed -i '/net.core.netdev_max_backlog/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_timestamps/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_max_orphans/d' /etc/sysctl.conf
    if [[ -e /appex/bin/lotServer.sh ]]; then
        bash <(wget --no-check-certificate -qO- https://github.com/MoeClub/lotServer/raw/master/Install.sh) uninstall
    fi
    clear
    echo -e "${Info}:清除加速完成。"
    sleep 1s
}

#############内核管理组件#############
#删除多余内核
detele_kernel(){
    if [[ "${release}" == "centos" ]]; then
        # 更安全的内核包检测方式
        rpm_total=$(rpm -qa | grep -E "^kernel-[0-9]" | grep -v "${kernel_version}" | grep -v "noarch" | wc -l)
        if [ "${rpm_total}" -gt "0" ]; then
            echo -e "检测到 ${rpm_total} 个其余内核，开始卸载..."
            # 使用数组来存储要删除的内核包
            kernels_to_remove=($(rpm -qa | grep -E "^kernel-[0-9]" | grep -v "${kernel_version}" | grep -v "noarch"))
            
            for kernel_pkg in "${kernels_to_remove[@]}"; do
                if [ -n "${kernel_pkg}" ]; then
                    echo -e "开始卸载 ${kernel_pkg} 内核..."
                    rpm --nodeps -e "${kernel_pkg}" 2>/dev/null
                    if [ $? -eq 0 ]; then
                        echo -e "卸载 ${kernel_pkg} 内核卸载完成，继续..."
                    else
                        echo -e "卸载 ${kernel_pkg} 失败，跳过..."
                    fi
                fi
            done
            echo -e "内核卸载完毕，继续..."
        else
            echo -e "没有检测到其他内核，跳过卸载步骤。"
        fi
    elif [[ "${release}" == "debian" || "${release}" == "ubuntu" ]]; then
        deb_total=$(dpkg -l | grep 'linux-image' | awk '{print $2}' | grep -v "${kernel_version}" | wc -l)
        if [ "${deb_total}" -gt "0" ]; then
            echo -e "检测到 ${deb_total} 个其余内核，开始卸载..."
            kernels_to_remove=($(dpkg -l | grep 'linux-image' | awk '{print $2}' | grep -v "${kernel_version}"))
            
            for kernel_pkg in "${kernels_to_remove[@]}"; do
                if [ -n "${kernel_pkg}" ]; then
                    echo -e "开始卸载 ${kernel_pkg} 内核..."
                    apt-get purge -y "${kernel_pkg}"
                    echo -e "卸载 ${kernel_pkg} 内核卸载完成，继续..."
                fi
            done
            echo -e "内核卸载完毕，继续..."
        else
            echo -e "没有检测到其他内核，跳过卸载步骤。"
        fi
    fi
}

#更新引导 - 修复GRUB配置检查
BBR_grub(){
    if [[ "${release}" == "centos" ]]; then
        if [[ ${version} = "6" ]]; then
            if [ ! -f "/boot/grub/grub.conf" ]; then
                echo -e "${Error} /boot/grub/grub.conf 找不到，请检查."
                exit 1
            fi
            sed -i 's/^default=.*/default=0/g' /boot/grub/grub.conf
        elif [[ ${version} = "7" ]]; then
            # 修复GRUB配置检查 - 检查多个可能的路径
            grub_cfg_path=""
            possible_paths=(
                "/boot/grub2/grub.cfg"
                "/boot/efi/EFI/centos/grub.cfg"
                "/boot/efi/EFI/redhat/grub.cfg"
                "/boot/grub/grub.cfg"
            )
            
            for path in "${possible_paths[@]}"; do
                if [ -f "$path" ]; then
                    grub_cfg_path="$path"
                    echo -e "${Info} 找到 GRUB 配置文件: $path"
                    break
                fi
            done
            
            if [ -z "$grub_cfg_path" ]; then
                echo -e "${Error} 未找到 GRUB 配置文件，尝试生成..."
                # 尝试生成 GRUB 配置
                if command -v grub2-mkconfig &>/dev/null; then
                    grub2-mkconfig -o /boot/grub2/grub.cfg
                    if [ -f "/boot/grub2/grub.cfg" ]; then
                        grub_cfg_path="/boot/grub2/grub.cfg"
                        echo -e "${Info} 成功生成 GRUB 配置文件"
                    else
                        echo -e "${Error} 生成 GRUB 配置失败，但继续设置默认启动项"
                    fi
                else
                    echo -e "${Error} 未找到 grub2-mkconfig 命令"
                fi
            fi
            
            # 设置默认启动项
            if command -v grub2-set-default &>/dev/null; then
                grub2-set-default 0
                echo -e "${Info} 已设置默认启动项为 0"
            else
                echo -e "${Error} 未找到 grub2-set-default 命令"
            fi
        fi
    elif [[ "${release}" == "debian" || "${release}" == "ubuntu" ]]; then
        /usr/sbin/update-grub
    fi
}

#############系统检测组件#############

#检查系统
check_sys(){
    if [[ -f /etc/redhat-release ]]; then
        release="centos"
    elif cat /etc/issue | grep -q -E -i "debian"; then
        release="debian"
    elif cat /etc/issue | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
        release="centos"
    elif cat /proc/version | grep -q -E -i "debian"; then
        release="debian"
    elif cat /proc/version | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
        release="centos"
    fi
}

#检查Linux版本
check_version(){
    if [[ -s /etc/redhat-release ]]; then
        version=$(grep -oE "[0-9.]+" /etc/redhat-release | cut -d . -f 1)
    else
        version=$(grep -oE "[0-9.]+" /etc/issue | cut -d . -f 1)
    fi
    bit=$(uname -m)
    if [[ ${bit} = "x86_64" ]]; then
        bit="x64"
    else
        bit="x32"
    fi
}

check_status(){
    kernel_version=$(uname -r | awk -F "-" '{print $1}')
    kernel_version_full=$(uname -r)
    if [[ ${kernel_version_full} = "4.14.129-bbrplus" ]]; then
        kernel_status="BBRplus"
    elif [[ ${kernel_version} = "3.10.0" || ${kernel_version} = "3.16.0" || ${kernel_version} = "3.2.0" || ${kernel_version} = "4.4.0" || ${kernel_version} = "3.13.0"  || ${kernel_version} = "2.6.32" || ${kernel_version} = "4.9.0" ]]; then
        kernel_status="Lotserver"
    elif [[ $(echo ${kernel_version} | awk -F'.' '{print $1}') == "4" ]] && [[ $(echo ${kernel_version} | awk -F'.' '{print $2}') -ge 9 ]] || [[ $(echo ${kernel_version} | awk -F'.' '{print $1}') == "5" ]]; then
        kernel_status="BBR"
    else 
        kernel_status="noinstall"
    fi

    if [[ ${kernel_status} == "Lotserver" ]]; then
        if [[ -e /appex/bin/lotServer.sh ]]; then
            run_status=$(bash /appex/bin/lotServer.sh status | grep "LotServer" | awk '{print $3}')
            if [[ ${run_status} = "running!" ]]; then
                run_status="启动成功"
            else 
                run_status="启动失败"
            fi
        else 
            run_status="未安装加速模块"
        fi
    elif [[ ${kernel_status} == "BBR" ]]; then
        run_status=$(grep "net.ipv4.tcp_congestion_control" /etc/sysctl.conf | awk -F "=" '{print $2}')
        if [[ ${run_status} == "bbr" ]]; then
            run_status=$(lsmod | grep "bbr" | awk '{print $1}')
            if [[ ${run_status} == "tcp_bbr" ]]; then
                run_status="BBR启动成功"
            else 
                run_status="BBR启动失败"
            fi
        elif [[ ${run_status} == "tsunami" ]]; then
            run_status=$(lsmod | grep "tsunami" | awk '{print $1}')
            if [[ ${run_status} == "tcp_tsunami" ]]; then
                run_status="BBR魔改版启动成功"
            else 
                run_status="BBR魔改版启动失败"
            fi
        elif [[ ${run_status} == "nanqinlang" ]]; then
            run_status=$(lsmod | grep "nanqinlang" | awk '{print $1}')
            if [[ ${run_status} == "tcp_nanqinlang" ]]; then
                run_status="暴力BBR魔改版启动成功"
            else 
                run_status="暴力BBR魔改版启动失败"
            fi
        else 
            run_status="未安装加速模块"
        fi
    elif [[ ${kernel_status} == "BBRplus" ]]; then
        run_status=$(grep "net.ipv4.tcp_congestion_control" /etc/sysctl.conf | awk -F "=" '{print $2}')
        if [[ ${run_status} == "bbrplus" ]]; then
            run_status=$(lsmod | grep "bbrplus" | awk '{print $1}')
            if [[ ${run_status} == "tcp_bbrplus" ]]; then
                run_status="BBRplus启动成功"
            else 
                run_status="BBRplus启动失败"
            fi
        else 
            run_status="未安装加速模块"
        fi
    fi
}

#############系统检测组件#############
if [ $1 ]; then
    if [[ $1 == "start" ]]; then
        startbbrplus
    fi
fi
check_sys
check_version
[[ ${release} != "debian" ]] && [[ ${release} != "ubuntu" ]] && [[ ${release} != "centos" ]] && echo -e "${Error} 本脚本不支持当前系统 ${release} !" && exit 1
start_menu