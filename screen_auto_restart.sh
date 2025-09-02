#!/bin/bash

# RL Swarm 自动重启脚本（包含Screen会话管理）
# 使用方法: ./screen_auto_restart.sh

set -euo pipefail

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Screen会话名称
SCREEN_NAME="gensyn"

# PID文件路径
PID_FILE="/tmp/rl_swarm_daemon.pid"

# 检查是否已有实例运行
check_existing_instance() {
    if [ -f "$PID_FILE" ]; then
        local existing_pid=$(cat "$PID_FILE")
        if kill -0 "$existing_pid" 2>/dev/null; then
            log_warn "检测到已有实例运行 (PID: $existing_pid)"
            log_info "如需启动新实例，请先停止旧实例：$0 --stop"
            return 1
        else
            log_info "清理过期的PID文件"
            rm -f "$PID_FILE"
        fi
    fi
    return 0
}

# 创建PID文件
create_pid_file() {
    echo $$ > "$PID_FILE"
    log_info "创建PID文件: $PID_FILE (PID: $$)"
}

# 清理PID文件
cleanup_pid_file() {
    if [ -f "$PID_FILE" ]; then
        rm -f "$PID_FILE"
        log_info "清理PID文件: $PID_FILE"
    fi
}

# 检查screen是否安装
check_screen() {
    if ! command -v screen &> /dev/null; then
        log_error "screen未安装，正在安装..."
        apt-get update && apt-get install -y screen
    fi
}

# 创建或连接到screen会话
setup_screen() {
    log_info "设置Screen会话: $SCREEN_NAME"
    
    # 检查是否有多个screen会话，如果有则清理
    local session_count=$(screen -list | grep -c "$SCREEN_NAME" || echo "0")
    if [ "$session_count" -gt 1 ]; then
        log_warn "检测到多个screen会话，清理重复会话..."
        screen -ls | grep "$SCREEN_NAME" | awk '{print $1}' | while read session; do
            log_info "删除重复的screen会话: $session"
            screen -S "$session" -X quit 2>/dev/null || true
        done
        sleep 2
    fi
}

# 备份认证文件
backup_auth_files() {
    log_info "备份认证文件..."
    mkdir -p /root/backup
    
    if [ -f "/root/rl-swarm/modal-login/temp-data/userApiKey.json" ]; then
        cp "/root/rl-swarm/modal-login/temp-data/userApiKey.json" "/root/backup/"
        log_info "已备份 userApiKey.json"
    else
        log_warn "userApiKey.json 不存在，跳过备份"
    fi
    
    if [ -f "/root/rl-swarm/modal-login/temp-data/userData.json" ]; then
        cp "/root/rl-swarm/modal-login/temp-data/userData.json" "/root/backup/"
        log_info "已备份 userData.json"
    else
        log_warn "userData.json 不存在，跳过备份"
    fi
}

# 恢复认证文件
restore_auth_files() {
    log_info "恢复认证文件..."
    mkdir -p "/root/rl-swarm/modal-login/temp-data"
    
    if [ -f "/root/backup/userApiKey.json" ]; then
        cp "/root/backup/userApiKey.json" "/root/rl-swarm/modal-login/temp-data/"
        log_info "已恢复 userApiKey.json"
    fi
    
    if [ -f "/root/backup/userData.json" ]; then
        cp "/root/backup/userData.json" "/root/rl-swarm/modal-login/temp-data/"
        log_info "已恢复 userData.json"
    fi
}

