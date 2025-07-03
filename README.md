# RL Swarm 自动重启脚本

## 简介

`screen_auto_restart.sh` 是一个用于自动监控和重启 RL Swarm 的脚本，使用 Screen 会话管理，支持后台运行和 SSH 断开重连。

## 功能特性

- ✅ 自动备份和恢复认证文件
- ✅ 在 Screen 会话中运行，支持 SSH 断开重连
- ✅ 自动检测错误并重启
- ✅ 监控 round 进度并与网页同步
- ✅ 自动输入必要的参数
- ✅ 后台运行模式
- ✅ 状态查询和优雅停止

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
```
- 在后台启动监控
- 支持 SSH 断开重连
- 日志保存在 `/tmp/rl_swarm_daemon.log`

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
- 显示 Screen 会话状态
- 显示 RL Swarm 进程状态
- 显示备份文件状态

### 停止脚本
```bash
./screen_auto_restart.sh --stop
```
- 优雅停止 RL Swarm
- 发送 Ctrl+C 到 Screen 会话

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

## 重启条件

脚本会在以下情况下自动重启 RL Swarm：

1. **游戏运行异常**
   - 检测到 `ERROR: Exception occurred during game run.`
   - 检测到 `Traceback (most recent call last):`
   - 等待 20 秒后重启（便于调试）

2. **程序异常退出**
   - 检测到 `Terminated`、`Killed`、`Aborted`、`Segmentation fault`
   - 等待 10 秒后重启

3. **Round 进度落后**
   - 检测到 round 差距超过 20
   - 与 [dashboard.gensyn.ai](https://dashboard.gensyn.ai/) 同步比较

4. **启动超时**
   - 启动超过 10 分钟未完成
   - 自动重启

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
└── screen_auto_restart.sh
```

## 注意事项

1. **首次运行**：确保已经手动运行过 RL Swarm 并完成了认证流程
2. **网络连接**：脚本需要访问 dashboard.gensyn.ai 来获取最新 round 信息
3. **权限要求**：需要 root 权限或对相关目录的读写权限
4. **Screen 安装**：脚本会自动检查并安装 screen（如果需要）

## 故障排除

### 如果脚本无法启动
```bash
# 检查虚拟环境
ls -la /root/rl-swarm/.venv/

# 检查脚本权限
ls -la /root/rl-swarm/run_rl_swarm.sh

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

### 如果无法获取网页 round 信息
```bash
# 测试网络连接
curl -s "https://dashboard.gensyn.ai/"

# 检查 DNS 解析
nslookup dashboard.gensyn.ai
```

## 版本信息

- **脚本版本**: screen_auto_restart.sh
- **支持系统**: Linux (Ubuntu/Debian)
- **依赖**: screen, curl, bash
- **RL Swarm 版本**: 兼容 v0.1.1+ 