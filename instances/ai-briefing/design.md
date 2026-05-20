# 周报回归测试 · 设计方案

## 整体思路

对现有 ai-briefing 的周报链路做一次回归测试，验证采集→模板→发送全流程正常。**不修改现有代码，不新增依赖**，只加一个可独立运行的测试脚本。

## 脚本结构

```
ai-briefing/tests/test_weekly_regression.sh
```

单文件 shell 脚本，串行执行 4 个测试步骤，每步输出 PASS/FAIL，最后返回 exit code。

---

## 测试步骤

### Step 1 — 采集测试

```
Collect data → count items → each item must have name + url
```

- 跑 `collect_weekly()` 模式（不写死 mock，用真实 GitHub API 抓，跟周报一样的采集入口）
- 验证返回的项目数 ≥ 1
- 验证每个项目有 name、url、description 字段
- 输出抽取的项目数、来源分布

### Step 2 — HTML 模板渲染

```
Read template → render with data → check no leftover placeholders
```

- 读 `src/digest/ai_digest_template.html`
- 调用现有 LLM 润色流程（或直接拿一份已精选的数据填充占位符）
- 验证填充后内容中不含 `##PLACEHOLDER##` 或 `##???##` 残留

> 设计说明：Step 2 需要一份精选后的数据。最简单的做法是从 Step 1 的采集结果中取 top K 条，直接按模板格式填入卡片。如果 LLM 润色流程可用则走 LLM，不可用则取原始数据按固定格式排版。两种路径都算 PASS。

### Step 3 — 邮件发送

```
Send email via existing send script → verify no errors
```

- 将 Step 2 生成的 HTML 传给 `src/digest/send_ai_briefing.py`
- 收件人：sunzcdev@gmail.com
- 主题：`[回归测试] AI新玩意 周报测试 {日期}`
- 验证脚本输出 "OK"（无报错）

### Step 4 — 结果报告

```
Print summary table
```

输出格式：
```
=== 周报回归测试报告 ===
日期: 2026-05-20
采集: ✅ 15 个项目 (GitHub 8 + Hacker News 5 + Reddit 2)
渲染: ✅ 模板无残留占位符
发送: ✅ 邮件已发送至 sunzcdev@gmail.com
主题: [回归测试] AI新玩意 周报测试 2026-05-20
========================
结果: ✅ 全部通过 (exit 0)
```

---

## 不做的范围

- ❌ 不改现有 collector/digest/storage 代码
- ❌ 不改 cron 定时任务
- ❌ 不验证邮件是否真实到达（依赖邮箱本身的送达，非脚本能测）
- ❌ 不发真实的完整周报（只用测试数据跑链路）

## 验收标准

1. `bash tests/test_weekly_regression.sh` 跑完 exit code 0
2. 每步输出 PASS/FAIL（红色或绿色标记）
3. 邮箱 sunzcdev@gmail.com 收到测试邮件
4. 不影响现有系统中任何文件的状态

## 实现优先级

| 优先级 | 内容 | 说明 |
|--------|------|------|
| P0 | Step 1 采集 | 直接复用 collector 的 collect_weekly |
| P0 | Step 3 发送 | 直接复用 send_ai_briefing.py |
| P0 | Step 4 报告 | printf 输出表格 |
| P1 | Step 2 渲染 | 模板填充逻辑需要处理占位符替换 |
