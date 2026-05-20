# 风火轮共享知识库 — 测试标准

## 核心原则
- **测试不是"没报错= PASS"**，必须验证实际结果
- **本地保存 ≠ 成功**，只有线上 Bitable 能查到才算 submit PASS
- **测试用独立后台进程**（terminal background），不被消息打断
- **delegate_task 会被中断**，不能用

## 主动监测规范
1. **每 10s 检查 daemon 进程**：`pgrep -f daemon`，挂了立刻报
2. **每 5s 检查 context 状态**：读 context.json 看 status 是否推进
3. **同一阶段卡 30s 报警**：status 不变超过 30s 就是有问题
4. **总超时 5 分钟**：超过就报异常退出，不等死

## Design 阶段检查
| 检查项 | PASS 条件 |
|--------|----------|
| LLM 调用 | API 返回成功，解析出合法 JSON |
| prompt 内容 | user_prompt 非空，有实际内容 |
| task_type | metadata.task_type = 预设值 |
| metadata 完整性 | task_type/business_domain/modification_scope 三者齐全 |

## Approve 阶段检查
| 检查项 | PASS 条件 |
|--------|----------|
| 轮询确认 | daemon 在 30s 内检测到 prompt_confirmed=true |
| 状态推进 | context.status 从 approve → inject |

## Inject 阶段检查
| 检查项 | PASS 条件 |
|--------|----------|
| CDP 连接 | connect() 成功 |
| 注入结果 | inject_success=True |
| 弹窗处理 | auth dialog 被自动点掉 |
| 截图 before | before 截图文件存在且非空 PNG |

## Watch 阶段检查
| 检查项 | PASS 条件 |
|--------|----------|
| 完成检测 | context 状态推进到 review |
| 截图 after | after 截图文件存在且非空 PNG |
| 会话ID格式 | session_id 含 user_id/session_id/message_id 三段，末尾有 `Trae CN.T(时间)` |
| 轨迹格式 | trajectory 非空 >500 字符，含任务描述/文件操作/进度标记 |

## Review 阶段检查
| 检查项 | PASS 条件 |
|--------|----------|
| LLM 审查 | 返回合法 JSON，satisfied 字段有值 |
| diff 存在 | diff 字段非空 |
| 不满意原因 | satisfied=False 时 dissatisfaction_reason 非空 |

## Submit 阶段检查 ⭐
| 检查项 | PASS 条件 | FAIL 条件 |
|--------|----------|-----------|
| 线上写入 | 用 lark-cli 查 Bitable，确认该 UID 记录真实存在 | 线上表格查不到 |
| 字段值 | prompt/task_type/session_id/satisfied/reason 正确 | 字段缺失或值不对 |
| record_id | 返回线上 record_id（非 local_ 开头） | 返回 local_xxx |
| 截图上传 | before/after 截图已上传到 Bitable 截图表字段 | 未上传 |
| 本地保存 | 本地保存是 fallback，不能算 PASS | 只有本地保存但线上无记录 = ❌ |
