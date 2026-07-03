#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; gate="$here/.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
run(){ GATE_DIFF_FILE="$2" bash "$gate/check-no-float.sh" >/dev/null 2>&1; local g=$?;
  [[ "$g" == "$3" ]] && { echo "PASS $1"; pass=$((pass+1)); } || { echo "FAIL $1 (exit $g want $3)"; fail=$((fail+1)); }; }

printf 'diff --git a/finance/calc.go b/finance/calc.go\n+++ b/finance/calc.go\n+\tvar rate float64 = 3.5\n' >"$tmp/bad.diff"
run "float in money path -> fail" "$tmp/bad.diff" 1

printf '+++ b/finance/calc.go\n+\tvar rate float64 = 3.5 //money:allow-float reason=display\n' >"$tmp/allow.diff"
run "allow-float escape -> pass" "$tmp/allow.diff" 0

printf '+++ b/handler/ui.go\n+\tvar x float64 = 1.0\n' >"$tmp/nonmoney.diff"
run "float outside money path -> pass" "$tmp/nonmoney.diff" 0

printf '+++ b/finance/calc.go\n+\tvar amt decimal.Decimal\n' >"$tmp/clean.diff"
run "decimal in money path -> pass" "$tmp/clean.diff" 0

printf '+++ b/vendor/github.com/x/finance/calc.go\n+\tvar rate float64 = 3.5\n' >"$tmp/vendor.diff"
run "float in vendored money path -> pass (vendor excluded)" "$tmp/vendor.diff" 0

echo "== $pass passed / $fail failed =="; [[ "$fail" == 0 ]]
