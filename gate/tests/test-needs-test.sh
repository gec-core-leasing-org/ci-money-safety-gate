#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; gate="$here/.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
run(){ GATE_FILES_FILE="$2" GATE_SKIP_TEST="${4:-0}" bash "$gate/check-needs-test.sh" >/dev/null 2>&1; local g=$?;
  [[ "$g" == "$3" ]] && { echo "PASS $1"; pass=$((pass+1)); } || { echo "FAIL $1 (exit $g want $3)"; fail=$((fail+1)); }; }

printf 'finance/calc.go\n' >"$tmp/no_test.files"
run "money .go without test -> fail" "$tmp/no_test.files" 1

printf 'finance/calc.go\nfinance/calc_test.go\n' >"$tmp/with_test.files"
run "money .go with sibling test -> pass" "$tmp/with_test.files" 0

printf 'finance/calc.go\nfinance/sub/other_test.go\n' >"$tmp/wrong_dir.files"
run "test in different dir -> fail" "$tmp/wrong_dir.files" 1

printf 'handler/ui.go\n' >"$tmp/nonmoney.files"
run "non-money .go without test -> pass" "$tmp/nonmoney.files" 0

printf 'vendor/github.com/x/finance/calc.go\n' >"$tmp/vendor.files"
run "vendored money .go without test -> pass (vendor excluded)" "$tmp/vendor.files" 0

run "skip label overrides -> pass" "$tmp/no_test.files" 0 1

echo "== $pass passed / $fail failed =="; [[ "$fail" == 0 ]]
