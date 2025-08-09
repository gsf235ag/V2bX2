#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
plain='\033[0m'

# 检查root权限
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# 检查是否已安装V2bX
if [[ ! -f /usr/local/V2bX/V2bX ]]; then
    echo -e "${red}错误：${plain} 未检测到V2bX安装，请先安装V2bX！\n"
    exit 1
fi

# 检测操作系统
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "alpine"; then
    release="alpine"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "arch"; then
    release="arch"
else
    echo -e "${red}未检测到系统版本！${plain}\n" && exit 1
fi

# 检测架构
arch=$(uname -m)
if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64-v8a"
elif [[ $arch == "s390x" ]]; then
    arch="s390x"
else
    arch="64"
    echo -e "${yellow}检测架构失败，使用默认架构: ${arch}${plain}"
fi

echo -e "${blue}===========================================${plain}"
echo -e "${blue}           V2bX 更新脚本               ${plain}"
echo -e "${blue}===========================================${plain}"
echo -e "检测到系统: ${green}${release}${plain}"
echo -e "检测到架构: ${green}${arch}${plain}"
echo ""

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /usr/local/V2bX/V2bX ]]; then
        return 2
    fi
    if [[ x"${release}" == x"alpine" ]]; then
        temp=$(service V2bX status | awk '{print $3}')
        if [[ x"${temp}" == x"started" ]]; then
            return 0
        else
            return 1
        fi
    else
        temp=$(systemctl status V2bX | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
        if [[ x"${temp}" == x"running" ]]; then
            return 0
        else
            return 1
        fi
    fi
}

# 获取当前版本
get_current_version() {
    if [[ -f /usr/local/V2bX/V2bX ]]; then
        current_version=$(/usr/local/V2bX/V2bX version 2>/dev/null | head -1 || echo "未知版本")
        echo -e "当前版本: ${green}${current_version}${plain}"
    else
        echo -e "${red}无法获取当前版本${plain}"
    fi
}

