#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 <instance_dir>"
    exit 1
}

[[ $# -lt 1 ]] && usage

INSTANCE_DIR="$(realpath "$1")"
TEAM_JSON="$INSTANCE_DIR/team.json"

[[ -f "$TEAM_JSON" ]] || { echo "[deliver] ERROR: team.json not found at $TEAM_JSON"; exit 1; }

PROJECT_NAME="$(python3 -c "import json; d=json.load(open('$TEAM_JSON')); print(d.get('project_name', d.get('name','unknown')))" 2>/dev/null || echo "unknown")"
PROJECT_DIR="$(python3 -c "import json; d=json.load(open('$TEAM_JSON')); print(d.get('project_dir',''))" 2>/dev/null || echo "")"
DELIVER_DIR="${PROJECT_DIR:-$INSTANCE_DIR}"

TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
COMMIT_MSG="交付: $PROJECT_NAME $TIMESTAMP"

echo "[deliver] Project: $PROJECT_NAME"
echo "[deliver] Directory: $DELIVER_DIR"
echo "[deliver] Timestamp: $TIMESTAMP"
echo ""

# ── Step 1: commit ────────────────────────────────────────────────────────────
echo "[deliver] Step 1/3: Committing all changes..."
if git -C "$DELIVER_DIR" status --porcelain | grep -q .; then
    git -C "$DELIVER_DIR" add -A
    git -C "$DELIVER_DIR" commit -m "$COMMIT_MSG"
    echo "[deliver] OK: committed"
else
    echo "[deliver] OK: nothing to commit, working tree clean"
fi

# ── Step 2: push ──────────────────────────────────────────────────────────────
echo "[deliver] Step 2/3: Pushing to origin main..."
if git -C "$DELIVER_DIR" remote get-url origin &>/dev/null 2>&1; then
    git -C "$DELIVER_DIR" push origin main
    echo "[deliver] OK: pushed to origin/main"
else
    echo "[deliver] WARN: no remote 'origin' configured — skipping push"
fi

# ── Step 3: update team.json ──────────────────────────────────────────────────
echo "[deliver] Step 3/3: Updating team.json current_gate → delivered..."
python3 -c "
import json
with open('$TEAM_JSON','r') as f:
    d = json.load(f)
d['current_gate'] = 'delivered'
d['delivered_at'] = '$TIMESTAMP'
with open('$TEAM_JSON','w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
"
echo "[deliver] OK: team.json updated"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║              交付完成 / Delivered              ║"
echo "╠══════════════════════════════════════════════╣"
printf  "║  项目: %-37s║\n" "$PROJECT_NAME"
printf  "║  时间: %-37s║\n" "$TIMESTAMP"
COMMIT_HASH=$(git -C "$DELIVER_DIR" rev-parse --short HEAD 2>/dev/null || echo "n/a")
printf  "║  提交: %-37s║\n" "$COMMIT_HASH"
echo "╚══════════════════════════════════════════════╝"
