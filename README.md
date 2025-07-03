# RL Swarm 自动重启脚本使用说明

## 脚本版本

我们提供了三个版本的脚本：

1. **`simple_auto_restart.sh`** - 基础版本，直接在前台运行
2. **`screen_auto_restart.sh`** - 完整版本，包含Screen会话管理（推荐）
3. **`auto_restart_rl_swarm.sh`** - 高级版本，功能最全面

## 脚本功能

这些自动重启脚本可以：
1. 自动备份认证文件（userApiKey.json 和 userData.json）
2. 在检测到特定条件时自动重启RL Swarm
3. 自动输入必要的参数（N和模型名称）
4. 监控round进度并与网页同步
5. **Screen版本额外功能**：
   - 自动创建和管理Screen会话
   - 后台运行，支持SSH断开重连
   - 提供状态查询和停止命令

## 重启条件

脚本会在以下情况下自动重启：

1. **检测到wandb同步信息**：
   ```
   wandb: You can sync this run to the cloud by running:
   wandb: wandb sync 
   wandb: Find logs at: 
   ```

2. **Round进度落后**：
   - 检测到 "Starting round: XXXX/1000000"
   - 与 [https://dashboard.gensyn.ai/](https://dashboard.gensyn.ai/) 的最新round比较
   - 如果差距超过20，则重启

## 使用方法

### 基础版本（simple_auto_restart.sh）

#### 1. 给脚本添加执行权限
```bash
chmod +x simple_auto_restart.sh
```

#### 2. 运行脚本
```bash
./simple_auto_restart.sh
```

### Screen版本（screen_auto_restart.sh）- 推荐

#### 1. 给脚本添加执行权限
```bash
chmod +x screen_auto_restart.sh
```

#### 2. 运行脚本（自动创建Screen会话）
```bash
./screen_auto_restart.sh
```

#### 3. 查看运行状态
```bash
./screen_auto_restart.sh --status
```

#### 4. 连接到Screen会话查看详细输出
```bash
screen -r gensyn
# 按 Ctrl+A, D 分离会话
```

#### 5. 停止脚本
```bash
./screen_auto_restart.sh --stop
```

#### 6. 查看帮助
```bash
./screen_auto_restart.sh --help
```

## 脚本工作流程

### 基础版本工作流程

1. **备份阶段**：
   - 备份 `/root/rl-swarm/modal-login/temp-data/userApiKey.json`
   - 备份 `/root/rl-swarm/modal-login/temp-data/userData.json`
   - 保存到 `/root/backup/` 目录

2. **启动阶段**：
   - 进入 `/root/rl-swarm` 目录
   - 激活虚拟环境 `.venv/bin/activate`
   - 启动 `./run_rl_swarm.sh`

3. **监控阶段**：
   - 监控输出日志
   - 检测 "Waiting for modal userData.json to be created"
   - 自动恢复备份文件
   - 自动输入 "N" 和 "Gensyn/Qwen2.5-0.5B-Instruct"

4. **重启检测**：
   - 监控wandb同步信息
   - 监控round进度
   - 在满足条件时自动重启

### Screen版本工作流程

1. **初始化阶段**：
   - 检查并安装screen（如果需要）
   - 创建或连接到名为"gensyn"的Screen会话
   - 备份认证文件

2. **启动阶段**：
   - 在Screen会话中执行命令
   - 自动进入RL Swarm目录
   - 激活虚拟环境
   - 启动RL Swarm

3. **监控阶段**：
   - 在Screen会话中启动日志监控
   - 实时监控输出并检测重启条件
   - 自动处理认证文件恢复和参数输入

4. **管理阶段**：
   - 提供状态查询功能
   - 支持优雅停止
   - 自动清理残留进程

## 文件结构

```
/root/
├── rl-swarm/
│   ├── modal-login/
│   │   └── temp-data/
│   │       ├── userApiKey.json
│   │       └── userData.json
│   └── run_rl_swarm.sh
├── backup/
│   ├── userApiKey.json
│   └── userData.json
└── simple_auto_restart.sh
```

## 注意事项

1. **首次运行**：确保已经手动运行过RL Swarm并完成了认证流程
2. **网络连接**：脚本需要访问 https://dashboard.gensyn.ai/ 来获取最新round信息
3. **权限要求**：需要root权限或对相关目录的读写权限
4. **进程管理**：脚本会自动清理残留的RL Swarm进程

## 故障排除

### 如果脚本无法启动RL Swarm：
```bash
# 检查虚拟环境
ls -la /root/rl-swarm/.venv/

# 检查run_rl_swarm.sh权限
ls -la /root/rl-swarm/run_rl_swarm.sh

# 手动测试启动
cd /root/rl-swarm
source .venv/bin/activate
./run_rl_swarm.sh
```

### 如果认证文件恢复失败：
```bash
# 检查备份文件
ls -la /root/backup/

# 手动恢复
cp /root/backup/userApiKey.json /root/rl-swarm/modal-login/temp-data/
cp /root/backup/userData.json /root/rl-swarm/modal-login/temp-data/
```

### 如果无法获取网页round信息：
```bash
# 测试网络连接
curl -s "https://dashboard.gensyn.ai/"

# 检查DNS解析
nslookup dashboard.gensyn.ai
```

## 停止脚本

### 基础版本
```bash
# 如果在前台运行，按 Ctrl+C

# 或者直接杀死进程
pkill -f simple_auto_restart.sh
```

### Screen版本
```bash
# 优雅停止（推荐）
./screen_auto_restart.sh --stop

# 或者连接到screen会话手动停止
screen -r gensyn
# 然后按 Ctrl+C

# 或者直接杀死进程
pkill -f screen_auto_restart.sh
```

## 日志查看

脚本的输出会显示在控制台，包括：
- [INFO] 信息日志
- [WARN] 警告日志  
- [ERROR] 错误日志

临时日志文件：`/tmp/rl_swarm_output.log` 