# 更新V2bX
update_v2bx() {
    # 询问要安装的版本
    echo -n "输入指定版本(默认最新版): "
    read -r target_version
    
    if [[ -n "$target_version" ]]; then
        # 用户指定了版本
        echo -e "准备更新到指定版本: ${green}${target_version}${plain}"
        download_url="https://github.com/gsf235ag/V2bX/releases/download/${target_version}/V2bX-linux-${arch}.zip"
        last_version="$target_version"
    else
        # 使用最新版本
        echo -e "${yellow}正在获取最新版本信息...${plain}"
        last_version=$(curl -Ls "https://api.github.com/repos/gsf235ag/V2bX/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}获取V2bX最新版本失败，可能是超出Github API限制${plain}"
            echo -e "${yellow}尝试继续更新...${plain}"
            # 如果无法获取版本号，尝试直接下载latest
            download_url="https://github.com/gsf235ag/V2bX/releases/latest/download/V2bX-linux-${arch}.zip"
            last_version="latest"
        else
            echo -e "检测到V2bX最新版本: ${green}${last_version}${plain}"
            download_url="https://github.com/gsf235ag/V2bX/releases/download/${last_version}/V2bX-linux-${arch}.zip"
        fi
    fi
    
    # 检查服务状态
    check_status
    service_was_running=$?
    
    if [[ $service_was_running -eq 0 ]]; then
        echo -e "${yellow}检测到V2bX正在运行，正在停止服务...${plain}"
        if [[ x"${release}" == x"alpine" ]]; then
            service V2bX stop
        else
            systemctl stop V2bX
        fi
        echo -e "${green}服务已停止${plain}"
    fi
    
    # 备份当前版本
    backup_file="/usr/local/V2bX/V2bX.backup.$(date +%Y%m%d_%H%M%S)"
    if [[ -f /usr/local/V2bX/V2bX ]]; then
        echo -e "${yellow}备份当前版本到: ${backup_file}${plain}"
        cp /usr/local/V2bX/V2bX "$backup_file"
    fi
    
    # 进入安装目录
    cd /usr/local/V2bX/
    
    # 下载新版本
    echo -e "${yellow}正在下载V2bX ${last_version}...${plain}"
    echo -e "下载地址: ${blue}${download_url}${plain}"
    
    if wget --no-check-certificate -N --progress=bar -O V2bX-linux.zip "${download_url}"; then
        echo -e "${green}下载完成${plain}"
    else
        echo -e "${red}下载失败，正在恢复备份...${plain}"
        if [[ -f "$backup_file" ]]; then
            cp "$backup_file" /usr/local/V2bX/V2bX
            chmod +x /usr/local/V2bX/V2bX
        fi
        # 如果服务之前在运行，重新启动
        if [[ $service_was_running -eq 0 ]]; then
            if [[ x"${release}" == x"alpine" ]]; then
                service V2bX start
            else
                systemctl start V2bX
            fi
        fi
        exit 1
    fi
    
    # 解压并安装
    echo -e "${yellow}正在解压和安装...${plain}"
    if unzip -o V2bX-linux.zip; then
        rm V2bX-linux.zip -f
        chmod +x V2bX
        
        # 更新geo文件（如果存在）
        if [[ -f geoip.dat ]]; then
            cp geoip.dat /etc/V2bX/
            echo -e "${green}geoip.dat 已更新${plain}"
        fi
        if [[ -f geosite.dat ]]; then
            cp geosite.dat /etc/V2bX/
            echo -e "${green}geosite.dat 已更新${plain}"
        fi
        
        echo -e "${green}V2bX更新完成${plain}"
        
        # 获取新版本信息
        new_version=$(/usr/local/V2bX/V2bX version 2>/dev/null | head -1 || echo "未知版本")
        echo -e "新版本: ${green}${new_version}${plain}"
        
        # 重新启动服务
        if [[ $service_was_running -eq 0 ]]; then
            echo -e "${yellow}正在启动V2bX服务...${plain}"
            if [[ x"${release}" == x"alpine" ]]; then
                service V2bX start
            else
                systemctl start V2bX
            fi
            
            # 等待服务启动
            sleep 3
            
            # 检查服务状态
            check_status
            if [[ $? -eq 0 ]]; then
                echo -e "${green}V2bX服务启动成功${plain}"
                # 删除备份文件（可选）
                echo -n "更新成功！是否删除备份文件？[y/N]: "
                read -r delete_backup
                if [[ $delete_backup =~ ^[Yy]$ ]]; then
                    rm -f "$backup_file"
                    echo -e "${green}备份文件已删除${plain}"
                else
                    echo -e "${yellow}备份文件保留在: ${backup_file}${plain}"
                fi
            else
                echo -e "${red}V2bX服务启动失败，正在恢复备份...${plain}"
                if [[ -f "$backup_file" ]]; then
                    cp "$backup_file" /usr/local/V2bX/V2bX
                    chmod +x /usr/local/V2bX/V2bX
                    if [[ x"${release}" == x"alpine" ]]; then
                        service V2bX start
                    else
                        systemctl start V2bX
                    fi
                    echo -e "${yellow}已恢复到备份版本${plain}"
                fi
                exit 1
            fi
        else
            echo -e "${yellow}V2bX未在运行，更新完成但未启动服务${plain}"
            echo -e "${blue}提示：使用 'V2bX start' 命令启动服务${plain}"
        fi
        
    else
        echo -e "${red}解压失败，正在恢复备份...${plain}"
        rm V2bX-linux.zip -f
        if [[ -f "$backup_file" ]]; then
            cp "$backup_file" /usr/local/V2bX/V2bX
            chmod +x /usr/local/V2bX/V2bX
        fi
        # 如果服务之前在运行，重新启动
        if [[ $service_was_running -eq 0 ]]; then
            if [[ x"${release}" == x"alpine" ]]; then
                service V2bX start
            else
                systemctl start V2bX
            fi
        fi
        exit 1
    fi
}

# 清理备份文件
cleanup_backups() {
    echo -e "${yellow}正在查找备份文件...${plain}"
    backup_files=$(find /usr/local/V2bX/ -name "V2bX.backup.*" -type f 2>/dev/null)
    
    if [[ -z "$backup_files" ]]; then
        echo -e "${green}没有找到备份文件${plain}"
        return
    fi
    
    echo -e "${blue}找到以下备份文件:${plain}"
    ls -lh /usr/local/V2bX/V2bX.backup.* 2>/dev/null
    
    echo -n "是否删除所有备份文件？[y/N]: "
    read -r confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        rm -f /usr/local/V2bX/V2bX.backup.*
        echo -e "${green}备份文件清理完成${plain}"
    else
        echo -e "${yellow}保留备份文件${plain}"
    fi
}

# 主程序
echo -e "${blue}===========================================${plain}"
echo -e "${blue}           V2bX 更新脚本               ${plain}"
echo -e "${blue}===========================================${plain}"
echo ""

# 显示当前版本
get_current_version
echo ""

# 显示当前服务状态
check_status
case $? in
    0)
        echo -e "服务状态: ${green}✅ 运行中${plain}"
        ;;
    1)
        echo -e "服务状态: ${yellow}⚠️ 未运行${plain}"
        ;;
    2)
        echo -e "服务状态: ${red}❌ 未安装${plain}"
        exit 1
        ;;
esac
echo ""

# 询问操作
echo "请选择操作："
echo "1. 更新到最新版本"
echo "2. 清理备份文件"
echo "3. 取消"
echo ""
echo -n "请输入选项 [1-3]: "
read -r choice

case $choice in
    1)
        echo ""
        update_v2bx
        ;;
    2)
        echo ""
        cleanup_backups
        ;;
    3)
        echo -e "${yellow}取消更新${plain}"
        exit 0
        ;;
    *)
        echo -e "${red}无效选项${plain}"
        exit 1
        ;;
esac

echo ""
echo -e "${green}===========================================${plain}"
echo -e "${green}           更新操作完成               ${plain}"
echo -e "${green}===========================================${plain}"