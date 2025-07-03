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
    
    # 检查screen会话是否存在
    if screen -list | grep -q "$SCREEN_NAME"; then
        log_info "Screen会话 $SCREEN_NAME 已存在"
        
        # 检查会话是否已分离
        if screen -list | grep -q "$SCREEN_NAME.*Detached"; then
            log_info "连接到现有的分离会话"
            screen -r "$SCREEN_NAME"
        else
            log_info "Screen会话正在运行，创建新会话"
            screen -dmS "${SCREEN_NAME}_$(date +%s)" bash -c "cd /root && exec bash"
        fi
    else
        log_info "创建新的Screen会话: $SCREEN_NAME"
        screen -dmS "$SCREEN_NAME" bash -c "cd /root && exec bash"
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

# 在screen中启动RL Swarm
start_rl_swarm_in_screen() {
    log_info "在Screen会话中启动RL Swarm..."
    
    # 发送命令到screen会话
    screen -S "$SCREEN_NAME" -X stuff "cd /root/rl-swarm$(printf '\r')"
    sleep 1
    
    screen -S "$SCREEN_NAME" -X stuff "source .venv/bin/activate$(printf '\r')"
    sleep 1
    
    # 启动RL Swarm
    screen -S "$SCREEN_NAME" -X stuff "./run_rl_swarm.sh$(printf '\r')"
    
    log_info "RL Swarm已在Screen会话中启动"
    log_info "使用 'screen -r $SCREEN_NAME' 查看运行状态"
}

# 监控RL Swarm输出
monitor_rl_swarm() {
    log_info "开始监控RL Swarm输出..."
    
    while true; do
        # 创建临时日志文件来捕获screen输出
        LOG_FILE="/tmp/rl_swarm_screen.log"
        
        # 启动screen日志捕获
        screen -S "$SCREEN_NAME" -X logfile "$LOG_FILE"
        screen -S "$SCREEN_NAME" -X log on
        
        sleep 5
        
        # 初始化状态变量
        startup_complete=false
        startup_start_time=$(date +%s)
        
        # 监控screen日志文件（添加错误处理）
        tail -f "$LOG_FILE" 2>/dev/null | while read line; do
                            # 检查启动超时（只在启动阶段检查，启动完成后不检查）
                if [ "$startup_complete" = false ]; then
                    current_time=$(date +%s)
                    startup_duration=$((current_time - startup_start_time))
                    
                    # 如果启动超过10分钟还没有完成，则重启
                    if [ $startup_duration -gt 600 ]; then
                        log_warn "启动超时（超过10分钟未完成），准备重启..."
                        restart_rl_swarm
                        break  # 跳出当前tail -f循环，重新开始监控
                    fi
                fi
            
            # 过滤掉screen的控制字符
            clean_line=$(echo "$line" | sed 's/\x1b\[[0-9;]*m//g' | sed 's/\r//g')
            
            if [ -n "$clean_line" ]; then
                echo "$clean_line"
                
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
                
                # 检测到等待userData.json时恢复文件
                if echo "$clean_line" | grep -q "Waiting for modal userData.json to be created"; then
                    log_info "检测到等待userData.json，恢复备份文件..."
                    restore_auth_files
                    
                    # 发送N和模型名称到screen会话
                    sleep 3
                    screen -S "$SCREEN_NAME" -X stuff "N$(printf '\r')"
                    sleep 2
                    screen -S "$SCREEN_NAME" -X stuff "Gensyn/Qwen2.5-0.5B-Instruct$(printf '\r')"
                fi
                
                # 检测异常错误（只在启动完成后检测）
                if [ "$startup_complete" = true ] && echo "$clean_line" | grep -E "(ERROR: Exception occurred during game run\.|Traceback \(most recent call last\):)"; then
                    log_warn "检测到游戏运行异常，等待20秒后重启（便于调试）..."
                    sleep 20
                    restart_rl_swarm
                    break  # 跳出当前tail -f循环，重新开始监控
                fi
                
                # 检测程序异常退出（只在启动完成后检测）
                if [ "$startup_complete" = true ] && echo "$clean_line" | grep -E "(Terminated|Killed|Aborted|Segmentation fault)"; then
                    log_warn "检测到程序异常退出，等待10秒后重启..."
                    sleep 10
                    restart_rl_swarm
                    break  # 跳出当前tail -f循环，重新开始监控
                fi
                
                # 检测round信息并比较（每次检测到新的round都进行比较）
                if echo "$clean_line" | grep -q "Starting round:"; then
                    current_round=$(echo "$clean_line" | grep -o "Starting round: [0-9]*" | grep -o "[0-9]*")
                    
                    if [ -n "$current_round" ] && [ "$current_round" -gt 0 ]; then
                        log_debug "检测到round: $current_round"
                        
                        # 尝试从网页获取最新round（设置超时避免阻塞）
                        latest_round=$(timeout 10 curl -s "https://dashboard.gensyn.ai/" 2>/dev/null | grep -o 'round[^0-9]*[0-9]*' | grep -o '[0-9]*' | tail -1)
                        
                        if [ -n "$latest_round" ] && [ "$latest_round" -gt 0 ]; then
                            diff=$((latest_round - current_round))
                            log_debug "Round比较: 当前=$current_round, 最新=$latest_round, 差距=$diff"
                            
                            if [ $diff -gt 20 ]; then
                                log_warn "检测到round差距过大 (当前: $current_round, 最新: $latest_round, 差距: $diff)，准备重启..."
                                sleep 5
                                restart_rl_swarm
                                break  # 跳出当前tail -f循环，重新开始监控
                            fi
                        else
                            log_debug "无法从网页获取最新round信息"
                        fi
                    fi
                fi
            fi
        done
        
        # 检查RL Swarm进程是否还在运行
        if ! pgrep -f "run_rl_swarm.sh" > /dev/null; then
            log_warn "RL Swarm进程已停止，准备重启..."
            restart_rl_swarm
            sleep 5
        fi
        
        # 无论什么原因，都继续监控
        log_info "继续监控..."
        sleep 5
    done
}

# 重启RL Swarm
restart_rl_swarm() {
    log_info "重启RL Swarm..."
    
    # 发送Ctrl+C停止当前进程
    screen -S "$SCREEN_NAME" -X stuff "$(printf '\003')"
    sleep 3
    
    # 在现有screen会话中重新启动RL Swarm
    log_info "在现有screen会话中重新启动RL Swarm..."
    screen -S "$SCREEN_NAME" -X stuff "cd /root/rl-swarm$(printf '\r')"
    sleep 1
    screen -S "$SCREEN_NAME" -X stuff "source .venv/bin/activate$(printf '\r')"
    sleep 1
    screen -S "$SCREEN_NAME" -X stuff "./run_rl_swarm.sh$(printf '\r')"
    
    log_info "RL Swarm已在现有screen会话中重新启动"
}

# 清理临时文件
cleanup() {
    log_info "清理临时文件..."
    rm -f /tmp/rl_swarm_screen.log
    rm -f /tmp/rl_swarm_daemon.log
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
            # 发送Ctrl+C到screen会话
            screen -S "$SCREEN_NAME" -X stuff "$(printf '\003')"
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
    
    # 检查screen
    check_screen
    
    # 备份文件
    backup_auth_files
    
    # 设置screen会话
    setup_screen
    
    # 设置信号处理（仅在收到终止信号时清理）
    trap 'log_info "收到终止信号，清理后退出..."; cleanup; exit 0' SIGTERM SIGINT
    
    # 启动RL Swarm
    start_rl_swarm_in_screen
    
    # 开始监控
    monitor_rl_swarm
}

# 运行主函数
main "$@" 