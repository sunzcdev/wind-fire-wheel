#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 <instance_dir>"
    exit 1
}

[[ $# -lt 1 ]] && usage

INSTANCE_DIR="$(realpath "$1")"
TEAM_JSON="$INSTANCE_DIR/team.json"

[[ -f "$TEAM_JSON" ]] || { echo "[test-check] ERROR: team.json not found at $TEAM_JSON"; exit 1; }

PROJECT_DIR="$(python3 -c "import json; d=json.load(open('$TEAM_JSON')); print(d.get('project_dir',''))" 2>/dev/null || echo "")"
CHECK_DIR="${PROJECT_DIR:-$INSTANCE_DIR}"

FAIL=0

echo "[test-check] Scanning: $CHECK_DIR"
echo ""

# ── Blocking checks ──────────────────────────────────────────────────────────

echo "[test-check] [1/2] Looking for test files..."
TEST_FILES=()
while IFS= read -r -d '' f; do
    TEST_FILES+=("$f")
done < <(find "$CHECK_DIR" \
    \( -name "*_test.py"  -o -name "test_*.py" \
    -o -name "*_test.go"  -o -name "*_test.js" \
    -o -name "*.spec.js"  -o -name "*.spec.ts" \
    -o -name "*.spec.jsx" -o -name "*.spec.tsx" \
    -o -name "*.test.js"  -o -name "*.test.ts" \
    -o -name "*.test.jsx" -o -name "*.test.tsx" \
    \) -not -path "*/.git/*" -not -path "*/node_modules/*" -print0 2>/dev/null)

if [[ "${#TEST_FILES[@]}" -eq 0 ]]; then
    echo "[test-check] FAIL: no test files found"
    echo "[test-check] Expected: *_test.py, test_*.py, *.spec.*, *.test.*"
    FAIL=1
else
    echo "[test-check] OK: found ${#TEST_FILES[@]} test file(s)"
    for f in "${TEST_FILES[@]}"; do
        echo "  - $f"
    done
fi

echo ""
echo "[test-check] [2/2] Running tests..."

detect_and_run_tests() {
    local dir="$1"

    # pytest
    if [[ -f "$dir/pytest.ini" || -f "$dir/setup.cfg" || -f "$dir/pyproject.toml" ]] || \
       find "$dir" -name "test_*.py" -o -name "*_test.py" 2>/dev/null | grep -q .; then
        if command -v pytest &>/dev/null; then
            echo "[test-check] Detected: pytest"
            if pytest "$dir" -q --tb=short 2>&1; then
                echo "[test-check] OK: pytest passed"
                return 0
            else
                echo "[test-check] FAIL: pytest failed"
                return 1
            fi
        fi
    fi

    # go test
    if [[ -f "$dir/go.mod" ]]; then
        echo "[test-check] Detected: go test"
        if (cd "$dir" && go test ./... 2>&1); then
            echo "[test-check] OK: go test passed"
            return 0
        else
            echo "[test-check] FAIL: go test failed"
            return 1
        fi
    fi

    # npm / jest
    if [[ -f "$dir/package.json" ]]; then
        local test_script
        test_script=$(python3 -c "import json; d=json.load(open('$dir/package.json')); print(d.get('scripts',{}).get('test',''))" 2>/dev/null || echo "")
        if [[ -n "$test_script" ]]; then
            echo "[test-check] Detected: npm test"
            if (cd "$dir" && npm test --silent 2>&1); then
                echo "[test-check] OK: npm test passed"
                return 0
            else
                echo "[test-check] FAIL: npm test failed"
                return 1
            fi
        fi
    fi

    echo "[test-check] WARN: cannot detect test runner — skipping execution"
    return 0
}

if [[ "$FAIL" -eq 0 ]]; then
    if ! detect_and_run_tests "$CHECK_DIR"; then
        FAIL=1
    fi
else
    echo "[test-check] Skipping test run (no test files found)"
fi

# ── Non-blocking checklist ────────────────────────────────────────────────────

echo ""
echo "[test-check] ── Checklist (review manually, non-blocking) ──"
echo "[test-check] [ ] Do tests cover the core/happy path?"
echo "[test-check] [ ] Are boundary and edge cases tested?"
echo "[test-check] [ ] Are there regression guards for previously fixed bugs?"

echo ""
if [[ "$FAIL" -eq 0 ]]; then
    echo "[test-check] RESULT: ALL blocking checks passed"
    exit 0
else
    echo "[test-check] RESULT: BLOCKED — fix the issues above before proceeding"
    exit 1
fi
