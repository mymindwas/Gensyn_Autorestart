# RL Swarm 自动重启脚本（Screen版本）

这是一个用于自动管理RL Swarm进程的bash脚本，使用Screen会话确保进程在SSH断开后继续运行，并具备自动重启功能。

## 功能特性

- **自动备份和恢复认证文件** - 备份`userApiKey.json`和`userData.json`，重启时自动恢复
- **Screen会话管理** - 在名为"gensyn"的Screen会话中运行RL Swarm
- **自动交互处理** - 自动响应启动过程中的交互式提示
- **智能错误检测** - 检测各种错误情况并自动重启
- **Peer ID记录** - 自动检测并记录运行中的Peer ID
- **Score监控** - 每4小时检查一次score变化，无变化时自动重启
- **进程健康检查** - 监控RL Swarm进程和Screen会话状态
- **Daemon模式支持** - 支持后台运行，提供状态查询和停止命令

## 快速开始

### 1. 前台启动（测试用）
```bash
./screen_auto_restart.sh
```

### 2. 后台启动（推荐先关掉残留进程）
```bash
./screen_auto_restart.sh --stop
pkill -f screen_auto_restart
./screen_auto_restart.sh --daemon
```

### 3. 查看状态
```bash
./screen_auto_restart.sh --status
```

### 4. 停止脚本
```bash
./screen_auto_restart.sh --stop
```

## 自动重启条件

脚本会在以下情况下自动重启RL Swarm：

1. **错误检测**：
   - `ERROR: Exception occurred during game run.`
   - `Traceback (most recent call last):`
   - `Terminated`, `Killed`, `Aborted`, `Segmentation fault`
   - `ConnectionError`, `TimeoutError`, `Connection refused`, `Connection reset`
   - `stuck`, `hung`, `frozen`, `not responding`

2. **进程健康检查**：
   - RL Swarm进程停止运行
   - Screen会话不存在

3. **Score监控**：
   - 检测到Peer ID并记录到`/tmp/rl_swarm_peer_id.txt`
   - 每4小时检查一次score变化（通过API：`https://dashboard.gensyn.ai/api/v1/peer?id=<peer_id>`）
   - 如果4小时内score无变化，自动重启

4. **日志监控**：
   - 启动完成后15分钟内不检查日志卡住
   - 15分钟后，如果20分钟无日志更新，自动重启

## 监控和重启逻辑

### 启动阶段保护
- 启动完成后10分钟内不检查长时间无输出
- 启动完成后15分钟内不检查日志卡住
- 避免在启动阶段误判程序卡住

### 交互式提示处理
脚本自动处理以下交互式提示：
1. `Waiting for modal userData.json to be created` → 恢复备份文件，发送"N"和模型名称
2. `Would you like to push models...` → 发送"N"
3. `Enter the model name...` → 发送"Gensyn/Qwen2.5-0.5B-Instruct"

### Score变化检测
- 从日志中提取Peer ID：`Peer ID [Qmb14s2Es99SDQ6Fh6kkZkM6359raDgBLdjcYoSk3nxxv7] is already registered!`
- 使用API查询当前score：`https://dashboard.gensyn.ai/api/v1/peer?id=<peer_id>`
- 每4小时（14400秒）检查一次
- 记录到临时文件：
  - `/tmp/rl_swarm_peer_id.txt` - 当前Peer ID
  - `/tmp/rl_swarm_last_score.txt` - 上次记录的score
  - `/tmp/rl_swarm_last_score_check.txt` - 上次检查时间

## 文件结构

### 临时文件
- `/tmp/rl_swarm_screen.log` - Screen会话输出日志
- `/tmp/rl_swarm_daemon.log` - 脚本运行日志
- `/tmp/rl_swarm_peer_id.txt` - 当前Peer ID
- `/tmp/rl_swarm_last_score.txt` - 上次记录的score
- `/tmp/rl_swarm_last_score_check.txt` - 上次检查时间
- `/tmp/rl_swarm_daemon.pid` - 脚本PID文件

### 备份文件
- `/root/backup/userApiKey.json` - 备份的API密钥
- `/root/backup/userData.json` - 备份的用户数据

## 使用方法

### 连接到Screen会话
```bash
screen -r gensyn
```

### 查看所有Screen会话
```bash
screen -list
```

### 查看脚本日志
```bash
# 查看后台脚本日志
tail -f /tmp/rl_swarm_daemon.log

# 查看Screen输出日志
tail -f /tmp/rl_swarm_screen.log
```

### 停止Screen会话
```bash
screen -S gensyn -X quit
```

## 故障排除

### 常见问题

1. **脚本无法启动**
   - 检查是否有其他实例运行：`./screen_auto_restart.sh --status`
   - 停止旧实例：`./screen_auto_restart.sh --stop`

2. **Screen会话问题**
   - 检查screen是否安装：`which screen`
   - 查看会话状态：`screen -list`

3. **认证文件问题**
   - 检查备份文件：`ls -la /root/backup/`
   - 手动恢复：`cp /root/backup/* /root/rl-swarm/modal-login/temp-data/`

4. **进程监控问题**
   - 检查进程状态：`ps aux | grep -E "(run_rl_swarm|rgym_exp)"`
   - 检查PID文件：`cat /tmp/rl_swarm_daemon.pid`

### 日志分析
- 查看错误模式：`grep -E "(ERROR|Exception|Traceback)" /tmp/rl_swarm_screen.log`
- 查看重启记录：`grep "准备重启" /tmp/rl_swarm_daemon.log`
- 查看score检查：`grep "score" /tmp/rl_swarm_daemon.log`

## 注意事项

1. **权限要求**：脚本需要root权限来管理进程和文件
2. **网络依赖**：需要网络连接来查询Gensyn API
3. **磁盘空间**：确保有足够空间存储日志和备份文件
4. **系统兼容性**：适用于Ubuntu/Debian系统，需要bash和screen

## 更新日志

- **v1.0**: 基础自动重启功能
- **v1.1**: 添加Screen会话管理
- **v1.2**: 改进错误检测和启动保护
- **v1.3**: 添加Peer ID记录和Score监控
- **v1.4**: 优化交互式提示处理和监控逻辑
