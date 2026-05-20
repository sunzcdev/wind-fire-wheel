# ai-briefing 运维规则

## 项目特点
cron 驱动，非 daemon。间隔 5 分钟检查一次即可。

## 监控项
| 检查 | 频率 | 超时 | 恢复 |
|------|:----:|:----:|------|
| 上次采集是否成功 | 5min | 24h | 报PM |
| 磁盘 | 5min | >85% | 清理旧数据 |
| 网络（代理） | 5min | fail×3 | 报PM |

## 上报格式
[运维] ai-briefing: data_freshness — 上次采集已过24h
[运维] ai-briefing: disk — 磁盘 87%，已清理旧数据
