# 核心模块回归测试 · 设计方案

## 脚本

`tests/test_core_modules.sh` — 单文件 bash 脚本，3 步串行。

## 步骤

### Step 1 — 采集
- 调 `python3 src/collector/ai_briefing_collector.py daily`
- timeout 30s，超时算 FAIL
- 解析 items 数组，验证非空 + 字段完整性
- 输出源分布（GitHub / HN / Reddit 各多少条）

### Step 2 — 存储
- 构造一条测试数据：`{"name":"回归测试","url":"https://github.com/test","stars":1}`
- `python3 src/storage/ai_briefing_storage.py save 9999-01-01 '[...]'`
- `python3 src/storage/ai_briefing_storage.py read 365` 确认读到
- 清理：删掉 daily_9999-01-01.json，从 index 移除

### Step 3 — 发送
- 简单 HTML 内容（纯文本 `回归测试通过`）
- `cat test.html | python3 src/digest/send_ai_briefing.py "[核心模块回归测试] ..."`
- 验证 OK

### 报告
PASS/FAIL 表格，exit 0/1。
