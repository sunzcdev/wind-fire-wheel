# 无敌风火轮 — 实例：Solo Coder 标注流水线

## 项目概述
基于 CDP 操控 Trae IDE 的全自动标注流水线。从出题→审批→注入→监视→审查→提交，全链路自动化。

## 运行中资源
- 项目路径：`~/AIProjects/solo-code-pipline/`
- Trae 目标项目：`~/AIProjects/solo-coder-mark/`
- 配置文件：`~/AIProjects/solo-code-pipline/config.yaml`
- 状态文件：`~/AIProjects/solo-code-pipline/context.json`

## 启动命令
```bash
cd ~/AIProjects/solo-code-pipline
python3 main.py start 40650 "Feature迭代"
```

## 当前 Gate 状态
- Gate 1 需求解析：idle
- Gate 2 方案生成：idle
- Gate 3 实现：idle
- Gate 4 验证：idle
- Gate 5 交付判定：idle

## 成员
| 角色 | 身份 |
|------|------|
| PO | 孙振朝 |
| PM | Hermes |
| Dev | CC/OpenCode |
| Test | 自动化测试 |
| Ops | Hermes (Ops) |

## 飞书
Bitable 表格：app_token=HO1Kb3JQpa9e0WsHhQ0c2dpLnYb, table_id=tblfVRXx3qotQ4mO