# 启动或重启RL Swarm（统一函数）
start_or_restart_rl_swarm() {
    local is_restart=${1:-false}
    
    if [ "$is_restart" = true ]; then
        log_info "重启RL Swarm..."
        
        # 删除所有旧的screen会话
        log_info "删除所有旧的screen会话..."
        screen -ls | grep "$SCREEN_NAME" | awk '{print $1}' | while read session; do
            log_info "删除screen会话: $session"
            screen -S "$session" -X quit 2>/dev/null || true
        done
        sleep 3
        
        # 确保所有screen会话都已删除
        while screen -list | grep -q "$SCREEN_NAME"; do
            log_info "等待screen会话完全删除..."
            sleep 1
        done
    else
        log_info "启动RL Swarm..."
    fi
    
    # 恢复认证文件
    log_info "恢复认证文件..."
    restore_auth_files
    
    # 创建新的screen会话
    log_info "创建新的screen会话..."
    screen -dmS "$SCREEN_NAME" bash -c "cd /root && exec bash"
    sleep 2
    
    # 在screen会话中启动RL Swarm
    log_info "在screen会话中启动RL Swarm..."
    screen -S "$SCREEN_NAME" -X stuff "cd /root/rl-swarm$(printf '\r')"
    sleep 1
    screen -S "$SCREEN_NAME" -X stuff "source .venv/bin/activate$(printf '\r')"
    sleep 1
    screen -S "$SCREEN_NAME" -X stuff "export CUDA_VISIBLE_DEVICES=""$(printf '\r')"
    sleep 1
    screen -S "$SCREEN_NAME" -X stuff "./run_rl_swarm.sh$(printf '\r')"
    
    log_info "RL Swarm已在screen会话中启动"
    
    # 启动日志捕获
    log_info "启动日志捕获..."
    LOG_FILE="/tmp/rl_swarm_screen.log"
    screen -S "$SCREEN_NAME" -X logfile "$LOG_FILE"
    screen -S "$SCREEN_NAME" -X log on
    sleep 2
    
    # 重置监控状态
    log_info "重置监控状态..."
    startup_complete=false
    auth_handled=false
    
    # 开始监控（形成循环）
    log_info "开始监控..."
    monitor_rl_swarm
}

