#!/usr/bin/env bash
set -euo pipefail

# lan-scan.sh 验收测试

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAN_SCAN="$SCRIPT_DIR/lan-scan.sh"
PASS=0
FAIL=0

pass()  { echo "✅ $1"; PASS=$((PASS+1)); }
fail()  { echo "❌ $1"; FAIL=$((FAIL+1)); }

echo "=== lan-scan.sh 验收测试 ==="

# 1. 语法检查
echo "--- 1. 语法检查 ---"
bash -n "$LAN_SCAN" && pass "bash -n 通过" || fail "bash -n 报错"

# 2. help 输出
echo "--- 2. help 参数 ---"
if timeout 3 bash "$LAN_SCAN" --help 2>&1 | grep -q "用法"; then
    pass "help 输出正确"
else
    fail "help 未输出"
fi

# 3. 正常扫描（限 5s）
echo "--- 3. 正常扫描 ---"
output=$(timeout 10 bash "$LAN_SCAN" 192.168.5 2>&1 || true)
if echo "$output" | grep -q "扫描完成"; then
    pass "扫描正常结束"
else
    fail "扫描未正常结束"
fi

# 4. 输出格式
echo "--- 4. 输出格式 ---"
if echo "$output" | grep -qP "^\d+\.\d+\.\d+\.\d+"; then
    pass "输出包含 IP 地址"
else
    fail "输出缺少 IP 地址"
fi

# 5. MAC 显示
echo "--- 5. MAC 地址 ---"
if echo "$output" | grep -v "扫描" | grep -v "网段" | grep -v "IP" | grep -v "^$" | head -3 | grep -v "N/A"; then
    pass "MAC 地址已获取"
else
    fail "MAC 均为 N/A（arp 缓存未填充，非关键问题）"
fi

echo ""
echo "=== 结果: $PASS 通过, $FAIL 失败 ==="
exit $FAIL
