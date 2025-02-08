#!/bin/bash

# 全局配置
TIMEOUT=5
CHECK_FILE="docker-ce/ubuntu/dists/focal/InRelease"
declare -A MIRROR_STATUS
declare -A REGISTRY_STATUS

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
PLAIN='\033[0m'
BOLD='\033[1m'

## Docker CE 镜像源列表
mirror_list_docker_ce=(
    "阿里云@mirrors.aliyun.com/docker-ce"
    "腾讯云@mirrors.tencent.com/docker-ce"
    "华为云@repo.huaweicloud.com/docker-ce"
    "火山引擎@mirrors.volces.com/docker"
    "南京大学@mirrors.nju.edu.cn/docker-ce"
    "上海交通大学@mirror.sjtu.edu.cn/docker-ce"
    "清华大学@mirrors.tuna.tsinghua.edu.cn/docker-ce"
    "中国科技大学@mirrors.ustc.edu.cn/docker-ce"
    "微软 Azure 中国@mirror.azure.cn/docker-ce"
    "网易@mirrors.163.com/docker-ce"
    "官方@download.docker.com"
)

## Docker Registry 仓库列表
mirror_list_registry=(
    "阿里云（杭州）@registry.cn-hangzhou.aliyuncs.com"
    "腾讯云@mirror.ccs.tencentyun.com"
    "华为云@swr.cn-east-3.myhuaweicloud.com"
    "Docker Proxy@dockerproxy.net"
    "DaoCloud@docker.m.daocloud.io"
    "阿里云（东京）@registry.ap-northeast-1.aliyuncs.com"
    "阿里云（法兰克福）@registry.eu-central-1.aliyuncs.com"
    "阿里云（硅谷）@registry.us-west-1.aliyuncs.com"
    "官方 Docker Hub@registry.hub.docker.com"
)

# 初始化终端检测
if [ -t 1 ]; then
    IS_TERMINAL=true
else
    IS_TERMINAL=false
fi

function show_animation() {
    if $IS_TERMINAL; then
        local chars=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
        while :; do
            for char in "${chars[@]}"; do
                echo -ne "\r$char 检查中..."
                sleep 0.1
            done
        done
    fi
}

function check_connectivity() {
    local url=$1
    local proxy_opts=""
    local start_time end_time

    if [ -n "$http_proxy" ]; then
        proxy_opts="--proxy $http_proxy"
    elif [ -n "$HTTP_PROXY" ]; then
        proxy_opts="--proxy $HTTP_PROXY"
    fi

    start_time=$(date +%s%3N)
    if curl -sI $proxy_opts --connect-timeout $TIMEOUT "${url}/${CHECK_FILE}" | grep -q "200 OK"; then
        end_time=$(date +%s%3N)
        TIME_USED=$(( (end_time - start_time) / 1000 ))
        return 0
    else
        TIME_USED=0
        return 1
    fi
}

