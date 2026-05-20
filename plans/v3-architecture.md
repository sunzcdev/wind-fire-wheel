# 风火轮 v3 — 多 agent 协作架构方案

## 核心转变

```
v2（现在）              v3（目标）
gate-check 文件检查  →  agent 自主领活
PM 填所有坑          →  PM 只拆需求看结果
CC 靠 CLI 前台跑     →  Dev agent 后台稳定
Test 不存在          →  Test agent 可 spawn
Ops 一分钟扫一次     →  Ops daemon 7×24h
```

---

## 架构总览

```
PO ──→ [PM] ──写 task doc──→ queue/tasks/pending/
                                 ↓
                          [Dev daemon]  ← 后台循环监听
                                 ↓ 领活 → 调 claude -p → 完成
                                 ↓
queue/tasks/done/ ──→ PM 检查 → 写 test job
                                 ↓
queue/test-jobs/pending/ ──→ [Test daemon]  ← 后台循环监听
                                 ↓ 领活 → 跑测试 → 出报告
                                 ↓
queue/test-jobs/done/ ──→ PM 检查 → 交付 PO

[Ops daemon] ← 7×24h 巡逻所有实例 + agent 进程
```

每个 daemon 是一个独立的 `terminal(background)` 进程，没有 `delegate_task` 的同步阻塞问题。

---

## 1. 通信协议

基于文件系统队列，无网络依赖、无消息中间件。

```
instances/<project>/
├── tasks/                    ← Dev 任务队列
│   ├── pending/              ← PM 放这里
│   ├── in_progress/          ← Dev 移到这里
│   └── done/                 ← Dev 完成移到这里
├── test-jobs/                ← Test 任务队列
│   ├── pending/
│   ├── in_progress/
│   └── done/
└── reports/                  ← 测试报告、结果
```

### 任务文件格式

```json
{
  "task_id": "dev-20260520-001",
  "type": "dev",
  "project": "ai-briefing",
  "project_dir": "/home/sunzc/AIProjects/ai-briefing",
  "prompt": "修复采集超时问题...",
  "files": ["src/collector/ai_briefing_collector.py"],
  "acceptance": "timeout 30 内能跑完 weekly 采集",
  "created_at": "2026-05-20 20:00:00",
  "status": "pending",
  "result": {
    "exit_code": 0,
    "summary": "改了啥",
    "duration_sec": 135,
    "error": null
  }
}
```

### 状态流转

```
pending → in_progress → done   （正常）
pending → in_progress → failed  （失败，PM 决定重派或终止）
```

---

## 2. Dev daemon

### 启动方式

```bash
terminal(background=true, command="python3 template/agents/dev-daemon.py --instance instances/ai-briefing")
```

### 行为

```
loop:
  每 10 秒扫一次 tasks/pending/
  有文件 → 移到 in_progress/
    调 cc-task（terminal background 模式）
    等 notify_on_complete
    写 result 到 .task.json
    移到 tasks/done/
  无文件 → sleep 10s
```

### 关键改进 vs 当前 cc-task

| 当前问题 | v3 修复 |
|---------|---------|
| cc-task 前台跑被 SIGINT | dev daemon 自己就是 background，内部调 claude 也 background |
| exit 130 混淆"成功了还是失败了" | daemon 检查文件是否存在、diff 是否有内容，不依赖 exit code |
| CC 跑完 PM 不知道 | notify_on_complete → PM 知道活干完了 |
| 一次只能跑一个任务 | daemon 能串行排队，PM 可以放多个任务 |

---

## 3. Test daemon

### 行为

```
loop:
  每 10 秒扫一次 test-jobs/pending/
  有文件 → 移到 in_progress/
    根据 job 内容运行测试脚本（bash tests/test_xxx.sh）
    捕获输出和 exit code
    写 report 到 reports/ 和 result 到 .test.json
    移到 test-jobs/done/
  无文件 → sleep 10s
```

### 测试 job 格式

```json
{
  "job_id": "test-20260520-001",
  "project": "ai-briefing",
  "test_script": "tests/test_weekly_regression.sh",
  "timeout_sec": 60,
  "created_at": "2026-05-20 20:00:00"
}
```

### 测试 report 保存到 reports/

```json
{
  "job_id": "...",
  "passed": true,
  "steps": [
    {"name": "采集", "status": "pass", "detail": "25 个项目"},
    {"name": "渲染", "status": "pass", "detail": "无残留"},
    {"name": "发送", "status": "pass", "detail": "邮件已发送"}
  ],
  "output": "...完整 stdout...",
  "duration_sec": 28
}
```

---

## 4. Ops daemon

### 行为

```
loop:
  每 30 秒巡逻一次
  对所有 instances/ 下的项目：
    检查 Dev daemon 进程是否活着 → 不在则重启
    检查 Test daemon 进程是否活着 → 不在则重启
    检查 tasks/pending/ 中是否有超过 5 分钟无人认领的任务 → 告警
    检查 tasks/in_progress/ 中是否有超过 30 分钟未完成的任务 → 告警
    检查磁盘空间（< 10% 告警）
  报告异常（通过写 report 或通知 PM）
  sleep 30s
```

---

## 5. PM 的新工作流

### 收到需求后

```
1. 写 requirement.md → 给 PO 确认
2. 写 design.md → 给 PO 确认
3. 拆任务 → 写 .task.json → 放到 tasks/pending/
4. 回复 PO：「收到，开始了」
5. 等 notify_on_complete
6. 检查 tasks/done/ 里的 result → 正确则写 test job → 放到 test-jobs/pending/
7. 等 notify_on_complete  
8. 检查 test report → 通过则交付 PO
```

PM 不再：
- 调 cc-task
- 跑测试脚本
- 修代码 bug
- 读日志排查问题

---

## 6. 实现顺序

### P0 — 让 CC 稳定干活（今日就能修）

1. 改 cc-task 用 `terminal(background, notify_on_complete)` 而不是 foreground
2. 完成后检查文件 diff 而不是 exit code

### P1 — Dev daemon

3. 写 `template/agents/dev-daemon.py` — 监听 tasks/pending/，调 CC
4. 给 ai-briefing 实例启动 dev daemon
5. 验证：放一个 task → daemon 自动捡起来跑完

### P2 — Test daemon

6. 写 `template/agents/test-daemon.py` — 监听 test-jobs/pending/
7. 给 ai-briefing 实例启动 test daemon
8. 验证：放一个 test job → daemon 自动跑测试出报告

### P3 — Ops daemon

9. 写 `template/agents/ops-daemon.py` — 全局巡逻
10. 启动一个共享的 ops daemon（不按实例启动，全局一个）

### P4 — PM 流程适配

11. 更新 PM 工作规约，移除所有"PM 动手干活"的路径
12. 从 v2 迁移现有实例到 v3

---

## 不做的范围

- ❌ 不引入消息队列（ZeroMQ/RabbitMQ/Redis）
- ❌ 不引入 MCP 服务
- ❌ 不引入 HTTP 或其他网络协议
- ❌ 不改现有 gate-check 脚本（v2 和 v3 可以共存）
- ❌ 不做管理界面
- ❌ 不做实时状态同步（文件系统 polling 够用）

---

## 第一期实现

只做 P0 + 最小 Dev daemon，验证能跑通。

P0 的改动：改一行 cc-task —— 把 foreground 换成 background，不再依赖 exit code 判断成败。
P1 最小：一个 50 行的 Python 定时器脚本，扫目录、调 cc-task、记结果。

要开始实现第一期吗？
