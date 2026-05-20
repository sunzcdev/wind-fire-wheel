#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 <instance_dir> <gate_name>"
    echo "  gate_name: requirement | design | implementation | verification | delivery"
    exit 1
}

[[ $# -lt 2 ]] && usage

INSTANCE_DIR="$(realpath "$1")"
GATE="$2"

check_requirement() {
    local req_dir="$INSTANCE_DIR/docs"
    local found=0
    for f in "$INSTANCE_DIR"/{requirement,requirements,需求}.{md,txt,rst} "$INSTANCE_DIR"/docs/{requirement,requirements}.{md,txt} 2>/dev/null; do
        [[ -f "$f" ]] && found=1 && break
    done
    if [[ "$found" -eq 0 ]] && [[ -d "$req_dir" ]]; then
        local count
        count=$(find "$req_dir" -name "*.md" -o -name "*.txt" | wc -l)
        [[ "$count" -gt 0 ]] && found=1
    fi
    if [[ "$found" -eq 0 ]]; then
        echo "[gate-check] FAIL requirement: no requirement document found in $INSTANCE_DIR"
        echo "[gate-check] Expected: requirement.md, requirements.md, or docs/*.md"
        return 1
    fi
    echo "[gate-check] OK requirement: document found"
}

check_design() {
    local found=0
    for f in "$INSTANCE_DIR"/{design,方案,architecture,arch}.{md,txt,rst} "$INSTANCE_DIR"/docs/{design,architecture}.{md,txt} 2>/dev/null; do
        [[ -f "$f" ]] && found=1 && break
    done
    if [[ "$found" -eq 0 ]]; then
        echo "[gate-check] FAIL design: no design document found in $INSTANCE_DIR"
        echo "[gate-check] Expected: design.md, architecture.md, or docs/design.md"
        return 1
    fi
    echo "[gate-check] OK design: document found"
}

check_implementation() {
    local project_dir
    project_dir="$(python3 -c "import json; d=json.load(open('$INSTANCE_DIR/team.json')); print(d.get('project_dir',''))" 2>/dev/null || echo "")"
    local check_dir="${project_dir:-$INSTANCE_DIR}"

    if ! git -C "$check_dir" rev-parse HEAD &>/dev/null 2>&1; then
        echo "[gate-check] FAIL implementation: not a git repository at $check_dir"
        return 1
    fi

    local diff_stat
    diff_stat=$(git -C "$check_dir" diff --stat HEAD 2>/dev/null || echo "")
    if [[ -n "$diff_stat" ]]; then
        echo "[gate-check] FAIL implementation: uncommitted changes detected"
        echo "$diff_stat"
        return 1
    fi

    local commit_count
    commit_count=$(git -C "$check_dir" rev-list --count HEAD 2>/dev/null || echo "0")
    if [[ "$commit_count" -lt 1 ]]; then
        echo "[gate-check] FAIL implementation: no commits found"
        return 1
    fi

    echo "[gate-check] OK implementation: code committed"
}

check_verification() {
    local test_found=0
    while IFS= read -r -d '' f; do
        test_found=1
        break
    done < <(find "$INSTANCE_DIR" \( -name "*_test.*" -o -name "test_*.*" -o -name "*.spec.*" \) -not -path "*/.git/*" -print0 2>/dev/null)

    if [[ "$test_found" -eq 0 ]]; then
        echo "[gate-check] FAIL verification: no test files found"
        echo "[gate-check] Expected: *_test.*, test_*.*, or *.spec.*"
        return 1
    fi

    echo "[gate-check] OK verification: test files found"
}

check_delivery() {
    local team_json="$INSTANCE_DIR/team.json"
    local gate
    gate=$(python3 -c "import json; d=json.load(open('$team_json')); print(d.get('current_gate',''))" 2>/dev/null || echo "")

    local project_dir
    project_dir="$(python3 -c "import json; d=json.load(open('$team_json')); print(d.get('project_dir',''))" 2>/dev/null || echo "")"
    local check_dir="${project_dir:-$INSTANCE_DIR}"

    if ! git -C "$check_dir" rev-parse HEAD &>/dev/null 2>&1; then
        echo "[gate-check] FAIL delivery: not a git repository"
        return 1
    fi

    local diff_stat
    diff_stat=$(git -C "$check_dir" diff --stat HEAD 2>/dev/null || echo "")
    if [[ -n "$diff_stat" ]]; then
        echo "[gate-check] FAIL delivery: uncommitted changes — run dev-check first"
        return 1
    fi

    echo "[gate-check] OK delivery: artifacts ready"
}

case "$GATE" in
    requirement)    check_requirement ;;
    design)         check_design ;;
    implementation) check_implementation ;;
    verification)   check_verification ;;
    delivery)       check_delivery ;;
    *)
        echo "[gate-check] ERROR: unknown gate '$GATE'"
        echo "Valid gates: requirement design implementation verification delivery"
        exit 1
        ;;
esac