# 监控RL Swarm输出
monitor_rl_swarm() {
    log_info "开始监控RL Swarm输出..."
    
    while true; do
        # 创建临时日志文件来捕获screen输出
        LOG_FILE="/tmp/rl_swarm_screen.log"
        
        # 清理过大的日志文件
        if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -gt 10485760 ]; then  # 10MB
            log_info "清理过大的日志文件..."
            rm -f "$LOG_FILE"
        fi
        
        # 启动screen日志捕获
        screen -S "$SCREEN_NAME" -X logfile "$LOG_FILE"
        screen -S "$SCREEN_NAME" -X log on
        
        sleep 5
        
        # 初始化状态变量
        startup_complete=false
        auth_handled=false
        startup_start_time=$(date +%s)
        last_log_update=$(date +%s)  # 记录最后日志更新时间
        
        # 监控screen日志文件
        # 使用临时文件来共享变量状态
        echo "$(date +%s)" > /tmp/last_log_update.tmp
        
        tail -f "$LOG_FILE" 2>/dev/null | while read line; do
            # 过滤掉screen的控制字符
            clean_line=$(echo "$line" | sed 's/\x1b\[[0-9;]*m//g' | sed 's/\r//g')
            
            if [ -n "$clean_line" ]; then
                echo "$clean_line"
                # 更新最后日志时间到临时文件
                echo "$(date +%s)" > /tmp/last_log_update.tmp
                
                # 检测启动完成标志
                if echo "$clean_line" | grep -q "Good luck in the swarm!"; then
                    startup_complete=true
                    log_info "RL Swarm启动完成"
                elif echo "$clean_line" | grep -q "Starting round:"; then
                    startup_complete=true
                    log_info "RL Swarm启动完成（检测到round开始）"
                elif echo "$clean_line" | grep -q "Connected to peer"; then
                    startup_complete=true
                    log_info "RL Swarm启动完成（检测到peer连接）"
                fi
                
                # 检测任何需要交互的提示（统一处理）
                if [ "$auth_handled" = false ]; then
                    if echo "$clean_line" | grep -q "Waiting for modal userData.json to be created"; then
                        log_info "检测到等待userData.json，恢复备份文件并发送输入..."
                        restore_auth_files
                        auth_handled=true
                        sleep 3
                        screen -S "$SCREEN_NAME" -X stuff "N$(printf '\r')"
                        sleep 2
                        screen -S "$SCREEN_NAME" -X stuff "Gensyn/Qwen2.5-0.5B-Instruct$(printf '\r')"
                        sleep 2
                        screen -S "$SCREEN_NAME" -X stuff "Y$(printf '\r')"
                    elif echo "$clean_line" | grep -q "Would you like to push models you train in the RL swarm to the Hugging Face Hub?"; then
                        log_info "检测到Hugging Face Hub推送提示，发送输入..."
                        auth_handled=true
                        sleep 2
                        screen -S "$SCREEN_NAME" -X stuff "N$(printf '\r')"
                        sleep 2
                        screen -S "$SCREEN_NAME" -X stuff "Gensyn/Qwen2.5-0.5B-Instruct$(printf '\r')"
                        sleep 2
                        screen -S "$SCREEN_NAME" -X stuff "Y$(printf '\r')"
                    fi
                fi
                
                # 检测异常错误（优先级最高，无论启动状态）
                if echo "$clean_line" | grep -E "(ERROR: Exception occurred during game run\.|Traceback \(most recent call last\):)"; then
                    log_warn "检测到游戏运行异常，准备重启..."
                    sleep 20
                    start_or_restart_rl_swarm true
                    break
                fi
                
                # 检测程序异常退出（优先级最高，无论启动状态）
                if echo "$clean_line" | grep -E "(Terminated|Killed|Aborted|Segmentation fault)"; then
                    log_warn "检测到程序异常退出，准备重启..."
                    sleep 10
                    start_or_restart_rl_swarm true
                    break
                fi
                
                # 检测其他常见错误模式
                if echo "$clean_line" | grep -E "(ConnectionError|TimeoutError|Connection refused|Connection reset)"; then
                    log_warn "检测到连接错误，准备重启..."
                    sleep 15
                    start_or_restart_rl_swarm true
                    break
                fi
                
                
                           # 检测Peer ID并监控score变化
                if echo "$clean_line" | grep -q "Peer ID.*is already registered"; then
                    # 提取Peer ID
                    current_peer_id=$(echo "$clean_line" | grep -o "Qm[a-zA-Z0-9]*")
                    if [ -n "$current_peer_id" ]; then
                        log_info "检测到Peer ID: $current_peer_id"
                        
                        # 将Peer ID保存到临时文件
                        echo "$current_peer_id" > /tmp/current_peer_id.tmp
                        
                        # 初始化score监控
                        if [ ! -f "/tmp/last_score_check.tmp" ]; then
                            echo "$(date +%s)" > /tmp/last_score_check.tmp
                            echo "0" > /tmp/last_score.tmp
                        fi
                        
                        # 立即获取一次score
                        current_score=$(timeout 10 curl -s "https://dashboard.gensyn.ai/api/v1/peer?id=$current_peer_id" 2>/dev/null | grep -o '"score":[0-9]*' | grep -o '[0-9]*')
                        
                        if [ -n "$current_score" ] && [ "$current_score" -gt 0 ]; then
                            log_info "当前score: $current_score"
                            echo "$current_score" > /tmp/last_score.tmp
                            echo "$(date +%s)" > /tmp/last_score_check.tmp
                        else
                            log_warn "无法获取当前score信息"
                        fi
                    fi
                fi
                
                # 定期检查score变化（每4小时检查一次）
                if [ -f "/tmp/last_score_check.tmp" ] && [ -f "/tmp/last_score.tmp" ]; then
                    current_time=$(date +%s)
                    last_check_time=$(cat /tmp/last_score_check.tmp)
                    time_since_last_check=$((current_time - last_check_time))
                    
                    # 4小时 = 14400秒
                    if [ $time_since_last_check -ge 14400 ]; then
                        log_info "执行定期score检查..."
                        
                        if [ -f "/tmp/current_peer_id.tmp" ]; then
                            current_peer_id=$(cat /tmp/current_peer_id.tmp)
                            last_score=$(cat /tmp/last_score.tmp)
                            
                            # 获取最新score
                            new_score=$(timeout 10 curl -s "https://dashboard.gensyn.ai/api/v1/peer?id=$current_peer_id" 2>/dev/null | grep -o '"score":[0-9]*' | grep -o '[0-9]*')
                            
                            if [ -n "$new_score" ] && [ "$new_score" -gt 0 ]; then
                                log_info "Score检查: 上次=$last_score, 当前=$new_score"
                                
                                if [ "$new_score" -eq "$last_score" ]; then
                                    log_warn "检测到score无变化 (上次: $last_score, 当前: $new_score)，准备重启..."
                                    sleep 5
                                    start_or_restart_rl_swarm true
                                    break
                                else
                                    log_info "Score有变化，更新记录"
                                    echo "$new_score" > /tmp/last_score.tmp
                                fi
                            else
                                log_warn "无法获取最新score信息"
                            fi
                        else
                            log_warn "未找到Peer ID，跳过score检查"
                        fi
                        
                        # 更新检查时间
                        echo "$(date +%s)" > /tmp/last_score_check.tmp
                    fi
                fi
                # 检测程序是否长时间没有输出（可能卡住了）
                # 只有在启动完成且运行一段时间后才检查
                if [ "$startup_complete" = true ]; then
                    current_time=$(date +%s)
                    startup_duration=$((current_time - startup_start_time))
                    # 从临时文件读取最后日志更新时间
                    if [ -f "/tmp/last_log_update.tmp" ]; then
                        last_log_update=$(cat /tmp/last_log_update.tmp)
                        time_since_last_log=$((current_time - last_log_update))
                        
                        # 只有在启动完成超过10分钟后才开始检查长时间无输出
                        if [ $startup_duration -gt 600 ] && [ $time_since_last_log -gt 1800 ]; then  # 启动30分钟后，30分钟无输出
                            log_warn "检测到程序长时间无输出 (启动${startup_duration}秒后，${time_since_last_log}秒无输出)，可能卡住了，准备重启..."
                            start_or_restart_rl_swarm true
                            break
                        fi
                    fi
                fi
            fi
        done
        
        # 检查RL Swarm进程是否还在运行
        if ! pgrep -f "run_rl_swarm.sh" > /dev/null && ! pgrep -f "rgym_exp" > /dev/null; then
            log_warn "RL Swarm进程已停止，准备重启..."
            start_or_restart_rl_swarm true
            sleep 5
        fi
        
        # 检查screen会话是否存在，如果不存在则重启
        if ! screen -list | grep -q "$SCREEN_NAME"; then
            log_warn "Screen会话不存在，准备重启..."
            start_or_restart_rl_swarm true
            sleep 5
        fi
        
        # 检查日志是否卡住（只有在启动完成且运行一段时间后才检查）
        if [ "$startup_complete" = true ]; then
            current_time=$(date +%s)
            startup_duration=$((current_time - startup_start_time))
            # 从临时文件读取最后日志更新时间
            if [ -f "/tmp/last_log_update.tmp" ]; then
                last_log_update=$(cat /tmp/last_log_update.tmp)
                time_since_last_log=$((current_time - last_log_update))
                
                # 只有在启动完成超过15分钟后才开始检查日志卡住
                if [ $startup_duration -gt 900 ] && [ $time_since_last_log -gt 1200 ]; then  # 启动15分钟后，20分钟无更新
                    log_warn "检测到日志卡住 (启动${startup_duration}秒后，${time_since_last_log}秒无更新)，准备重启..."
                    start_or_restart_rl_swarm true
                    break
                fi
            fi
        fi
        
        # 检查进程是否真的在运行（简化检查，移除CPU使用率检测）
        if [ "$startup_complete" = true ]; then
            # 检查进程是否在运行
            if ! pgrep -f "run_rl_swarm.sh" > /dev/null && ! pgrep -f "rgym_exp" > /dev/null; then
                log_warn "RL Swarm进程已停止，准备重启..."
                start_or_restart_rl_swarm true
                break
            fi
        fi
        
        # 继续监控
        if [ -f "/tmp/last_log_update.tmp" ]; then
            last_log_update=$(cat /tmp/last_log_update.tmp)
            current_time=$(date +%s)
            time_since_last_log=$((current_time - last_log_update))
            log_info "继续监控... (距离上次日志更新: ${time_since_last_log}秒)"
        else
            log_info "继续监控..."
        fi
        sleep 5
    done
}

