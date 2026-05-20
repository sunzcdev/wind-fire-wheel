#!/usr/bin/env bash
set -euo pipefail

# auto-dispatch — 自动扫描 instances/ 下所有实例，发现新需求就启动 pipeline。
# 设计用于 cronjob（no_agent=true），无输出=无事件，有输出=需要你关注。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIND_FIRE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTANCES_DIR="$WIND_FIRE_ROOT/instances"
DISPATCH_SCRIPT="$SCRIPT_DIR/dispatch.sh"

NOTIFY=""  # 收集需要通知的消息

echo "[auto-dispatch] $(date '+%Y-%m-%d %H:%M:%S') — scan start" >&2

if [[ ! -d "$INSTANCES_DIR" ]]; then
  echo "[auto-dispatch] ERROR: instances dir not found: $INSTANCES_DIR" >&2
  exit 0
fi

for INSTANCE_DIR in "$INSTANCES_DIR"/*/; do
  [[ -d "$INSTANCE_DIR" ]] || continue

  PROJECT_NAME=$(basename "$INSTANCE_DIR")
  TEAM_JSON="$INSTANCE_DIR/team.json"
  REQUIREMENT_MD="$INSTANCE_DIR/requirement.md"

  [[ -f "$TEAM_JSON" ]] || continue

  # 读当前 gate
  CURRENT_GATE=$(python3 -c "
import json
with open('$TEAM_JSON') as f:
    d = json.load(f)
v = d.get('current_gate')
# None / null / 'None' / empty 都视为未开始
if not v or v == 'None':
    print('')
else:
    print(v)
" 2>/dev/null || echo "")

  # ── 情况1: 未开始，有 requirement.md → 启动 pipeline ──
  if [[ -z "$CURRENT_GATE" && -f "$REQUIREMENT_MD" ]]; then
    echo "[auto-dispatch] >>> $PROJECT_NAME: 检测到 requirement.md，启动 pipeline..." >&2

    # 先设 gate=requirement，然后 run dispatch
    python3 -c "
import json
with open('$TEAM_JSON') as f:
    d = json.load(f)
d['current_gate'] = 'requirement'
with open('$TEAM_JSON', 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
"

    if OUTPUT=$(bash "$DISPATCH_SCRIPT" "$INSTANCE_DIR" 2>&1); then
      echo "[auto-dispatch] ✅ $PROJECT_NAME: pipeline 完成" >&2
    else
      EXIT=$?
      echo "[auto-dispatch] ❌ $PROJECT_NAME: pipeline 失败 (exit=$EXIT)" >&2
      echo "$OUTPUT" >&2
      NOTIFY+="[auto-dispatch] FAIL: $PROJECT_NAME — pipeline 执行出错 (exit=$EXIT)"$'\n'
      NOTIFY+="$OUTPUT"$'\n'
      NOTIFY+=""$'\n'
    fi
  fi

  # ── 情况2: 卡在某个 gate 太久 → 通知 ──
  if [[ -n "$CURRENT_GATE" && "$CURRENT_GATE" != "delivered" ]]; then
    # 检查 requirement.md 是否存在（没有 requirement 的卡住不算异常）
    if [[ ! -f "$REQUIREMENT_MD" ]]; then
      continue  # 没有需求文档，卡住正常
    fi

    # 检查是否有 dispatch 进程正在运行
    if pgrep -f "dispatch.sh.*$INSTANCE_DIR" > /dev/null 2>&1; then
      continue  # 正在跑，不算卡
    fi

    # 检查是否有 bugs/ 目录（说明在回流中，等人修）
    if [[ -d "$INSTANCE_DIR/bugs" ]] && ls "$INSTANCE_DIR/bugs/"*.md &>/dev/null 2>&1; then
      # 有未解决的 bug → 已经在回流，不重复启动
      BUG_COUNT=$(ls "$INSTANCE_DIR/bugs/"*.md 2>/dev/null | wc -l)
      echo "[auto-dispatch] 🔄 $PROJECT_NAME: 卡在 $CURRENT_GATE（$BUG_COUNT 个未修复 bug，等待 Dev）" >&2
      NOTIFY+="[auto-dispatch] STUCK: $PROJECT_NAME — gate $CURRENT_GATE，$BUG_COUNT 个 bug 待修"$'\n'
      continue
    fi

    # 没有 bug 且没在跑 → 可以重试 dispatch
    echo "[auto-dispatch] 🔄 $PROJECT_NAME: 卡在 $CURRENT_GATE（未活动），尝试重跑..." >&2

    if OUTPUT=$(bash "$DISPATCH_SCRIPT" "$INSTANCE_DIR" 2>&1); then
      echo "[auto-dispatch] ✅ $PROJECT_NAME: 重跑完成" >&2
    else
      EXIT=$?
      echo "[auto-dispatch] ❌ $PROJECT_NAME: 重跑失败 (exit=$EXIT)" >&2
      echo "$OUTPUT" >&2
      NOTIFY+="[auto-dispatch] RETRY FAIL: $PROJECT_NAME — gate $CURRENT_GATE 重跑失败 (exit=$EXIT)"$'\n'
    fi
  fi
done

# ── 输出通知（只有异常时才输出，cron 会自动投递到微信/飞书）──
if [[ -n "$NOTIFY" ]]; then
  echo "╔══════════════════════════════════════════════╗"
  echo "║       风火轮 · 自动调度报告                    ║"
  echo "╚══════════════════════════════════════════════╝"
  echo ""
  echo "$NOTIFY"
fi

echo "[auto-dispatch] $(date '+%Y-%m-%d %H:%M:%S') — scan done" >&2
