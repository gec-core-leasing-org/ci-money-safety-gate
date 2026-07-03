#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; gate="$here/.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
run(){ GATE_DIFF_FILE="$2" bash "$gate/check-sqli.sh" >/dev/null 2>&1; local g=$?;
  [[ "$g" == "$3" ]] && { echo "PASS $1"; pass=$((pass+1)); } || { echo "FAIL $1 (exit $g want $3)"; fail=$((fail+1)); }; }

printf '+++ b/repo/q.go\n+\tdb.Raw(fmt.Sprintf("SELECT * FROM t WHERE id=%%s", id))\n' >"$tmp/raw.diff"
run "Sprintf into Raw -> fail" "$tmp/raw.diff" 1

printf '+++ b/repo/q.go\n+\tq := fmt.Sprintf("ORDER BY %%s", col)\n' >"$tmp/order.diff"
run "Sprintf ORDER BY -> fail" "$tmp/order.diff" 1

printf '+++ b/repo/q.go\n+\tdb.Where("id = ?", id)\n' >"$tmp/param.diff"
run "parameterized -> pass" "$tmp/param.diff" 0

printf '+++ b/repo/q.go\n+\tmsg := fmt.Sprintf("hello %%s", name)\n' >"$tmp/plain.diff"
run "Sprintf non-SQL -> pass" "$tmp/plain.diff" 0

printf '+++ b/vendor/github.com/x/orm/q.go\n+\tdb.Raw(fmt.Sprintf("SELECT * FROM t WHERE id=%%s", id))\n' >"$tmp/vendor.diff"
run "Sprintf+SQL in vendor -> pass (vendor excluded)" "$tmp/vendor.diff" 0

echo "== $pass passed / $fail failed =="; [[ "$fail" == 0 ]]
