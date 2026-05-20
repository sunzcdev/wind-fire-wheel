# Demo 项目方案

## 架构
一个 Bash 脚本管线，顺序执行 5 个 Gate。

## 组件
- dispatch.sh — 调度入口
- gate-check.sh — Gate 前置条件检查
- 各 Gate 脚本（dev-check, test-check, deliver）

## 实现策略
用 set -euo pipefail 保证错误传递，python3 解析 JSON 配置。
