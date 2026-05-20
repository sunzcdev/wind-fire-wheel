#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATE_DIR="$REPO_ROOT/template"
INSTANCES_DIR="$REPO_ROOT/instances"

usage() {
    echo "Usage: $0 <project_name> <project_dir>"
    echo "  project_name: short slug (e.g. my-feature)"
    echo "  project_dir:  absolute path to the project's source code"
    exit 1
}

[[ $# -lt 2 ]] && usage

PROJECT_NAME="$1"
PROJECT_DIR="$(realpath "$2")"

INSTANCE_DIR="$INSTANCES_DIR/$PROJECT_NAME"

if [[ -d "$INSTANCE_DIR" ]]; then
    echo "[init-instance] ERROR: instance already exists: $INSTANCE_DIR"
    exit 1
fi

echo "[init-instance] Creating instance: $PROJECT_NAME"
echo "[init-instance] Source: $PROJECT_DIR"
echo ""

# ── Step 1: create directory ──────────────────────────────────────────────────
mkdir -p "$INSTANCE_DIR"
echo "[init-instance] OK: created $INSTANCE_DIR"

# ── Step 2: copy template team.json ──────────────────────────────────────────
cp "$TEMPLATE_DIR/team.json" "$INSTANCE_DIR/team.json"
echo "[init-instance] OK: copied team.json"

# ── Step 3: interactive member config ─────────────────────────────────────────
echo ""
echo "[init-instance] Configure team members (press Enter to skip):"
echo ""

read -rp "  PO (Product Owner) name: " PO_NAME
read -rp "  PO contact (email/slack): " PO_CONTACT
read -rp "  Dev lead name: " DEV_NAME
read -rp "  Dev contact (email/slack): " DEV_CONTACT
read -rp "  QA / Test lead name: " TEST_NAME
read -rp "  QA contact (email/slack): " TEST_CONTACT

TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

python3 - <<PYEOF
import json

with open('$INSTANCE_DIR/team.json', 'r') as f:
    d = json.load(f)

d['project_name']   = '$PROJECT_NAME'
d['project_dir']    = '$PROJECT_DIR'
d['current_gate']   = 'requirement'
d['created_at']     = '$TIMESTAMP'

d['members'] = {
    'po':   {'name': '$PO_NAME',   'contact': '$PO_CONTACT'},
    'dev':  {'name': '$DEV_NAME',  'contact': '$DEV_CONTACT'},
    'test': {'name': '$TEST_NAME', 'contact': '$TEST_CONTACT'},
}

with open('$INSTANCE_DIR/team.json', 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)

print('[init-instance] OK: team.json populated')
PYEOF

# ── Step 4: copy ops/ ─────────────────────────────────────────────────────────
cp -r "$TEMPLATE_DIR/ops" "$INSTANCE_DIR/ops"
echo "[init-instance] OK: copied ops/"

# ── Done ───────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║         实例初始化完成 / Instance Ready        ║"
echo "╠══════════════════════════════════════════════╣"
printf  "║  名称: %-37s║\n" "$PROJECT_NAME"
printf  "║  目录: %-37s║\n" "$INSTANCE_DIR"
printf  "║  Gate: %-37s║\n" "requirement"
echo "╠══════════════════════════════════════════════╣"
echo "║  下一步 / Next:                               ║"
echo "║    1. 添加 requirement.md 文档                ║"
echo "║    2. 运行 dispatch.sh <instance_dir>         ║"
echo "╚══════════════════════════════════════════════╝"
