# 云服务器上从零搭建 RouterOS (CHR) 并配置 L2TP VPN 服务器

本文详细记录如何在 **Linux 云服务器**（如腾讯云、阿里云、华为云等）上通过官方脚本安装 **RouterOS CHR**（Cloud Hosted Router），并完成 L2TP/IPsec VPN 服务器的完整配置，包括必要的安全加固。教程将基于您实际运行脚本时输出的信息，让您能够直接复现整个过程。

---

## 📌 环境说明

| 项目       | 示例值                         | 说明                                                |
| ---------- | ------------------------------ | --------------------------------------------------- |
| 云服务器   | CentOS 7/8 或任意 Linux 发行版 | 需要 root 权限                                      |
| 虚拟磁盘   | /dev/vda                       | 系统盘，安装时将被覆盖                              |
| CHR 版本   | 7.22.1                         | 稳定版                                              |
| 公网 IP    | 172.19.0.12/20                 | 云平台分配的私网 IP，实际公网 IP 需通过云控制台查看 |
| 网关       | 172.19.0.1                     |                                                     |
| DNS        | 183.60.83.19                   | 云平台内网 DNS                                      |
| 管理员密码 | TAu2g13b7TN6u5fH               | 安装脚本随机生成，首次登录后建议修改                |

> ⚠️ 安装 CHR 会 **覆盖系统盘全部数据**，请在操作前确认该磁盘无重要数据。

---

## 🔧 第一部分：安装 RouterOS CHR

### 1.1 执行安装脚本

脚本官网地址：https://mikrotik.ltd/

使用 root 用户登录云服务器，执行以下命令：

```bash
VERSION=7.22.1 bash <(curl https://mikrotik.ltd/chr.sh)
```

脚本执行过程如下（根据您实际输出整理）：

```bash
[root@VM-0-12-centos ~]# VERSION=7.22.1 bash <(curl https://mikrotik.ltd/chr.sh)
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100 11677    0 11677    0     0  19380      0 --:--:-- --:--:-- --:--:-- 19364
Select your language:
1. English
2. 简体中文
Please choose an option [1] 2
CPU架构: x86_64
引导模式: BIOS
已选择版本: 7.22.1
下载文件:  chr-7.22.1-legacy-bios.img.zip
######################################################################## 100.0%
输入IP地址: [172.19.0.12/20]
输入网关地址: [172.19.0.1]
输入DNS服务器: [183.60.83.19]
管理员密码: [TAu2g13b7TN6u5fH]
autorun.scr 文件已创建。
输入存储设备名称: [vda]
警告：/dev/vda 上的数据将会丢失！
您是否确定继续? [y/n] y
32+0 records in
32+0 records out
134217728 bytes (134 MB) copied, 0.538082 s, 249 MB/s

```

等待写入完成，脚本会自动重启服务器，启动后即进入 RouterOS 系统。

### 1.2 安装后首次登录

服务器重启后，您将无法再通过 SSH 连接（因为 RouterOS 不再运行 Linux），需要通过以下方式管理：

1. **使用 WinBox**：从 Windows 电脑下载 WinBox 工具，输入云服务器的 **公网 IP**，用户名 `admin`，密码为安装时生成的 `TAu2g13b7TN6u5fH`。

---

## 🔒 第二部分：云环境安全加固

RouterOS 默认开启了多个管理服务（SSH、Telnet、FTP、WWW、Winbox、API 等），在公网环境中必须限制或关闭这些服务，防止被恶意扫描和攻击。

### 2.0 打开winbox 终端

![image-20260328232245439](img\image-20260328232245439.png)

### 2.1 查看当前启用的服务

```bash
/ip service print
```

输出示例：
```
Flags: X - disabled, I - invalid 
 #   NAME     PORT   ADDRESS         CERTIFICATE
 0   telnet   23     0.0.0.0/0       
 1   ftp      21     0.0.0.0/0       
 2   www      80     0.0.0.0/0       
 3   ssh      22     0.0.0.0/0       
 4   www-ssl  443    0.0.0.0/0       
 5   api      8728   0.0.0.0/0       
 6   winbox   8291   0.0.0.0/0       
 7   api-ssl  8729   0.0.0.0/0
```

![image-20260328232317037](img\image-20260328232317037.png)

### 2.2 禁用不必要的服务

推荐只保留 **Winbox**（方便 GUI 管理）或 **SSH**（方便命令行管理），其他全部禁用。

```bash
# 禁用除 Winbox 和 SSH 外的所有服务
/ip service disable [find name~"telnet|ftp|www|www-ssl|api|api-ssl"]
```

如果希望完全禁用 SSH（只通过 Winbox 管理）：

```bash
/ip service disable ssh
```

### 2.3 配置云平台安全组（非常重要）

登录云服务器控制台（如腾讯云、阿里云），找到该服务器的 **安全组** 配置，**删除或限制** 所有不必要的入站规则。

**推荐的安全组规则**：

| 协议 | 端口      | 来源           | 说明                 |
| ---- | --------- | -------------- | -------------------- |
| TCP  | 22        | 您的本地 IP/32 | SSH 管理（如果保留） |
| TCP  | 8291      | 您的本地 IP/32 | Winbox 管理          |
| UDP  | 500, 4500 | 0.0.0.0/0      | IPsec（VPN 客户端）  |
| UDP  | 1701      | 0.0.0.0/0      | L2TP（VPN 客户端）   |
| ICMP | -         | 0.0.0.0/0      | 可选，用于 Ping 测试 |

> 🔒 **严格原则**：只开放 VPN 必需端口（UDP 500, 4500, 1701）和管理端口（限制来源 IP）。其他端口一律禁止。

---

## 🚀 第三部分：配置 L2TP VPN 服务器

### 3.1 创建 VPN 地址池

VPN 客户端连接后，将从地址池中获取虚拟 IP。

```bash
/ip pool add name=l2tp-pool ranges=192.168.100.2-192.168.100.254
```

![image-20260328232449293](img\image-20260328232449293.png)

### 3.2 配置 PPP Profile

PPP Profile 定义了 VPN 连接的参数，包括 DNS、加密要求等。

```bash
/ppp profile add name=l2tp-profile local-address=192.168.100.1 remote-address=l2tp-pool dns-server=8.8.8.8,8.8.4.4 
```

- `local-address`：VPN 服务器的虚拟网关地址
- `remote-address`：分配给客户端的地址池
- `dns-server`：可改为内网 DNS 或 114.114.114.114
- 
- ![image-20260328232551741](img\image-20260328232551741.png)

### 3.3 启用 L2TP 服务器并绑定 IPsec

```bash
/interface l2tp-server server set enabled=yes use-ipsec=yes ipsec-secret=YourSecretKey default-profile=l2tp-profile
```

- `ipsec-secret`：预共享密钥，客户端连接时需要输入（请替换为强密码）
- `use-ipsec=yes`：强制 IPsec 加密

> 📌 RouterOS v7 会自动创建相应的 IPsec 策略，无需手动配置。
>
> ![image-20260328232712820](img\image-20260328232712820.png)

### 3.4 添加 VPN 用户

```bash
/ppp secret add name=user1 password=pass123 service=l2tp profile=l2tp-profile
```

可根据需要添加多个用户，每个用户独立认证。

![image-20260328232744759](imgs\image-20260328232744759.png)

### 3.5 配置 NAT 伪装

添加 NAT 规则：

```bash
/ip firewall nat add chain=srcnat src-address=192.168.100.0/24  action=masquerade
```
