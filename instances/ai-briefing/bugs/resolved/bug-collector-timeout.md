# Bug Report — 周报回归测试

**测试时间:** 2026-05-20
**测试用例:** test_weekly_regression.sh Step 1 — 采集
**缺陷类型:** 性能

## 描述

回归测试 Step 1 调用 `collect_weekly()` 超时（> 60s），无法完成采集。

## 重现

```bash
timeout 45 python3 src/collector/ai_briefing_collector.py weekly
# → 超时，无输出
```

## 根因分析

`collect_weekly()` 依次调用多个 API（GitHub × 2、Hacker News、Reddit × 2、TopHub），每个之间 `time.sleep(1.5)`。网络走 socks5 代理（`ALL_PROXY=socks5://127.0.0.1:1081`），加上 API 响应慢，总耗时超过 60s。

## 修复方向

1. 给所有 `urlopen` 调用加超时参数（已有 10-12s，但可收紧）
2. 减少 API 调用间的 `_delay()` 等待
3. 或增加 collector 的超时容忍度，让调用方能等更久
