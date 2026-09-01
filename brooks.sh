#!/usr/bin/env bash
#=================================================
#   System Required: CentOS 7+/Debian 8+/Ubuntu 16+/Alpine/Arch
#   Description: Brook 端口转发一键管理脚本 (Systemd & DDNS 优化增强版)
#   Version: 2.0.0
#   Author: Toyo, yulewang, Enhanced by Assistant
#=================================================

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

sh_ver="2.0.0"
file="/usr/local/brook-pf"
brook_file="/usr/local/brook-pf/brook"
brook_conf="/usr/local/brook-pf/brook.conf"
brook_log="/usr/local/brook-pf/brook.log"
brook_runner="/usr/local/brook-pf/brook-run.sh"
systemd_service="/etc/systemd/system/brook-pf.service"

Green_font_prefix="\033[32m" && Red_font_prefix="\033[31m" && Yellow_font_prefix="\033[33m"
Green_background_prefix="\033[42;37m" && Red_background_prefix="\033[41;37m" && Font_color_suffix="\033[0m"
Info="${Green_font_prefix}[信息]${Font_color_suffix}"
Error="${Red_font_prefix}[错误]${Font_color_suffix}"
Tip="${Yellow_font_prefix}[注意]${Font_color_suffix}"

check_root(){
    if [[ $EUID -ne 0 ]]; then
        echo -e "${Error} 当前非 ROOT 账号(或没有 ROOT 权限)，无法继续操作，请使用 ${Green_background_prefix}sudo su${Font_color_suffix} 获取权限后重试！"
        exit 1
    fi
}

check_sys(){
    if [[ -f /etc/redhat-release ]]; then
        release="centos"
    elif grep -q -E -i "debian" /etc/issue 2>/dev/null || grep -q -E -i "debian" /proc/version 2>/dev/null; then
        release="debian"
    elif grep -q -E -i "ubuntu" /etc/issue 2>/dev/null || grep -q -E -i "ubuntu" /proc/version 2>/dev/null; then
        release="ubuntu"
    elif grep -q -E -i "alpine" /etc/issue 2>/dev/null || grep -q -E -i "alpine" /proc/version 2>/dev/null; then
        release="alpine"
    elif grep -q -E -i "arch" /etc/issue 2>/dev/null || grep -q -E -i "arch" /proc/version 2>/dev/null; then
        release="arch"
    else
        release="other"
    fi

    # 架构识别
    local arch
    arch=$(uname -m)
    case "${arch}" in
        x86_64|amd64)
            brook_arch="brook_linux_amd64"
            ;;
        i386|i686)
            brook_arch="brook_linux_386"
            ;;
        aarch64|arm64)
            brook_arch="brook_linux_arm64"
            ;;
        armv7l|armv7|armhf)
            brook_arch="brook_linux_arm7"
            ;;
        armv6l|armv6)
            brook_arch="brook_linux_arm6"
            ;;
        armv5*)
            brook_arch="brook_linux_arm5"
            ;;
        mips64le)
            brook_arch="brook_linux_mips64le"
            ;;
        mips64)
            brook_arch="brook_linux_mips64"
            ;;
        mipsle)
            brook_arch="brook_linux_mipsle"
            ;;
        mips)
            brook_arch="brook_linux_mips"
            ;;
        ppc64le)
            brook_arch="brook_linux_ppc64le"
            ;;
        *)
            echo -e "${Error} 未识别或不支持的 CPU 架构: ${arch} !"
            exit 1
            ;;
    esac
}

check_installed_status(){
    if [[ ! -e ${brook_file} ]]; then
        echo -e "${Error} Brook 未安装，请先选择 [1. 安装 Brook] !"
        exit 1
    fi
}

check_pid(){
    if command -v systemctl >/dev/null 2>&1 && [[ -f "${systemd_service}" ]]; then
        if systemctl is-active --quiet brook-pf; then
            PID="systemd-running"
        else
            PID=$(pgrep -f "${brook_file} relay" | head -1)
        fi
    else
        PID=$(pgrep -f "${brook_file} relay" | head -1)
    fi
}

