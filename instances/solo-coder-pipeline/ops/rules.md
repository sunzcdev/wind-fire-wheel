# solo-coder-pipeline 运维规则

## 监控项
| 检查 | 频率 | 超时告警 | 恢复动作 | 升级 |
|------|:----:|:--------:|---------|:----:|
| daemon (main.py) | 15s | fail×2 | 重启daemon | P1 |
| Trae 进程 | 15s | fail×2 | 重启Trae | P1 |
| CDP 9229 端口 | 15s | fail×2 | 重启Trae | P1 |
| gate 推进 | 15s | 90s卡住 | 报PM | P1 |
| 磁盘 | 15s | >85% | 清理缓存 | P1 |
| DeepSeek key | 15s | fail×2 | 报PM | P2 → PO |

## 恢复流程
1. daemon 挂了 → 自动重启 → 仍挂报PM
2. gate 卡住 → 报PM判断（是否需求问题/跳过）
3. Trae 崩了 → 重启Trae → 仍崩报PM
4. CDP 端口不通 → 重启Trae → 仍不通报PM
5. 磁盘满 → 自动清理 → 仍满报PM
6. API key 过期 → 报PM换key → PM搞不定找PO

## 上报格式
[运维] 项目名: 检查名 — 问题描述
[运维] 项目名: daemon — 进程挂了，已自动重启
[运维] 项目名: gate_progress — gate 'approve' 卡了120s，已报PM
