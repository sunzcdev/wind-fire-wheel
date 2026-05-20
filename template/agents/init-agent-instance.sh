#!/usr/bin/env bash
# 初始化风火轮 v3 实例 — 创建 agent 队列目录 + 启动 daemon
# 用法: init-agent-instance.sh <instance_dir> [project_dir]
set -euo pipefail

INSTANCE_DIR="$(realpath "$1")"
PROJECT_DIR="${2:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "[init] 初始化 agent 实例: $INSTANCE_DIR"

# 1. 创建队列目录
mkdir -p "$INSTANCE_DIR"/tasks/{pending,in_progress,done}
mkdir -p "$INSTANCE_DIR"/test-jobs/{pending,in_progress,done}
mkdir -p "$INSTANCE_DIR"/reports
echo "[init] ✅ 队列目录已创建"

# 2. 如果 team.json 存在，更新 project_dir
TEAM_JSON="$INSTANCE_DIR/team.json"
if [[ -f "$TEAM_JSON" && -n "$PROJECT_DIR" ]]; then
  python3 -c "
import json
d = json.load(open('$TEAM_JSON'))
d['project_dir'] = '$PROJECT_DIR'
json.dump(d, open('$TEAM_JSON', 'w'), indent=2, ensure_ascii=False)
" 2>/dev/null
  echo "[init] ✅ team.json project_dir 已更新: $PROJECT_DIR"
fi

# 3. 启动 Dev daemon（后台）
DEV_SCRIPT="$TEMPLATE_DIR/agents/dev-daemon.py"
if [[ -f "$DEV_SCRIPT" ]]; then
  python3 "$DEV_SCRIPT" --instance "$INSTANCE_DIR" &
  DEV_PID=$!
  echo "[init] ✅ Dev daemon 已启动 (PID $DEV_PID)"
  disown "$DEV_PID" 2>/dev/null || true
else
  echo "[init] ⚠️  dev-daemon.py 不存在，跳过"
fi

# 4. 启动 Test daemon（后台）
TEST_SCRIPT="$TEMPLATE_DIR/agents/test-daemon.py"
if [[ -f "$TEST_SCRIPT" ]]; then
  python3 "$TEST_SCRIPT" --instance "$INSTANCE_DIR" &
  TEST_PID=$!
  echo "[init] ✅ Test daemon 已启动 (PID $TEST_PID)"
  disown "$TEST_PID" 2>/dev/null || true
else
  echo "[init] ⚠️  test-daemon.py 不存在，跳过"
fi

echo "[init] ✅ 完成"