# 清理临时文件
cleanup() {
    log_info "清理临时文件..."
    rm -f /tmp/rl_swarm_screen.log
    rm -f /tmp/rl_swarm_daemon.log
    rm -f /tmp/last_log_update.tmp
    cleanup_pid_file
}

# 显示帮助信息
show_help() {
    echo "RL Swarm 自动重启脚本（Screen版本）"
    echo ""
    echo "使用方法:"
    echo "  $0                    # 前台启动自动重启"
    echo "  $0 --daemon          # 后台启动自动重启（推荐）"
    echo "  $0 --help            # 显示帮助"
    echo "  $0 --status          # 显示状态"
    echo "  $0 --stop            # 停止脚本"
    echo ""
    echo "自动重启条件:"
    echo "  - 检测到游戏运行异常或程序崩溃"
    echo "  - RL Swarm进程停止运行"
    echo "  - Screen会话不存在"
    echo "  - Round进度落后对标节点超过4680"
    echo "  - 日志卡住超过20分钟无更新"
    echo ""
    echo "进程管理:"
    echo "  - 脚本使用PID文件确保只有一个实例运行"
    echo "  - 如果已有实例运行，新实例会提示停止旧实例"
    echo "  - 使用 --stop 命令可以安全停止所有相关进程"
    echo ""
    echo "Screen会话管理:"
    echo "  screen -r $SCREEN_NAME    # 连接到screen会话"
    echo "  screen -list              # 查看所有screen会话"
    echo "  screen -S $SCREEN_NAME -X quit  # 停止screen会话"
    echo ""
    echo "日志查看:"
    echo "  tail -f /tmp/rl_swarm_daemon.log  # 查看后台脚本日志"
    echo "  tail -f /tmp/rl_swarm_screen.log  # 查看screen输出日志"
}

