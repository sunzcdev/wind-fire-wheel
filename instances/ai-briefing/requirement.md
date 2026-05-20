# 日报系统核心模块回归测试

## 背景

日报系统（ai-briefing）三大核心模块：采集器、持久化存储、邮件发送。各自独立但有先后依赖。需要一个回归测试验证三个模块均能独立工作，不互相污染。

## 需求

写一个回归测试脚本 `tests/test_core_modules.sh`，依次验证三个核心模块：

### Step 1 — 采集模块
- 运行 `python3 src/collector/ai_briefing_collector.py daily`
- 验证返回 items 数组不为空
- 验证每个 item 有 name、url、description
- 输出项目数和来源分布

### Step 2 — 存储模块
- 用 `src/storage/ai_briefing_storage.py` 保存一条测试数据
- 用 read 命令读回来
- 验证数据一致

### Step 3 — 发送模块
- 发送一封简单测试邮件到 sunzcdev@gmail.com
- 主题带 `[核心模块回归测试]` 前缀
- 验证脚本输出 OK

### 报告
- 三步骤汇总表格
- 全部 PASS exit 0，任一 FAIL exit 1

## 约束
- 不改现有代码
- 测试数据用完自行清理（存储模块的测试数据要删掉）
- 邮件发送只发一封，不要多发