# 安装所有运行依赖，包含 DNS 域名解析、curl、cron 等
Installation_dependency(){
    echo -e "${Info} 正在安装必要依赖环境 (curl, wget, dig/nslookup, cron, iptables 等)..."
    if [[ ${release} == "centos" ]]; then
        yum install -y epel-release 2>/dev/null
        yum install -y curl wget bind-utils cronie iptables iptables-services ca-certificates 2>/dev/null
        systemctl enable crond 2>/dev/null && systemctl start crond 2>/dev/null
    elif [[ ${release} == "debian" || ${release} == "ubuntu" ]]; then
        apt-get update -y
        apt-get install -y curl wget dnsutils cron iptables ca-certificates 2>/dev/null
        systemctl enable cron 2>/dev/null && systemctl start cron 2>/dev/null
    elif [[ ${release} == "alpine" ]]; then
        apk update
        apk add curl wget bind-tools busybox-initscripts iptables ca-certificates tzdata
    elif [[ ${release} == "arch" ]]; then
        pacman -Sy --noconfirm curl wget bind cronie iptables ca-certificates
        systemctl enable cronie 2>/dev/null && systemctl start cronie 2>/dev/null
    fi

    # 尝试修正时区
    if [[ -f /usr/share/zoneinfo/Asia/Shanghai ]]; then
        \cp -f /usr/share/zoneinfo/Asia/Shanghai /etc/localtime 2>/dev/null
    fi
}

