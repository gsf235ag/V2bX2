#!/bin/bash

# 设置路径
CRON_DIR="/etc/Cron"
LOG_DIR="/var/log/cron_tasks"
CRON_BACKUP="/tmp/current_crontab.bak"

# 确保目录存在并设置权限
mkdir -p "$CRON_DIR"
mkdir -p "$LOG_DIR"
chmod 755 "$CRON_DIR"
chmod 755 "$LOG_DIR"

# 同步北京时间
sync_time() {
    echo "正在同步北京时间..."
    if ! command -v ntpdate >/dev/null 2>&1; then
        echo "未检测到 ntpdate，正在尝试安装..."
        apt-get install -y ntpdate 2>/dev/null || yum install -y ntpdate
    fi
    ntpdate ntp.aliyun.com
    hwclock -w
}

# 显示当前时间和 Cron 状态
show_header() {
    clear
    echo "==================== 定时任务管理器 ===================="
    echo "当前系统时间：$(date +"%Y-%m-%d %H:%M:%S")"
    systemctl is-active cron >/dev/null 2>&1 && cron_status="运行中" || cron_status="未启动"
    echo "Cron 状态：$cron_status"
    echo "========================================================"
}

# 生成 cron 时间表达式
get_cron_time() {
    echo "请选择执行频率："
    echo "1) 每分钟执行"
    echo "2) 每小时执行"
    echo "3) 每3小时执行"
    echo "4) 每6小时执行"
    echo "5) 每8小时执行"
    echo "6) 每16小时执行"
    echo "7) 每天执行（凌晨0点）"
    echo "8) 每天凌晨3点执行"
    echo "9) 自定义 Cron 表达式"
    read -rp "输入序号 [1-9]: " choice

    case $choice in
        1) cron_expr="* * * * *" ;;
        2) cron_expr="0 * * * *" ;;
        3) cron_expr="0 */3 * * *" ;;
        4) cron_expr="0 */6 * * *" ;;
        5) cron_expr="0 */8 * * *" ;;
        6) cron_expr="0 */16 * * *" ;;
        7) cron_expr="0 0 * * *" ;;
        8) cron_expr="0 3 * * *" ;;
        9) read -rp "请输入完整 Cron 表达式: " cron_expr ;;
        *) echo "无效选择"; return 1 ;;
    esac

    return 0
}

# 添加任务（支持任意命令或脚本）
add_task() {
    read -rp "请输入要执行的命令或脚本路径（例如 systemctl restart V2bX.service 或 /root/csv2.sh）: " cmd
    
    # 根据输入生成任务名
    if [[ "$cmd" =~ systemctl[[:space:]]+restart[[:space:]]+([^.[:space:]]+) ]]; then
        service_name="${BASH_REMATCH[1]}"
    else
        service_name=$(basename "$cmd")
    fi
    service_name="${service_name%.service}"

    script_path="$CRON_DIR/$service_name"
    log_path="$LOG_DIR/task_${service_name}.log"

    get_cron_time || return

    cat > "$script_path" <<EOF
#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
export PATH

echo "----------------------------------------------------------------------------"
echo "→ 正在执行：$cmd"
$cmd
if [ \$? -eq 0 ]; then
    echo "★[\$(date +"%Y-%m-%d %H:%M:%S")] ✅ 执行成功"
else
    echo "★[\$(date +"%Y-%m-%d %H:%M:%S")] ❌ 执行失败"
fi
echo "----------------------------------------------------------------------------"
EOF

    chmod 755 "$script_path"
    touch "$log_path"
    chmod 644 "$log_path"

    crontab -l 2>/dev/null > "$CRON_BACKUP"
    echo "$cron_expr $script_path >> $log_path 2>&1" >> "$CRON_BACKUP"
    crontab "$CRON_BACKUP"

    systemctl restart cron
    echo "✅ 任务添加成功！"
}

# 删除任务
delete_task() {
    echo "当前任务列表："
    ls "$CRON_DIR"
    echo
    read -rp "请输入要删除的任务名称（如 V2bX 或 csv2.sh，输入 0 取消）: " name

    if [[ -z "$name" || "$name" == "0" ]]; then
        echo "❎ 已取消删除任务"
        return
    fi

    script_path="$CRON_DIR/$name"
    log_path="$LOG_DIR/task_${name}.log"

    if [[ ! -f "$script_path" ]]; then
        echo "⚠️ 找不到指定的任务脚本：$script_path"
        return
    fi

    crontab -l 2>/dev/null | grep -v "$script_path" > "$CRON_BACKUP"
    crontab "$CRON_BACKUP"

    rm -f "$script_path"
    rm -f "$log_path"
    systemctl restart cron
    echo "✅ 任务 [$name] 已删除并重载 Cron"
}

# 查看任务
view_tasks() {
    echo "当前任务列表："
    crontab -l | grep "$CRON_DIR" || echo "无任务"

    echo
    echo "可用日志："
    ls -1 "$LOG_DIR"

    read -rp "是否查看某个日志内容？输入日志文件名（或回车跳过）: " logname
    if [[ -n "$logname" ]] && [[ -f "$LOG_DIR/$logname" ]]; then
        echo "========== 日志内容 =========="
        tail -n 30 "$LOG_DIR/$logname"
        echo "=============================="
    fi
}

# 主菜单
main_menu() {
    while true; do
        show_header
        echo "1) 添加定时任务"
        echo "2) 删除定时任务"
        echo "3) 查看任务和日志"
        echo "0) 退出脚本"
        echo "--------------------------------------------------------"
        read -rp "请输入选项: " option
        case "$option" in
            1) add_task ;;
            2) delete_task ;;
            3) view_tasks ;;
            0) echo "再见！"; exit 0 ;;
            *) echo "无效选项，请重试。" ;;
        esac
        read -rp "按 Enter 返回菜单..."
    done
}

# 启动脚本
sync_time
main_menu