function init_status_check() {
    echo -e "\n${BOLD}${BLUE}=== 网络可达性检查 (超时: ${TIMEOUT}s) ===${PLAIN}"

    # 检查Docker CE镜像源
    echo -e "\n${BOLD}${BLUE}>> 检查Docker CE镜像源${PLAIN}"
    local total=${#mirror_list_docker_ce[@]}
    for ((i=0; i<total; i++)); do
        entry="${mirror_list_docker_ce[$i]}"
        name="${entry%@*}"
        address="${entry#*@}"
        
        if $IS_TERMINAL; then
            show_animation &
            local anim_pid=$!
            disown $anim_pid
        fi

        if check_connectivity "https://$address"; then
            MIRROR_STATUS[$address]="${GREEN}✓${PLAIN}"
            status_msg="${GREEN}✓ 可达 (${TIME_USED}.$((TIME_USED % 1000 / 100 ))s)${PLAIN}"
        else
            MIRROR_STATUS[$address]="${RED}✗${PLAIN}"
            status_msg="${RED}✗ 不可达${PLAIN}"
        fi

        if $IS_TERMINAL; then
            kill $anim_pid 2>/dev/null
            echo -ne "\r\033[K"
        fi

        printf "  %2d/%d %-20s %-45s [%s]\n" $((i+1)) $total "$name" "$address" "$status_msg"
    done

    # 检查Registry镜像
    echo -e "\n${BOLD}${BLUE}>> 检查Registry镜像${PLAIN}"
    total=${#mirror_list_registry[@]}
    for ((i=0; i<total; i++)); do
        entry="${mirror_list_registry[$i]}"
        name="${entry%@*}"
        address="${entry#*@}"
        
        if $IS_TERMINAL; then
            show_animation &
            local anim_pid=$!
            disown $anim_pid
        fi

        start_time=$(date +%s%3N)
        if curl -sI --connect-timeout $TIMEOUT "https://$address/v2/" | grep -q "200 OK"; then
            end_time=$(date +%s%3N)
            time_used=$((end_time - start_time))
            REGISTRY_STATUS[$address]="${GREEN}✓${PLAIN}"
            status_msg="${GREEN}✓ 可达 (${time_used}ms)${PLAIN}"
        else
            REGISTRY_STATUS[$address]="${RED}✗${PLAIN}"
            status_msg="${RED}✗ 不可达${PLAIN}"
        fi

        if $IS_TERMINAL; then
            kill $anim_pid 2>/dev/null
            echo -ne "\r\033[K"
        fi

        printf "  %2d/%d %-20s %-45s [%s]\n" $((i+1)) $total "$name" "$address" "$status_msg"
    done
}

function permission_judgment() {
    if [ $UID -ne 0 ]; then
        echo -e "${RED}✗ 请使用 Root 用户运行本脚本${PLAIN}"
        exit 1
    fi
}

function collect_system_info() {
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        OS_NAME=$ID
        OS_VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        OS_NAME=$(awk '{print $1}' /etc/redhat-release | tr '[:upper:]' '[:lower:]')
        OS_VERSION=$(grep -oP '(?<=release )\d+' /etc/redhat-release)
    else
        echo -e "${RED}✗ 不支持的操作系统${PLAIN}"
        exit 1
    fi
}

function choose_mirrors() {
    echo -e "\n${BOLD}${BLUE}=== 镜像源选择 ===${PLAIN}"
    
    # Docker CE选择
    echo -e "\n${BOLD}可用的Docker CE镜像源：${PLAIN}"
    local i=1
    for entry in "${mirror_list_docker_ce[@]}"; do
        name="${entry%@*}"
        address="${entry#*@}"
        printf "  %2d. %-20s %-45s [%s]\n" $i "$name" "$address" "${MIRROR_STATUS[$address]}"
        ((i++))
    done

    while true; do
        read -p $'\n'"${BOLD}请选择Docker CE镜像源 (1-${#mirror_list_docker_ce[@]}): ${PLAIN}" choice
        if [[ $choice =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#mirror_list_docker_ce[@]})); then
            SELECTED_SOURCE="${mirror_list_docker_ce[$((choice-1))]#*@}"
            break
        else
            echo -e "${RED}无效输入，请重新选择${PLAIN}"
        fi
    done

    # Registry选择
    echo -e "\n${BOLD}可用的Registry镜像：${PLAIN}"
    i=1
    for entry in "${mirror_list_registry[@]}"; do
        name="${entry%@*}"
        address="${entry#*@}"
        printf "  %2d. %-20s %-45s [%s]\n" $i "$name" "$address" "${REGISTRY_STATUS[$address]}"
        ((i++))
    done

    while true; do
        read -p $'\n'"${BOLD}请选择Registry镜像 (1-${#mirror_list_registry[@]}): ${PLAIN}" choice
        if [[ $choice =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#mirror_list_registry[@]})); then
            SELECTED_REGISTRY="${mirror_list_registry[$((choice-1))]#*@}"
            break
        else
            echo -e "${RED}无效输入，请重新选择${PLAIN}"
        fi
    done
}

function configure_mirror() {
    case $OS_NAME in
    centos|rhel|almalinux|rocky)
        echo -e "\n${GREEN}▶ 配置Yum仓库...${PLAIN}"
        sudo tee /etc/yum.repos.d/docker-ce.repo <<EOF
[docker-ce-stable]
name=Docker CE Stable - \$basearch
baseurl=https://$SELECTED_SOURCE/centos/\$releasever/\$basearch/stable
enabled=1
gpgcheck=1
gpgkey=https://$SELECTED_SOURCE/gpg
EOF
        ;;
    ubuntu|debian)
        echo -e "\n${GREEN}▶ 配置APT源...${PLAIN}"
        sudo tee /etc/apt/sources.list.d/docker-ce.list <<EOF
deb [arch=$(dpkg --print-architecture)] https://$SELECTED_SOURCE/ubuntu $(lsb_release -cs) stable
EOF
        ;;
    *)
        echo -e "${RED}✗ 不支持的发行版：$OS_NAME${PLAIN}"
        exit 1
        ;;
    esac
}

function install_docker() {
    echo -e "\n${GREEN}▶ 开始安装Docker...${PLAIN}"
    case $OS_NAME in
    centos|rhel|almalinux|rocky)
        sudo yum remove -y docker* >/dev/null 2>&1
        sudo yum install -y yum-utils >/dev/null 2>&1
        sudo yum-config-manager --add-repo https://$SELECTED_SOURCE/repo/centos.repo
        sudo yum install -y docker-ce docker-ce-cli containerd.io
        ;;
    ubuntu|debian)
        sudo apt-get remove -y docker* >/dev/null 2>&1
        sudo apt-get update >/dev/null 2>&1
        sudo apt-get install -y \
            apt-transport-https \
            ca-certificates \
            curl \
            gnupg \
            lsb-release
        curl -fsSL https://$SELECTED_SOURCE/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        sudo apt-get update >/dev/null 2>&1
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io
        ;;
    esac

    if ! systemctl is-active --quiet docker; then
        sudo systemctl start docker
        sudo systemctl enable docker
    fi
}

function configure_registry() {
    echo -e "\n${GREEN}▶ 配置Registry镜像...${PLAIN}"
    sudo mkdir -p /etc/docker
    sudo tee /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["https://$SELECTED_REGISTRY"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  }
}
EOF
    sudo systemctl daemon-reload
    sudo systemctl restart docker
}

function main() {
    permission_judgment
    collect_system_info
    init_status_check
    choose_mirrors
    configure_mirror
    install_docker
    configure_registry

    echo -e "\n${GREEN}✓ 安装完成！验证信息：${PLAIN}"
    docker --version 2>/dev/null || echo -e "${RED}✗ Docker未正确安装${PLAIN}"
    
    echo -e "\n${BOLD}Registry状态：${PLAIN}"
    docker info 2>/dev/null | grep -i mirror || echo -e "${RED}✗ 无法获取Registry信息${PLAIN}"
}

# 执行主程序
main