# 显示状态
show_status() {
    echo "=== RL Swarm 状态 ==="
    
    echo "后台进程:"
    if [ -f "$PID_FILE" ]; then
        local daemon_pid=$(cat "$PID_FILE")
        if kill -0 "$daemon_pid" 2>/dev/null; then
            echo "  运行中 (PID: $daemon_pid)"
            echo "  日志文件: /tmp/rl_swarm_daemon.log"
        else
            echo "  PID文件存在但进程已停止"
        fi
    else
        echo "  未运行"
    fi
    
    echo ""
    echo "Screen会话:"
    screen -list | grep "$SCREEN_NAME" || echo "  未找到screen会话"
    
    echo ""
    echo "RL Swarm进程:"
    ps aux | grep -E "(run_rl_swarm|rgym_exp)" | grep -v grep || echo "  未找到RL Swarm进程"
    
    echo ""
    echo "备份文件:"
    ls -la /root/backup/ 2>/dev/null || echo "  备份目录不存在"
}

# 主函数
main() {
    # 解析命令行参数
    case "${1:-}" in
        --help)
            show_help
            exit 0
            ;;
        --status)
            show_status
            exit 0
            ;;
        --stop)
            log_info "停止RL Swarm..."
            # 检查是否有后台进程运行
            if [ -f "$PID_FILE" ]; then
                local daemon_pid=$(cat "$PID_FILE")
                if kill -0 "$daemon_pid" 2>/dev/null; then
                    log_info "停止后台进程 (PID: $daemon_pid)..."
                    kill "$daemon_pid"
                    sleep 2
                    # 强制杀死如果还在运行
                    if kill -0 "$daemon_pid" 2>/dev/null; then
                        log_warn "强制停止进程..."
                        kill -9 "$daemon_pid" 2>/dev/null || true
                    fi
                fi
            fi
            
            # 停止所有screen会话
            log_info "停止所有screen会话..."
            screen -ls | grep "$SCREEN_NAME" | awk '{print $1}' | while read session; do
                log_info "停止screen会话: $session"
                screen -S "$session" -X quit 2>/dev/null || true
            done
            
            # 清理PID文件
            cleanup_pid_file
            
            log_info "已停止所有相关进程"
            exit 0
            ;;
        --daemon)
            # 后台运行模式
            log_info "启动后台监控模式..."
            nohup "$0" > /tmp/rl_swarm_daemon.log 2>&1 &
            echo "后台进程已启动，PID: $!"
            echo "查看日志: tail -f /tmp/rl_swarm_daemon.log"
            echo "查看状态: $0 --status"
            exit 0
            ;;
    esac
    
    log_info "开始RL Swarm自动重启脚本（Screen版本）..."
    
    # 检查是否已有实例运行
    if ! check_existing_instance; then
        exit 1
    fi
    
    # 创建PID文件
    create_pid_file
    
    # 检查screen
    check_screen
    
    # 备份文件
    backup_auth_files
    
    # 设置screen会话
    setup_screen
    
    # 设置信号处理（仅在收到终止信号时清理）
    trap 'log_info "收到终止信号，清理后退出..."; cleanup; exit 0' SIGTERM SIGINT
    
    # 启动RL Swarm并开始监控（start_or_restart_rl_swarm会自动调用monitor_rl_swarm）
    start_or_restart_rl_swarm
}

# 运行主函数
main "$@" 