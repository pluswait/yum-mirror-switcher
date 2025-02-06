#!/bin/bash

# 全局超时设置（秒）
TIMEOUT=5
CHECK_FILE="docker-ce/ubuntu/dists/focal/InRelease"

## Docker CE 软件源列表
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

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
PLAIN='\033[0m'
BOLD='\033[1m'

# 可达性状态存储
declare -A MIRROR_STATUS
declare -A REGISTRY_STATUS

## 基础函数定义
function check_connectivity() {
    local url=$1
    local proxy_opts=""
    
    # 自动检测代理设置
    if [ -n "$http_proxy" ]; then
        proxy_opts="--proxy $http_proxy"
    elif [ -n "$HTTP_PROXY" ]; then
        proxy_opts="--proxy $HTTP_PROXY"
    fi

    if curl -sI $proxy_opts --connect-timeout $TIMEOUT "${url}/${CHECK_FILE}" | grep -q "200 OK"; then
        return 0
    else
        return 1
    fi
}

function init_status_check() {
    # 并行检查Docker CE镜像源
    for entry in "${mirror_list_docker_ce[@]}"; do
        {
            address="${entry#*@}"
            if check_connectivity "https://$address"; then
                MIRROR_STATUS[$address]="${GREEN}✓${PLAIN}"
            else
                MIRROR_STATUS[$address]="${RED}✗${PLAIN}"
            fi
        } &
    done

    # 并行检查Registry镜像
    for entry in "${mirror_list_registry[@]}"; do
        {
            address="${entry#*@}"
            if curl -sI --connect-timeout $TIMEOUT "https://$address/v2/" | grep -q "200 OK"; then
                REGISTRY_STATUS[$address]="${GREEN}✓${PLAIN}"
            else
                REGISTRY_STATUS[$address]="${RED}✗${PLAIN}"
            fi
        } &
    done

    wait # 等待所有后台任务完成
}

function permission_judgment() {
    if [ $UID -ne 0 ]; then
        echo -e "${RED}✗ 请使用 Root 用户运行本脚本${PLAIN}"
        exit 1
    fi
}

function collect_system_info() {
    # 系统信息收集逻辑
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        OS_NAME=$ID
        OS_VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        OS_NAME=$(cat /etc/redhat-release | awk '{print $1}')
        OS_VERSION=$(cat /etc/redhat-release | sed -n 's/.*release \([0-9]\+\).*/\1/p')
    else
        echo -e "${RED}✗ 不支持的操作系统${PLAIN}"
        exit 1
    fi
}

function choose_mirrors() {
    echo -e "\n${BOLD}=== 可用 Docker CE 镜像源 ===${PLAIN}"
    local i=1
    for entry in "${mirror_list_docker_ce[@]}"; do
        name="${entry%@*}"
        address="${entry#*@}"
        printf "%2d. %-20s %-45s [%s]\n" $i "$name" "$address" "${MIRROR_STATUS[$address]}"
        ((i++))
    done

    while true; do
        read -p $'\n'"${BOLD}请选择 Docker CE 镜像源 (1-${#mirror_list_docker_ce[@]}): ${PLAIN}" choice
        if [[ $choice =~ ^[0-9]+$ ]] && [ $choice -ge 1 ] && [ $choice -le ${#mirror_list_docker_ce[@]} ]; then
            SELECTED_SOURCE="${mirror_list_docker_ce[$((choice-1))]#*@}"
            break
        else
            echo -e "${RED}无效选择，请重新输入${PLAIN}"
        fi
    done

    echo -e "\n${BOLD}=== 可用 Registry 镜像 ===${PLAIN}"
    i=1
    for entry in "${mirror_list_registry[@]}"; do
        name="${entry%@*}"
        address="${entry#*@}"
        printf "%2d. %-20s %-45s [%s]\n" $i "$name" "$address" "${REGISTRY_STATUS[$address]}"
        ((i++))
    done

    while true; do
        read -p $'\n'"${BOLD}请选择 Registry 镜像 (1-${#mirror_list_registry[@]}): ${PLAIN}" choice
        if [[ $choice =~ ^[0-9]+$ ]] && [ $choice -ge 1 ] && [ $choice -le ${#mirror_list_registry[@]} ]; then
            SELECTED_REGISTRY="${mirror_list_registry[$((choice-1))]#*@}"
            break
        else
            echo -e "${RED}无效选择，请重新输入${PLAIN}"
        fi
    done
}

function configure_mirror() {
    # 配置镜像源逻辑（根据不同发行版实现）
    case $OS_NAME in
    centos|rhel|almalinux|rocky)
        echo -e "${GREEN}▶ 配置Yum仓库...${PLAIN}"
        sudo sed -i.bak -e "s|baseurl=.*docker-ce|baseurl=https://$SELECTED_SOURCE|" /etc/yum.repos.d/docker-ce.repo
        ;;
    ubuntu|debian)
        echo -e "${GREEN}▶ 配置APT源...${PLAIN}"
        sudo tee /etc/apt/sources.list.d/docker-ce.list <<EOF
deb [arch=$(dpkg --print-architecture)] https://$SELECTED_SOURCE $(lsb_release -cs) stable
EOF
        ;;
    *)
        echo -e "${RED}✗ 不支持的发行版：$OS_NAME${PLAIN}"
        exit 1
        ;;
    esac
}

function install_docker() {
    echo -e "${GREEN}▶ 开始安装Docker...${PLAIN}"
    case $OS_NAME in
    centos|rhel|almalinux|rocky)
        sudo yum remove -y docker* || true
        sudo yum install -y yum-utils
        sudo yum-config-manager --add-repo https://$SELECTED_SOURCE/repo/centos.repo
        sudo yum install -y docker-ce docker-ce-cli containerd.io
        ;;
    ubuntu|debian)
        sudo apt-get remove -y docker* || true
        sudo apt-get update
        sudo apt-get install -y \
            apt-transport-https \
            ca-certificates \
            curl \
            gnupg \
            lsb-release
        curl -fsSL https://$SELECTED_SOURCE/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io
        ;;
    esac
}

function configure_registry() {
    echo -e "${GREEN}▶ 配置Registry镜像...${PLAIN}"
    sudo mkdir -p /etc/docker
    sudo tee /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["https://$SELECTED_REGISTRY"]
}
EOF
    sudo systemctl daemon-reload
    sudo systemctl restart docker
}

## 主流程
function main() {
    permission_judgment
    init_status_check
    collect_system_info
    choose_mirrors
    configure_mirror
    install_docker
    configure_registry
    
    echo -e "\n${GREEN}✓ 安装完成！验证信息：${PLAIN}"
    docker --version
    curl -s https://$SELECTED_SOURCE/$CHECK_FILE | head -n 3
    echo -e "\nRegistry状态："
    docker info | grep -i mirror
}

# 初始化状态检查并启动主流程
init_status_check
main
