# RL Swarm 自动重启脚本

## 简介

`screen_auto_restart.sh` 是一个用于自动监控和重启 RL Swarm 的脚本，使用 Screen 会话管理，支持后台运行和 SSH 断开重连。脚本采用循环监控设计，确保 RL Swarm 持续稳定运行。

## 功能特性

- ✅ **自动备份和恢复认证文件**：启动前自动备份，重启时自动恢复
- ✅ **Screen 会话管理**：支持 SSH 断开重连，会话持久化
- ✅ **智能重启机制**：删除旧会话，创建新会话，避免状态污染
- ✅ **循环监控设计**：启动→监控→重启→监控的完整循环
- ✅ **自动交互处理**：自动处理认证和模型选择交互
- ✅ **对标节点监控**：与特定节点比较进度，防止落后
- ✅ **后台运行模式**：支持 daemon 模式，PID 文件管理
- ✅ **状态查询和优雅停止**：完整的进程管理功能

## 快速开始

### 1. 给脚本添加执行权限
```bash
chmod +x screen_auto_restart.sh
```

### 2. 后台运行（推荐）
```bash
./screen_auto_restart.sh --daemon
```

### 3. 查看运行状态
```bash
./screen_auto_restart.sh --status
```

### 4. 连接到 Screen 会话查看详细输出
```bash
screen -r gensyn
# 按 Ctrl+A, D 分离会话
```

## 使用方法

### 后台运行（推荐）
```bash
./screen_auto_restart.sh --daemon
首次使用需要手动将两个登录文件备份至对应文件夹
```
- 在后台启动监控
- 支持 SSH 断开重连
- 日志保存在 `/tmp/rl_swarm_daemon.log`
- 使用 PID 文件确保只有一个实例运行

### 前台运行
```bash
./screen_auto_restart.sh
```
- 在前台运行，可以看到实时输出
- 按 Ctrl+C 停止

### 查看状态
```bash
./screen_auto_restart.sh --status
```
- 显示后台进程状态和 PID
- 显示 Screen 会话状态
- 显示 RL Swarm 进程状态
- 显示备份文件状态

### 停止脚本
```bash
./screen_auto_restart.sh --stop
```
- 停止后台监控进程
- 停止所有 Screen 会话
- 清理 PID 文件

### 查看帮助
```bash
./screen_auto_restart.sh --help
```

## 日志查看

### 后台脚本日志
```bash
tail -f /tmp/rl_swarm_daemon.log
```

### Screen 输出日志
```bash
tail -f /tmp/rl_swarm_screen.log
```

## 监控和重启逻辑

### 循环设计
脚本采用循环监控设计：
```
启动 → 监控 → 检测问题 → 重启 → 监控 → ...
```

### 重启条件

脚本会在以下情况下自动重启 RL Swarm：

1. **游戏运行异常**
   - 检测到 `ERROR: Exception occurred during game run.`
   - 检测到 `Traceback (most recent call last):`
   - 等待 20 秒后重启（便于调试）

2. **程序异常退出**
   - 检测到 `Terminated`、`Killed`、`Aborted`、`Segmentation fault`
   - 等待 10 秒后重启

3. **Round 进度落后**
   - 与对标节点 `untamed alert rhino` 比较
   - 计算差距：当前 round - 对标节点 score
   - 如果差距 < 4680，则重启
   - 使用 API：`https://dashboard.gensyn.ai/api/v1/peer?name=untamed%20alert%20rhino`

4. **进程停止**
   - 检测到 RL Swarm 进程停止
   - 自动重启

5. **Screen 会话丢失**
   - 检测到 Screen 会话不存在
   - 自动重启

### 智能重启机制

重启时采用完全清理策略：
1. **删除所有旧 Screen 会话**：避免状态污染
2. **恢复认证文件**：确保认证正常
3. **创建新 Screen 会话**：全新环境
4. **启动 RL Swarm**：在新的干净环境中运行
5. **重新开始监控**：形成完整循环

