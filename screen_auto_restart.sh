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
    sleep 2
    
    screen -S "$SCREEN_NAME" -X stuff "source .venv/bin/activate$(printf '\r')"
    sleep 2
    
    # 启动RL Swarm
    screen -S "$SCREEN_NAME" -X stuff "./run_rl_swarm.sh$(printf '\r')"
    
    log_info "RL Swarm已在Screen会话中启动"
    log_info "使用 'screen -r $SCREEN_NAME' 查看运行状态"
}

# 监控RL Swarm输出
monitor_rl_swarm() {
    log_info "开始监控RL Swarm输出..."
    
    # 创建临时日志文件
    LOG_FILE="/tmp/rl_swarm_monitor.log"
    
    # 在screen中启动监控
    screen -S "$SCREEN_NAME" -X stuff "tail -f /root/rl-swarm/logs/*.log 2>/dev/null | tee $LOG_FILE$(printf '\r')"
    sleep 5
    
    # 监控日志文件
    tail -f "$LOG_FILE" | while read line; do
        echo "$line"
        
        # 检测到等待userData.json时恢复文件
        if echo "$line" | grep -q "Waiting for modal userData.json to be created"; then
            log_info "检测到等待userData.json，恢复备份文件..."
            restore_auth_files
            
            # 发送N和模型名称到screen会话
            sleep 3
            screen -S "$SCREEN_NAME" -X stuff "N$(printf '\r')"
            sleep 2
            screen -S "$SCREEN_NAME" -X stuff "Gensyn/Qwen2.5-0.5B-Instruct$(printf '\r')"
        fi
        
        # 检测wandb同步信息
        if echo "$line" | grep -q "wandb: You can sync this run to the cloud by running:"; then
            log_warn "检测到wandb同步信息，准备重启..."
            sleep 3
            screen -S "$SCREEN_NAME" -X stuff "$(printf '\r')"
            sleep 5
            restart_rl_swarm
            break
        fi
        
        # 检测round信息并比较
        if echo "$line" | grep -q "Starting round:"; then
            current_round=$(echo "$line" | grep -o "Starting round: [0-9]*" | grep -o "[0-9]*")
            
            if [ -n "$current_round" ] && [ "$current_round" -gt 0 ]; then
                # 尝试从网页获取最新round
                latest_round=$(curl -s "https://dashboard.gensyn.ai/" 2>/dev/null | grep -o 'round[^0-9]*[0-9]*' | grep -o '[0-9]*' | tail -1)
                
                if [ -n "$latest_round" ] && [ "$latest_round" -gt 0 ]; then
                    diff=$((latest_round - current_round))
                    if [ $diff -gt 20 ]; then
                        log_warn "检测到round差距过大 (当前: $current_round, 最新: $latest_round, 差距: $diff)，准备重启..."
                        sleep 5
                        restart_rl_swarm
                        break
                    fi
                fi
            fi
        fi
    done
}

# 重启RL Swarm
restart_rl_swarm() {
    log_info "重启RL Swarm..."
    
    # 停止当前进程
    screen -S "$SCREEN_NAME" -X stuff "$(printf '\003')"  # Ctrl+C
    sleep 3
    
    # 清理进程
    pkill -f "run_rl_swarm.sh" 2>/dev/null || true
    pkill -f "python.*rgym_exp" 2>/dev/null || true
    
    sleep 2
    
    # 重新启动
    start_rl_swarm_in_screen
}

# 清理进程
cleanup() {
    log_info "清理进程..."
    pkill -f "run_rl_swarm.sh" 2>/dev/null || true
    pkill -f "python.*rgym_exp" 2>/dev/null || true
    rm -f /tmp/rl_swarm_monitor.log
}

# 显示帮助信息
show_help() {
    echo "RL Swarm 自动重启脚本（Screen版本）"
    echo ""
    echo "使用方法:"
    echo "  $0                    # 启动自动重启"
    echo "  $0 --help            # 显示帮助"
    echo "  $0 --status          # 显示状态"
    echo "  $0 --stop            # 停止脚本"
    echo ""
    echo "Screen会话管理:"
    echo "  screen -r $SCREEN_NAME    # 连接到screen会话"
    echo "  screen -list              # 查看所有screen会话"
    echo "  screen -S $SCREEN_NAME -X quit  # 停止screen会话"
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
            screen -S "$SCREEN_NAME" -X stuff "$(printf '\003')" 2>/dev/null || true
            pkill -f "run_rl_swarm.sh" 2>/dev/null || true
            pkill -f "python.*rgym_exp" 2>/dev/null || true
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
    
    # 设置信号处理
    trap cleanup EXIT
    
    # 启动RL Swarm
    start_rl_swarm_in_screen
    
    # 开始监控
    monitor_rl_swarm
}

# 运行主函数
main "$@" 