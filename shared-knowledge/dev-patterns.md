# 风火轮共享知识库 — Dev经验

## CC 委托模式
- **用 stdin 传长 prompt**：`claude -p < /tmp/fix-prompt.txt`
- **命令行传长 prompt 会失败**（>5KB）
- **关键参数**：`--dangerously-skip-permissions --max-turns 15 --allowedTools 'Read,Edit,Write,Bash'`
- **时间设置**：简单修改 60s，多文件 120-300s，大幅重构 background
- **先验证 API key**：`curl` 测试，147ai 的 Claude key 经常过期
- **147ai 代理**：`sk-4yx*` 前缀走 Claude，`sk-CvU*` 走 Gemini（vision 任务）

## Trae CDP 操控
- **connect(port=9229)**：kill -SIGUSR1 → sleep 2 → ws 连接
- **_js(js_str, wc_idx)**：json.dumps(js, ensure_ascii=False) + awaitPromise=True，不用 String.raw/manual escape
- **inject(ws, wc_idx, text)**：先 focus → 'beforeinput' 事件插入文本 → KeyboardEvent Enter
- **_get_status(ws, wc_idx)**：查 DOM `.assistant-chat-turn-content` textContent 停长 ≥3s → 再查弹窗 → 返回 status
- **poll_until_done(ws, wc_idx, timeout)**：每 1s 查 status；文本稳定后二次验证防假阳性；超时→抛出
- **get_trajectory(ws, wc_idx, n=10)**：读 DOM `.assistant-chat-turn-content` 所有内容
- **get_session_id(ws, wc_idx)**：先 focus 窗口 → 向父元素链发 mousedown/mouseup/click → xclip 读剪贴板

## DAG 架构原则
- **节点独立**：每个 < 100 行，输入输出契约清晰
- **超过 4 个状态 → DAG**，不要线性状态机
- **状态文件加锁**：fcntl LOCK_SH 共享读锁 + LOCK_EX 写锁
- **Context 跨进程同步**：每次读前 reload() 从文件刷新，不读内存缓存
- **JSON 状态 < 2KB**，1次/秒轮询无损
- **daemon while loop > cron**：event-driven，不用 cron 做系统自动化

## 任务类型贯穿链
- **三种类型**：`0-1代码生成`（全新）、`Feature迭代`（增量）、`Bug修复`（定点修）
- **必须在 main.py start uid task_type 入口指定**，穿透到所有节点
- **design.py 用占位符 `__TASK_TYPE__` 运行时替换**，不能硬编码
- **context.metadata.task_type 是唯一来源**，每个节点从这读
- **症状 vs 根因**：文件不匹配是症状，task_type 没贯穿才是根因

## Bitable 提交
- **直接 lark-cli API PUT**，不走 bitable-submit.py 脚本
- **先查同 UID 的已有记录**（`+record-list`），匹配成功则 PUT 更新
- **失败 fallback 到本地保存**
- **必须 clean_env 去掉代理变量**
- **本地保存不算成功**，只有线上 Bitable 能查到才算
- **凭证**：`LARK_CLI_NO_PROXY=1` 绕过代理
- **lark-cli 路径**：`~/.hermes/node/bin/lark-cli`

## 项目结构规范
- **脚本 < 200 行 → 可以**
- **第 3 个 workaround → 抽项目**
- **先 DESIGN.md 再代码**
- **第一天就用 CC + sp + 12 规约**
- **三个目录分离**：pipeline/（核心代码）、scripts/（可执行脚本）、archive/（历史实验）
