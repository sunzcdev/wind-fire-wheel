#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 <instance_dir>"
    exit 1
}

[[ $# -lt 1 ]] && usage

INSTANCE_DIR="$(realpath "$1")"
TEAM_JSON="$INSTANCE_DIR/team.json"

[[ -f "$TEAM_JSON" ]] || { echo "[dev-check] ERROR: team.json not found at $TEAM_JSON"; exit 1; }

PROJECT_DIR="$(python3 -c "import json; d=json.load(open('$TEAM_JSON')); print(d.get('project_dir',''))" 2>/dev/null || echo "")"
CHECK_DIR="${PROJECT_DIR:-$INSTANCE_DIR}"

FAIL=0

echo "[dev-check] Scanning: $CHECK_DIR"
echo ""

# ── Blocking checks ──────────────────────────────────────────────────────────

echo "[dev-check] [1/3] Checking for uncommitted diff..."
if git -C "$CHECK_DIR" rev-parse HEAD &>/dev/null 2>&1; then
    DIFF_STAT=$(git -C "$CHECK_DIR" diff --stat 2>/dev/null || echo "")
    DIFF_CACHED=$(git -C "$CHECK_DIR" diff --cached --stat 2>/dev/null || echo "")
    if [[ -n "$DIFF_STAT" || -n "$DIFF_CACHED" ]]; then
        echo "[dev-check] FAIL: uncommitted changes detected"
        [[ -n "$DIFF_STAT" ]]    && echo "$DIFF_STAT"
        [[ -n "$DIFF_CACHED" ]] && echo "$DIFF_CACHED"
        FAIL=1
    else
        echo "[dev-check] OK: working tree clean"
    fi
else
    echo "[dev-check] WARN: not a git repo, skipping diff check"
fi

echo ""
echo "[dev-check] [2/3] Checking for debug print / console.log..."
if command -v rg &>/dev/null; then
    DEBUG_HITS=$(rg --no-heading -n \
        -e '\bprint\s*\(' \
        -e '\bconsole\.log\s*\(' \
        -e '\bdebugger\b' \
        --glob '!*.sh' \
        --glob '!*.md' \
        "$CHECK_DIR" 2>/dev/null || true)
else
    DEBUG_HITS=$(grep -rn \
        -e 'print(' \
        -e 'console\.log(' \
        -e 'debugger' \
        --include='*.py' --include='*.js' --include='*.ts' --include='*.jsx' --include='*.tsx' \
        "$CHECK_DIR" 2>/dev/null || true)
fi

if [[ -n "$DEBUG_HITS" ]]; then
    echo "[dev-check] FAIL: debug statements found:"
    echo "$DEBUG_HITS" | head -20
    FAIL=1
else
    echo "[dev-check] OK: no debug statements"
fi

echo ""
echo "[dev-check] [3/3] Checking for hardcoded secrets / passwords..."
SECRET_PATTERN='(password|passwd|secret|api_key|apikey|token|private_key)\s*=\s*["\x27][^"\x27]{4,}'
if command -v rg &>/dev/null; then
    SECRET_HITS=$(rg --no-heading -n -i \
        -e "$SECRET_PATTERN" \
        --glob '!*.sh' \
        --glob '!*.md' \
        --glob '!*test*' \
        "$CHECK_DIR" 2>/dev/null || true)
else
    SECRET_HITS=$(grep -rni -E "$SECRET_PATTERN" \
        --include='*.py' --include='*.js' --include='*.ts' --include='*.env' \
        "$CHECK_DIR" 2>/dev/null || true)
fi

if [[ -n "$SECRET_HITS" ]]; then
    echo "[dev-check] FAIL: potential hardcoded secrets found:"
    echo "$SECRET_HITS" | head -20
    FAIL=1
else
    echo "[dev-check] OK: no hardcoded secrets detected"
fi

# ── Non-blocking checklist ────────────────────────────────────────────────────

echo ""
echo "[dev-check] ── Checklist (review manually, non-blocking) ──"
echo "[dev-check] [ ] Are identifiers self-explanatory? (no x, tmp, data, foo)"
echo "[dev-check] [ ] Any obvious performance issues? (N+1 queries, loop-in-loop, unbounded scans)"
echo "[dev-check] [ ] Is security logic complete? (auth checks, input validation, output escaping)"

echo ""
if [[ "$FAIL" -eq 0 ]]; then
    echo "[dev-check] RESULT: ALL blocking checks passed"
    exit 0
else
    echo "[dev-check] RESULT: BLOCKED — fix the issues above before proceeding"
    exit 1
fi