### 自动交互处理

脚本自动处理以下交互：
- **认证文件恢复**：检测到 "Waiting for modal userData.json" 时自动恢复
- **Hugging Face Hub 推送**：检测到推送提示时自动输入 "N"
- **模型选择**：自动输入 "Gensyn/Qwen2.5-0.5B-Instruct"

## Screen 会话管理

### 连接到会话
```bash
screen -r gensyn
```

### 查看所有会话
```bash
screen -list
```

### 分离会话
在 Screen 会话中按 `Ctrl+A, D`

### 停止会话
```bash
screen -S gensyn -X quit
```

## 进程管理

### PID 文件机制
- 使用 `/tmp/rl_swarm_daemon.pid` 跟踪运行实例
- 防止多个实例同时运行
- 启动前检查现有实例

### 进程检查
```bash
# 检查后台进程
ps -p $(cat /tmp/rl_swarm_daemon.pid)

# 检查 RL Swarm 进程
ps aux | grep -E "(run_rl_swarm|rgym_exp)" | grep -v grep
```

## 文件结构

```
/root/
├── rl-swarm/
│   ├── modal-login/temp-data/
│   │   ├── userApiKey.json
│   │   └── userData.json
│   └── run_rl_swarm.sh
├── backup/
│   ├── userApiKey.json
│   └── userData.json
├── screen_auto_restart.sh
└── /tmp/
    ├── rl_swarm_daemon.pid
    ├── rl_swarm_daemon.log
    └── rl_swarm_screen.log
```

## 注意事项

1. **首次运行**：确保已经手动运行过 RL Swarm 并完成了认证流程
2. **网络连接**：脚本需要访问 API 来获取对标节点信息
3. **权限要求**：需要 root 权限或对相关目录的读写权限
4. **Screen 安装**：脚本会自动检查并安装 screen（如果需要）
5. **单一实例**：确保同时只有一个监控实例运行

## 故障排除

### 如果脚本无法启动
```bash
# 检查虚拟环境
ls -la /root/rl-swarm/.venv/

# 检查脚本权限
ls -la /root/rl-swarm/run_rl_swarm.sh

# 检查 PID 文件
cat /tmp/rl_swarm_daemon.pid

# 手动测试启动
cd /root/rl-swarm
source .venv/bin/activate
./run_rl_swarm.sh
```

### 如果认证文件恢复失败
```bash
# 检查备份文件
ls -la /root/backup/

# 手动恢复
cp /root/backup/userApiKey.json /root/rl-swarm/modal-login/temp-data/
cp /root/backup/userData.json /root/rl-swarm/modal-login/temp-data/
```

### 如果无法获取对标节点信息，超时15s
```bash
可能是服务器处于国内，或者俄罗斯UA、白俄罗BY、乌克兰UA斯等地区，
# 检查网络连接
ping dashboard.gensyn.ai
```

### 如果有多个 Screen 会话
```bash
# 查看所有会话
screen -list

# 清理重复会话
screen -ls | grep gensyn | awk '{print $1}' | xargs -I {} screen -S {} -X quit
```

### 如果监控循环中断
```bash
# 检查日志
tail -50 /tmp/rl_swarm_daemon.log

# 重新启动
./screen_auto_restart.sh --stop
./screen_auto_restart.sh --daemon
```
### 问题一：
```bash
[INFO] 创建PID文件: /tmp/rl_swarm_daemon.pid (PID: 72215)
[INFO] 备份认证文件...
mkdir: cannot create directory ‘/backup’: Permission denied
将路径中的/root替换成用户目录下的$HOME
例如：/root/backup变为$HOME/backup
```

## 版本信息

- **脚本版本**: screen_auto_restart.sh v2.0
- **支持系统**: Linux (Ubuntu/Debian)
- **依赖**: screen, curl, bash
- **RL Swarm 版本**: 兼容 v0.1.1+
- **监控特性**: 循环监控、智能重启、对标节点比较 
