# 无敌风火轮 — 实例：AI 新玩意简报系统

## 项目概述
常规化信息采集简报流水线。代码采集→LLM润色→Apple HTML→SMTP推送。
核心原则：代码干体力活，LLM只做润色。只发周报(周一)和月报(1号)。

## 运行中资源
- 脚本目录：`~/.hermes/scripts/`
- 数据目录：`~/.hermes/data/ai_briefing/`
- 采集脚本：`ai_briefing_collector.py`
- 持久化脚本：`ai_briefing_storage.py`
- 邮件发送：`send_ai_briefing.py`
- 邮件模板：`ai_digest_template.html`
- SKILL：`ai-briefing`（主流程）、`ai-briefing-internalization`（二次内化需求）

## 定时任务
- Cron job ID：`92f36b8cdd2d`（AI新玩意-主任务）
- 时间：每天 7:00
- 模式：1号→月报 / 周一(非1号)→周报 / 其他→跳过

## 邮件
- 发件：`james.sun@qq.com`（QQ SMTP）
- 收件：`sunzcdev@gmail.com`
- 抄送反馈：用户回复邮件到收件箱，通过 IMAP 采集

## 二次内化（需求中）
用户在简报中标记感兴趣的项目后，自动：
1. 采集 — 从邮件/微信/飞书提取标记
2. 分析 — 对用户有什么好处 + 对 Hermes 有什么好处
3. 存档 — 写入 internalized.json + interest_graph.json
4. 运用 — 周报/月报精选时参考用户兴趣权重

## 当前 Gate 状态
- Gate 1 需求解析：done — 现有简报已稳定运行
- Gate 2 方案生成：done — 架构和流程已确定
- Gate 3 实现：active — 二次内化功能待实现
- Gate 4 验证：idle
- Gate 5 交付判定：idle

## 成员
| 角色 | 身份 |
|------|------|
| PO | 孙振朝 |
| PM | Hermes |
| Dev | Hermes |
| Test | Hermes |
| Ops | Cron Job |

## 已知故障模式
- cron agent 假装运行命令但不实际执行 terminal → prompt 中要加粗强调"必须实际运行"
- collector.py 超时（GitHub API 限流/网络抖动）→ 后备用 web_extract 抓 github trending 静态页
- 用户反馈未自动处理 → 二次内化实现后解决
