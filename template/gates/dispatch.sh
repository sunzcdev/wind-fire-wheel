#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    echo "Usage: $0 <instance_dir>"
    echo "  instance_dir: path to instances/<project>/ directory"
    exit 1
}

[[ $# -lt 1 ]] && usage

INSTANCE_DIR="$(realpath "$1")"
TEAM_JSON="$INSTANCE_DIR/team.json"

[[ -f "$TEAM_JSON" ]] || { echo "[dispatch] ERROR: team.json not found at $TEAM_JSON"; exit 1; }

GATE_ORDER=("requirement" "design" "implementation" "verification" "delivery")

current_gate() {
    local val
    val=$(python3 -c "import json,sys; d=json.load(open('$TEAM_JSON')); v=d.get('current_gate'); print(v if v and v != 'None' else 'requirement')")
    echo "$val"
}

set_gate() {
    local gate="$1"
    python3 -c "
import json
with open('$TEAM_JSON','r') as f:
    d = json.load(f)
d['current_gate'] = '$gate'
with open('$TEAM_JSON','w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
"
}

gate_index() {
    local gate="$1"
    for i in "${!GATE_ORDER[@]}"; do
        [[ "${GATE_ORDER[$i]}" == "$gate" ]] && echo "$i" && return
    done
    echo "-1"
}

START_GATE="$(current_gate)"
START_IDX="$(gate_index "$START_GATE")"

if [[ "$START_IDX" == "-1" ]]; then
    echo "[dispatch] Unknown current_gate: $START_GATE"
    exit 1
fi

echo "[dispatch] Starting from gate: $START_GATE"

for i in $(seq "$START_IDX" $((${#GATE_ORDER[@]} - 1))); do
    GATE="${GATE_ORDER[$i]}"
    echo "[dispatch] Checking gate: $GATE"

    if ! "$SCRIPT_DIR/gate-check.sh" "$INSTANCE_DIR" "$GATE"; then
        echo "[dispatch] BLOCKED at gate: $GATE — preconditions not met"
        exit 1
    fi

    echo "[dispatch] PASSED gate: $GATE"
    NEXT_IDX=$((i + 1))
    if [[ "$NEXT_IDX" -lt "${#GATE_ORDER[@]}" ]]; then
        set_gate "${GATE_ORDER[$NEXT_IDX]}"
    else
        set_gate "delivered"
    fi
done

echo "[dispatch] All gates passed. current_gate updated."