# 获取 GitHub 最新版本号
get_latest_ver(){
    local tag
    tag=$(curl -fsSL --connect-timeout 5 --max-time 10 https://api.github.com/repos/txthinking/brook/releases/latest 2>/dev/null | grep '"tag_name":' | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
    if [[ -z "${tag}" ]]; then
        tag=$(curl -fsSL --connect-timeout 5 --max-time 10 https://fastly.jsdelivr.net/gh/txthinking/brook@master/version 2>/dev/null)
    fi
    if [[ -z "${tag}" ]]; then
        tag="v20260101.0"
    fi
    echo "${tag}"
}

Download_brook(){
    mkdir -p "${file}"
    cd "${file}" || exit 1

    local ver="$1"
    if [[ -z "${ver}" ]]; then
        echo -e "${Info} 正在获取 Brook 官方最新版本..."
        ver=$(get_latest_ver)
    fi

    echo -e "${Info} 开始下载 Brook [${ver}] (${brook_arch})..."
    local download_url="https://github.com/txthinking/brook/releases/download/${ver}/${brook_arch}"
    local download_url_mirror="https://ghproxy.net/https://github.com/txthinking/brook/releases/download/${ver}/${brook_arch}"

    if ! curl -fsSL --connect-timeout 10 -o brook "${download_url}"; then
        echo -e "${Tip} 官方直连下载失败，尝试使用加速镜像下载..."
        if ! curl -fsSL --connect-timeout 15 -o brook "${download_url_mirror}"; then
            echo -e "${Error} Brook 下载失败，请检查网络或 GitHub 连通性 !"
            exit 1
        fi
    fi

    chmod +x brook
    if [[ ! -x "${brook_file}" ]]; then
        echo -e "${Error} Brook 可执行文件异常 !"
        exit 1
    fi
    echo -e "${Info} Brook [${ver}] 下载并安装完成！"
}

# 生成多规则运行脚本与 Systemd 服务
Write_runner_and_service(){
    # 创建运行器脚本 brook-run.sh
    cat > "${brook_runner}" <<'EOF'
#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

file="/usr/local/brook-pf"
brook_file="/usr/local/brook-pf/brook"
brook_conf="/usr/local/brook-pf/brook.conf"
brook_log="/usr/local/brook-pf/brook.log"

ulimit -n 65535 2>/dev/null

trap 'kill $(jobs -p) 2>/dev/null; exit 0' SIGINT SIGTERM SIGQUIT

if [[ ! -f "${brook_conf}" ]]; then
    echo "[$(date)] brook.conf not found!" >> "${brook_log}"
    exit 1
fi

running_count=0
while read -r line || [[ -n "$line" ]]; do
    # 忽略空行和注释行
    line=$(echo "$line" | sed 's/^[ \t]*//;s/[ \t]*$//')
    [[ -z "$line" || "$line" =~ ^# ]] && continue

    user_port=$(echo "$line" | awk '{print $1}')
    user_ip=$(echo "$line" | awk '{print $2}')
    user_port_pf=$(echo "$line" | awk '{print $3}')
    user_enabled=$(echo "$line" | awk '{print $4}')

    if [[ "$user_enabled" == "1" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting relay :${user_port} -> ${user_ip}:${user_port_pf}" >> "${brook_log}"
        "${brook_file}" relay -l ":${user_port}" --to "${user_ip}:${user_port_pf}" >> "${brook_log}" 2>&1 &
        ((running_count++))
    fi
done < "${brook_conf}"

if [[ $running_count -eq 0 ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] No enabled relay rules found." >> "${brook_log}"
    sleep 5
    exit 0
fi

# 等待所有后台子进程
wait
EOF
    chmod +x "${brook_runner}"

    # 创建 Systemd 服务文件
    cat > "${systemd_service}" <<EOF
[Unit]
Description=Brook Port Forward Service
After=network.target network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=root
LimitNOFILE=65535
ExecStart=${brook_runner}
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload 2>/dev/null
    systemctl enable brook-pf >/dev/null 2>&1
}

Install_brook(){
    check_root
    check_sys
    echo -e "${Info} 检测到系统: ${release}, CPU架构: ${brook_arch}"
    Installation_dependency
    Download_brook
    touch "${brook_conf}"
    touch "${brook_log}"
    Write_runner_and_service
    echo -e "${Info} Brook 服务配置完成！"
    echo -e "${Info} 您可以通过菜单添加端口转发，或直接使用: ${Green_font_prefix}bash $0 <本地端口> <目标IP/域名> <目标端口>${Font_color_suffix} 快速添加！"
}

Start_brook(){
    check_installed_status
    Write_runner_and_service
    systemctl restart brook-pf
    sleep 1
    if systemctl is-active --quiet brook-pf; then
        echo -e "${Info} Brook 服务启动成功！"
    else
        echo -e "${Error} Brook 服务启动失败，请使用 ${Green_font_prefix}journalctl -u brook-pf -e${Font_color_suffix} 或查看 ${brook_log} 检查原因。"
    fi
}

Stop_brook(){
    check_installed_status
    systemctl stop brook-pf
    pkill -f "${brook_file} relay" 2>/dev/null
    echo -e "${Info} Brook 服务已停止。"
}

Restart_brook(){
    check_installed_status
    Write_runner_and_service
    systemctl restart brook-pf
    sleep 1
    if systemctl is-active --quiet brook-pf; then
        echo -e "${Info} Brook 服务重启成功！"
    else
        echo -e "${Error} Brook 服务重启失败，请查看日志���"
    fi
}

Update_brook(){
    check_installed_status
    check_sys
    local latest_ver
    latest_ver=$(get_latest_ver)
    echo -e "${Info} 最新版本: ${latest_ver}"
    Download_brook "${latest_ver}"
    Restart_brook
    echo -e "${Info} Brook 已成功更新至 ${latest_ver} 并重启服务！"
}

Uninstall_brook(){
    check_root
    echo -e "确定要彻底卸载 Brook 端口转发服务吗？[y/N]"
    read -e -p "(默认: n): " unyn
    [[ -z "${unyn}" ]] && unyn="n"
    if [[ ${unyn} == [Yy] ]]; then
        systemctl stop brook-pf 2>/dev/null
        systemctl disable brook-pf 2>/dev/null
        rm -f "${systemd_service}"
        systemctl daemon-reload 2>/dev/null
        pkill -f "${brook_file} relay" 2>/dev/null

        # 清理防火墙端口
        if [[ -f "${brook_conf}" ]]; then
            while read -r line || [[ -n "$line" ]]; do
                line=$(echo "$line" | sed 's/^[ \t]*//;s/[ \t]*$//')
                [[ -z "$line" || "$line" =~ ^# ]] && continue
                local p
                p=$(echo "$line" | awk '{print $1}')
                Del_iptables_port "$p"
            done < "${brook_conf}"
        fi

        # 清理 crontab
        crontab_monitor_brook_cron_stop >/dev/null 2>&1

        rm -rf "${file}"
        echo -e "${Info} Brook 已彻底卸载完成！"
    else
        echo -e "${Info} 卸载已取消。"
    fi
}

# 增强域名解析函数，支持 dig / nslookup / getent / python / ping 等多种回退策略
resolve_domain_to_ip(){
    local domain="$1"
    local ip=""

    # 1. 优先使用 dig
    if command -v dig >/dev/null 2>&1; then
        ip=$(dig +short +time=2 +tries=2 "${domain}" 2>/dev/null | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
    fi

    # 2. 回退使用 nslookup
    if [[ -z "$ip" ]] && command -v nslookup >/dev/null 2>&1; then
        ip=$(nslookup "${domain}" 2>/dev/null | awk '/^Address: / { print $2 }' | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
        if [[ -z "$ip" ]]; then
            ip=$(nslookup "${domain}" 2>/dev/null | awk -F': ' '/Address/ {print $2}' | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | tail -1)
        fi
    fi

    # 3. 回退使用 getent
    if [[ -z "$ip" ]] && command -v getent >/dev/null 2>&1; then
        ip=$(getent ahosts "${domain}" 2>/dev/null | awk '{print $1}' | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
    fi

    # 4. 回退使用 python
    if [[ -z "$ip" ]] && command -v python3 >/dev/null 2>&1; then
        ip=$(python3 -c "import socket; print(socket.gethostbyname('${domain}'))" 2>/dev/null | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}')
    fi

    # 5. 回退使用 ping
    if [[ -z "$ip" ]] && command -v ping >/dev/null 2>&1; then
        ip=$(ping -c 1 -W 2 "${domain}" 2>/dev/null | head -1 | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
    fi

    echo "$ip"
}

is_ip(){
    local input="$1"
    if [[ "$input" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

Add_iptables_port(){
    local port="$1"
    [[ -z "$port" ]] && return
    if command -v iptables >/dev/null 2>&1; then
        iptables -I INPUT -p tcp --dport "${port}" -j ACCEPT 2>/dev/null
        iptables -I INPUT -p udp --dport "${port}" -j ACCEPT 2>/dev/null
    fi
    if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
        ufw allow "${port}" >/dev/null 2>&1
    fi
    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
        firewall-cmd --zone=public --add-port="${port}/tcp" --permanent >/dev/null 2>&1
        firewall-cmd --zone=public --add-port="${port}/udp" --permanent >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    fi
}

Del_iptables_port(){
    local port="$1"
    [[ -z "$port" ]] && return
    if command -v iptables >/dev/null 2>&1; then
        iptables -D INPUT -p tcp --dport "${port}" -j ACCEPT 2>/dev/null
        iptables -D INPUT -p udp --dport "${port}" -j ACCEPT 2>/dev/null
    fi
    if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
        ufw delete allow "${port}" >/dev/null 2>&1
    fi
    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
        firewall-cmd --zone=public --remove-port="${port}/tcp" --permanent >/dev/null 2>&1
        firewall-cmd --zone=public --remove-port="${port}/udp" --permanent >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    fi
}

check_port_exists(){
    local check_port="$1"
    [[ ! -f "${brook_conf}" ]] && return 1
    if grep -q -E "^${check_port}[[:space:]]+" "${brook_conf}"; then
        return 0
    else
        return 1
    fi
}

# 核心：添加单条转发规则（支持快速命令行与交互式调用）
# 规则格式：本地端口 当前解析IP 目标端口 启用状态(0/1) [原始域名/标识]
Add_single_rule(){
    local lport="$1"
    local target="$2"
    local tport="$3"
    local enabled="${4:-1}"

    # 校验本地端口
    if ! [[ "$lport" =~ ^[0-9]+$ ]] || [[ "$lport" -lt 1 || "$lport" -gt 65535 ]]; then
        echo -e "${Error} 本地监听端口 [${lport}] 无效，必须在 1-65535 之间！"
        return 1
    fi

    # 校验目标端口
    if ! [[ "$tport" =~ ^[0-9]+$ ]] || [[ "$tport" -lt 1 || "$tport" -gt 65535 ]]; then
        echo -e "${Error} 目标转发端口 [${tport}] 无效，必须在 1-65535 之间！"
        return 1
    fi

    # 检查本地端口是否已配置
    if check_port_exists "${lport}"; then
        echo -e "${Error} 本地端口 [${lport}] 已在转发列表中存在，无法重复添加！如需修改请先删除或修改原有规则。"
        return 1
    fi

    local dest_ip=""
    local dest_domain=""

    if is_ip "${target}"; then
        dest_ip="${target}"
        dest_domain=""
    else
        dest_domain="${target}"
        echo -e "${Info} 检测到目标为域名 [${dest_domain}]，正在解析 IP..."
        dest_ip=$(resolve_domain_to_ip "${dest_domain}")
        if [[ -z "${dest_ip}" ]]; then
            echo -e "${Error} 无法解析域名 [${dest_domain}]，请检查域名拼写或 DNS 解析环境！"
            return 1
        fi
        echo -e "${Info} 域名解析成功: ${dest_domain} ===> ${dest_ip}"
    fi

    # 写入配置文件
    mkdir -p "${file}"
    touch "${brook_conf}"

    if [[ -n "${dest_domain}" ]]; then
        echo "${lport} ${dest_ip} ${tport} ${enabled} ${dest_domain}" >> "${brook_conf}"
    else
        echo "${lport} ${dest_ip} ${tport} ${enabled}" >> "${brook_conf}"
    fi

    Add_iptables_port "${lport}"
    Restart_brook

    echo -e "${Info} 端口转发添加成功！"
    echo -e "=================================================="
    echo -e " 本地监听端口 : ${Green_font_prefix}${lport}${Font_color_suffix}"
    if [[ -n "${dest_domain}" ]]; then
        echo -e " 目标域名     : ${Green_font_prefix}${dest_domain}${Font_color_suffix}"
        echo -e " 解析到 IP   : ${Green_font_prefix}${dest_ip}${Font_color_suffix}"
    else
        echo -e " 目标 IP     : ${Green_font_prefix}${dest_ip}${Font_color_suffix}"
    fi
    echo -e " 目标端口     : ${Green_font_prefix}${tport}${Font_color_suffix}"
    echo -e " 状态         : $( [[ "$enabled" == "1" ]] && echo -e "${Green_font_prefix}启用${Font_color_suffix}" || echo -e "${Red_font_prefix}禁用${Font_color_suffix}" )"
    echo -e "=================================================="

    # 如果添加了域名且尚未开启监控，提示开启
    if [[ -n "${dest_domain}" ]]; then
        if ! crontab -l 2>/dev/null | grep -q "$0 monitor\|brook-pf"; then
            echo -e "${Tip} 您添加了域名转发规则，建议开启 [10. 监控 Brook / DDNS] 功能以支持 IP 动态自动更新！"
        fi
    fi
    return 0
}

list_port(){
    if [[ ! -f "${brook_conf}" ]] || [[ ! -s "${brook_conf}" ]]; then
        echo -e "${Info} 目前 Brook 配置文件为空，暂无端口转发规则。"
        return
    fi

    echo -e "\n==================== 当前端口转发规则列表 ===================="
    local count=0
    while read -r line || [[ -n "$line" ]]; do
        line=$(echo "$line" | sed 's/^[ \t]*//;s/[ \t]*$//')
        [[ -z "$line" || "$line" =~ ^# ]] && continue

        local u_port u_ip u_port_pf u_en u_dom
        u_port=$(echo "$line" | awk '{print $1}')
        u_ip=$(echo "$line" | awk '{print $2}')
        u_port_pf=$(echo "$line" | awk '{print $3}')
        u_en=$(echo "$line" | awk '{print $4}')
        u_dom=$(echo "$line" | awk '{print $5}')

        local status_str
        if [[ "$u_en" == "1" ]]; then
            status_str="${Green_font_prefix}启用${Font_color_suffix}"
        else
            status_str="${Red_font_prefix}禁用${Font_color_suffix}"
        fi

        ((count++))
        if [[ -n "$u_dom" ]]; then
            echo -e "[${count}] 本地端口: ${Green_font_prefix}${u_port}${Font_color_suffix} -> 域名: ${Green_font_prefix}${u_dom}${Font_color_suffix} (当前IP: ${u_ip}) : ${Green_font_prefix}${u_port_pf}${Font_color_suffix} | 状态: ${status_str}"
        else
            echo -e "[${count}] 本地端口: ${Green_font_prefix}${u_port}${Font_color_suffix} -> 目标IP: ${Green_font_prefix}${u_ip}${Font_color_suffix} : ${Green_font_prefix}${u_port_pf}${Font_color_suffix} | 状态: ${status_str}"
        fi
    done < "${brook_conf}"

    local public_ip
    public_ip=$(curl -fsSL --connect-timeout 2 https://api.ipify.org 2>/dev/null || curl -fsSL --connect-timeout 2 https://ipinfo.io/ip 2>/dev/null || echo "VPS_IP")
    echo -e "------------------------------------------------------------"
    echo -e "规则总数: ${Green_font_prefix}${count}${Font_color_suffix} | 服务器公网 IP: ${Green_font_prefix}${public_ip}${Font_color_suffix}"
    echo -e "============================================================\n"
}

Del_pf(){
    list_port
    [[ ! -f "${brook_conf}" ]] || [[ ! -s "${brook_conf}" ]] && return

    while true; do
        read -e -p "请输入要删除的【本地监听端口】(按 Enter 取消): " del_port
        [[ -z "${del_port}" ]] && echo -e "${Info} 已取消删除。" && return

        if ! check_port_exists "${del_port}"; then
            echo -e "${Error} 本地端口 [${del_port}] 不在转发列表中，请重新输入！"
            continue
        fi

        # 从配置文件中删除
        sed -i "/^${del_port}[[:space:]]/d" "${brook_conf}"
        Del_iptables_port "${del_port}"
        Restart_brook
        echo -e "${Info} 本地端口 [${del_port}] 转发规则已成功删除！"
        break
    done
}

Modify_pf(){
    list_port
    [[ ! -f "${brook_conf}" ]] || [[ ! -s "${brook_conf}" ]] && return

    while true; do
        read -e -p "请输入要修改的【本地监听端口】(按 Enter 取消): " mod_port
        [[ -z "${mod_port}" ]] && echo -e "${Info} 已取消修改。" && return

        if ! check_port_exists "${mod_port}"; then
            echo -e "${Error} 本地端口 [${mod_port}] 不在转发列表中，请重新输入！"
            continue
        fi

        read -e -p "请输入新的【目标 IP 或 域名】: " new_target
        [[ -z "${new_target}" ]] && echo -e "${Error} 目标不能为空！" && return

        read -e -p "请输入新的【目标端口】: " new_tport
        [[ -z "${new_tport}" ]] && echo -e "${Error} 目标端口不能为空！" && return

        # 删除旧规则，添加新规则
        sed -i "/^${mod_port}[[:space:]]/d" "${brook_conf}"
        Add_single_rule "${mod_port}" "${new_target}" "${new_tport}" "1"
        break
    done
}

Toggle_Enabled_pf(){
    list_port
    [[ ! -f "${brook_conf}" ]] || [[ ! -s "${brook_conf}" ]] && return

    while true; do
        read -e -p "请输入要切换状态(启用/禁用)的【本地监听端口】(按 Enter 取消): " tog_port
        [[ -z "${tog_port}" ]] && echo -e "${Info} 已取消操作。" && return

        if ! check_port_exists "${tog_port}"; then
            echo -e "${Error} 本地端口 [${tog_port}] 不在转发列表中，请重新输入！"
            continue
        fi

        local line
        line=$(grep -E "^${tog_port}[[:space:]]" "${brook_conf}")
        local u_port u_ip u_port_pf u_en u_dom
        u_port=$(echo "$line" | awk '{print $1}')
        u_ip=$(echo "$line" | awk '{print $2}')
        u_port_pf=$(echo "$line" | awk '{print $3}')
        u_en=$(echo "$line" | awk '{print $4}')
        u_dom=$(echo "$line" | awk '{print $5}')

        local new_en="1"
        if [[ "$u_en" == "1" ]]; then
            new_en="0"
        fi

        sed -i "/^${tog_port}[[:space:]]/d" "${brook_conf}"
        if [[ -n "$u_dom" ]]; then
            echo "${u_port} ${u_ip} ${u_port_pf} ${new_en} ${u_dom}" >> "${brook_conf}"
        else
            echo "${u_port} ${u_ip} ${u_port_pf} ${new_en}" >> "${brook_conf}"
        fi

        Restart_brook
        if [[ "$new_en" == "1" ]]; then
            echo -e "${Info} 端口 [${tog_port}] 规则已${Green_font_prefix}启用${Font_color_suffix}！"
        else
            echo -e "${Info} 端口 [${tog_port}] 规则已${Red_font_prefix}禁用${Font_color_suffix}！"
        fi
        break
    done
}

# DDNS 域名解析变动检测与服务监控（由 Crontab 定时触发）
crontab_monitor_brook(){
    [[ ! -f "${brook_conf}" ]] && exit 0

    local ip_modified=0
    local temp_conf="${file}/brook.conf.tmp"
    rm -f "${temp_conf}"

    while read -r line || [[ -n "$line" ]]; do
        line=$(echo "$line" | sed 's/^[ \t]*//;s/[ \t]*$//')
        if [[ -z "$line" || "$line" =~ ^# ]]; then
            echo "$line" >> "${temp_conf}"
            continue
        fi

        local u_port u_ip u_port_pf u_en u_dom
        u_port=$(echo "$line" | awk '{print $1}')
        u_ip=$(echo "$line" | awk '{print $2}')
        u_port_pf=$(echo "$line" | awk '{print $3}')
        u_en=$(echo "$line" | awk '{print $4}')
        u_dom=$(echo "$line" | awk '{print $5}')

        if [[ -n "$u_dom" ]]; then
            local current_resolved_ip
            current_resolved_ip=$(resolve_domain_to_ip "${u_dom}")
            if [[ -n "${current_resolved_ip}" ]]; then
                if [[ "${u_ip}" != "${current_resolved_ip}" ]]; then
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] DDNS IP Change Detected: ${u_dom} (${u_ip} -> ${current_resolved_ip})" >> "${brook_log}"
                    u_ip="${current_resolved_ip}"
                    ip_modified=1
                fi
            else
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Warning: Could not resolve domain ${u_dom}" >> "${brook_log}"
            fi
            echo "${u_port} ${u_ip} ${u_port_pf} ${u_en} ${u_dom}" >> "${temp_conf}"
        else
            echo "$line" >> "${temp_conf}"
        fi
    done < "${brook_conf}"

    if [[ -f "${temp_conf}" ]]; then
        mv -f "${temp_conf}" "${brook_conf}"
    fi

    if [[ $ip_modified -eq 1 ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Reloading Brook due to DDNS IP changes..." >> "${brook_log}"
        systemctl restart brook-pf
    else
        # 守护进程自愈检查
        if ! systemctl is-active --quiet brook-pf; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Brook service inactive, restarting..." >> "${brook_log}"
            systemctl restart brook-pf
        fi
    fi
}

# 设置 Crontab 监控
Set_crontab_monitor_brook(){
    check_installed_status
    local script_abs_path
    script_abs_path=$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "/usr/local/brook-pf/brooks.sh")

    # 确保脚本被复制到了固定路径方便 cron 调用
    if [[ "$script_abs_path" != "/usr/local/brook-pf/brooks.sh" ]]; then
        cp -f "$script_abs_path" "/usr/local/brook-pf/brooks.sh" 2>/dev/null
        chmod +x "/usr/local/brook-pf/brooks.sh"
        script_abs_path="/usr/local/brook-pf/brooks.sh"
    fi

    local is_cron_active
    is_cron_active=$(crontab -l 2>/dev/null | grep -E "brooks\.sh monitor|brook-pf.*monitor")

    if [[ -z "${is_cron_active}" ]]; then
        echo -e "当前状态: ${Red_font_prefix}未开启${Font_color_suffix} 监控与 DDNS 自动更新"
        read -e -p "是否开启【Brook 运行状态监控与 DDNS 域名自动更新】？[Y/n]: " yn
        [[ -z "$yn" ]] && yn="y"
        if [[ $yn == [Yy] ]]; then
            crontab_monitor_brook_cron_start "${script_abs_path}"
        fi
    else
        echo -e "当前状态: ${Green_font_prefix}已开启${Font_color_suffix} 监控与 DDNS 自动更新"
        read -e -p "是否关闭【Brook 运行状态监控与 DDNS 域名自动更新】？[y/N]: " yn
        [[ -z "$yn" ]] && yn="n"
        if [[ $yn == [Yy] ]]; then
            crontab_monitor_brook_cron_stop
        fi
    fi
}

crontab_monitor_brook_cron_start(){
    local script_path="$1"
    crontab_monitor_brook_cron_stop >/dev/null 2>&1
    (crontab -l 2>/dev/null; echo "*/2 * * * * /bin/bash ${script_path} monitor >/dev/null 2>&1") | crontab -
    echo -e "${Info} 监控与 DDNS 自动更新任务已成功添加到 Crontab (每2分钟检查一次)！"
}

crontab_monitor_brook_cron_stop(){
    local tmp_cron="/tmp/crontab.tmp"
    crontab -l 2>/dev/null | grep -v "brooks.sh monitor" | grep -v "brook-pf.*monitor" > "${tmp_cron}"
    crontab "${tmp_cron}" 2>/dev/null
    rm -f "${tmp_cron}"
    echo -e "${Info} 监控与 DDNS 自动更新任务已停止并从 Crontab 移除！"
}

View_Log(){
    check_installed_status
    echo -e "${Tip} 正���查看 Brook 实时日志 (按 ${Red_font_prefix}Ctrl+C${Font_color_suffix} 退出日志查看)..."
    echo -e "------------------------------------------------------------"
    if [[ -f "${brook_log}" ]]; then
        tail -n 30 -f "${brook_log}"
    else
        journalctl -u brook-pf -f -n 30
    fi
}

# ================= 命令行快速模式处理 =================
# 支持: bash brooks.sh 10000 1.1.1.1 10000
# 或:   bash brooks.sh 10000 example.com 10000
handle_cli_args(){
    local lport="$1"
    local target="$2"
    local tport="$3"

    check_root
    check_sys

    # 如果尚未安装，自动先完成一键安装与依赖配置
    if [[ ! -x "${brook_file}" ]]; then
        echo -e "${Info} 检测到 Brook 尚未安装，正在为您自动初始化安装环境与 Brook..."
        Installation_dependency
        Download_brook
        touch "${brook_conf}"
        touch "${brook_log}"
        Write_runner_and_service
    fi

    echo -e "${Info} 执行命令行快速添加转发规则: [本地:${lport}] -> [${target}:${tport}]"
    Add_single_rule "${lport}" "${target}" "${tport}" "1"
    exit $?
}

# ================= 主入口逻辑 =================
check_sys

# 检查是否为 CLI 参数调用
if [[ $# -eq 3 ]] && [[ "$1" =~ ^[0-9]+$ ]] && [[ "$3" =~ ^[0-9]+$ ]]; then
    handle_cli_args "$1" "$2" "$3"
fi

action="$1"
if [[ "${action}" == "monitor" ]]; then
    crontab_monitor_brook
    exit 0
fi

# 交互式菜单
check_root
echo && echo -e "  Brook 端口转发 一键管理脚本 (Systemd & DDNS 增强版) ${Red_font_prefix}[v${sh_ver}]${Font_color_suffix}
  
 ${Green_font_prefix} 1.${Font_color_suffix} 安装 / 重新初始化 Brook
 ${Green_font_prefix} 2.${Font_color_suffix} 更新 Brook 内核
 ${Green_font_prefix} 3.${Font_color_suffix} 卸载 Brook
————————————
 ${Green_font_prefix} 4.${Font_color_suffix} 启动 Brook 服务
 ${Green_font_prefix} 5.${Font_color_suffix} 停止 Brook 服务
 ${Green_font_prefix} 6.${Font_color_suffix} 重启 Brook 服务
————————————
 ${Green_font_prefix} 7.${Font_color_suffix} 添加 端口转发 (支持 IP 与 域名)
 ${Green_font_prefix} 8.${Font_color_suffix} 删除 端口转发
 ${Green_font_prefix} 9.${Font_color_suffix} 修改 端口转发
 ${Green_font_prefix}10.${Font_color_suffix} 启用 / 禁用某条端口转发
 ${Green_font_prefix}11.${Font_color_suffix} 查看 端口转发列表
 ${Green_font_prefix}12.${Font_color_suffix} 监控与 DDNS 动态解析守护
 ${Green_font_prefix}13.${Font_color_suffix} 查看 运行日志
————————————"

if [[ -e ${brook_file} ]]; then
    check_pid
    if [[ ! -z "${PID}" ]]; then
        echo -e " 服务状态: ${Green_font_prefix}已安装${Font_color_suffix} | ��行状态: ${Green_font_prefix}运行中${Font_color_suffix}"
    else
        echo -e " 服务状态: ${Green_font_prefix}已安装${Font_color_suffix} | 运行状态: ${Red_font_prefix}未运行${Font_color_suffix}"
    fi
else
    echo -e " 服务状态: ${Red_font_prefix}未安装${Font_color_suffix}"
fi
echo

read -e -p " 请输入数字 [1-13]: " num
case "$num" in
    1)
        Install_brook
        ;;
    2)
        Update_brook
        ;;
    3)
        Uninstall_brook
        ;;
    4)
        Start_brook
        ;;
    5)
        Stop_brook
        ;;
    6)
        Restart_brook
        ;;
    7)
        check_installed_status
        list_port
        read -e -p "请输入【本地监听端口】[1-65535]: " in_lport
        read -e -p "请输入【目标 IP 或 域名】: " in_target
        read -e -p "请输入【目标端口】[1-65535]: " in_tport
        Add_single_rule "${in_lport}" "${in_target}" "${in_tport}" "1"
        ;;
    8)
        check_installed_status
        Del_pf
        ;;
    9)
        check_installed_status
        Modify_pf
        ;;
    10)
        check_installed_status
        Toggle_Enabled_pf
        ;;
    11)
        check_installed_status
        list_port
        ;;
    12)
        Set_crontab_monitor_brook
        ;;
    13)
        View_Log
        ;;
    *)
        echo -e "${Error} 请输入正确的数字 [1-13] !"
        ;;
esac
