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
BUG_DIR="$INSTANCE_DIR/bugs"

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

write_bug_report() {
    local gate="$1"
    local check_output="$2"
    mkdir -p "$BUG_DIR"
    local bugfile="$BUG_DIR/bug-$(date +%Y%m%d-%H%M%S).md"
    cat > "$bugfile" <<-EOF
# Bug Report — Gate: ${gate}

**时间:** $(date '+%Y-%m-%d %H:%M:%S')
**实例:** $(basename "$INSTANCE_DIR")

## 检查失败输出
\`\`\`
${check_output}
\`\`\`

## 要求
修复后提交，交由重新验证。
EOF
    echo "$bugfile"
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

    CHECK_OUTPUT=$("$SCRIPT_DIR/gate-check.sh" "$INSTANCE_DIR" "$GATE" 2>&1) || {
        EXIT_CODE=$?
        echo "[dispatch] BLOCKED at gate: $GATE — preconditions not met"
        echo "$CHECK_OUTPUT"

        # ---- 回流逻辑 ----
        if [[ "$GATE" == "verification" ]]; then
            # verification 失败 → 记录 bug → 退回 implementation
            echo "[dispatch] ========== 回流: 测试不通过，退回实现阶段 =========="
            BUG_FILE=$(write_bug_report "$GATE" "$CHECK_OUTPUT")
            echo "[dispatch] bug 报告: $BUG_FILE"
            set_gate "implementation"
            echo "[dispatch] current_gate 已重置为 implementation，Dev 可重新开始"
            echo "[dispatch] bug 摘要:"
            head -5 "$BUG_FILE"
        elif [[ "$GATE" == "implementation" ]]; then
            # implementation 失败 → 退回 design （方案有问题）
            echo "[dispatch] ========== 回流: 实现不通过，退回方案阶段 =========="
            set_gate "design"
            echo "[dispatch] current_gate 已重置为 design"
        else
            # 其他 Gate 失败 → 直接停，等人处理
            echo "[dispatch] 前置条件不满足，等待人工处理"
        fi

        exit "$EXIT_CODE"
    }

    echo "[dispatch] PASSED gate: $GATE"

    # 清理历史 bug 报告（如果当前 gate 通过了）
    if [[ "$GATE" == "verification" ]] && [[ -d "$BUG_DIR" ]]; then
        rm -f "$BUG_DIR"/*.md
        rmdir "$BUG_DIR" 2>/dev/null || true
        echo "[dispatch] bug 报告已清空"
    fi

    NEXT_IDX=$((i + 1))
    if [[ "$NEXT_IDX" -lt "${#GATE_ORDER[@]}" ]]; then
        set_gate "${GATE_ORDER[$NEXT_IDX]}"
    else
        set_gate "delivered"
    fi
done

echo "[dispatch] All gates passed. current_gate updated."
