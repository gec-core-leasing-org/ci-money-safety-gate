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

# Fix 2 (I1): quoted-path handling (git core.quotePath octal-escapes non-ASCII names)
printf '"finance/\\340\\270\\204.go"\n' >"$tmp/quoted.files"
run "quoted money .go without test -> fail" "$tmp/quoted.files" 1

# Fix 1 (C1): fail-closed guards
(unset GATE_FILES_FILE BASE_SHA HEAD_SHA GATE_SKIP_TEST; bash "$gate/check-needs-test.sh") >/dev/null 2>&1
g=$?
[[ "$g" == 2 ]] && { echo "PASS no override + no SHAs -> exit 2"; pass=$((pass+1)); } || { echo "FAIL no override + no SHAs -> exit 2 (got $g)"; fail=$((fail+1)); }

(unset BASE_SHA HEAD_SHA GATE_SKIP_TEST; GATE_FILES_FILE=/nonexistent bash "$gate/check-needs-test.sh") >/dev/null 2>&1
g=$?
[[ "$g" == 2 ]] && { echo "PASS GATE_FILES_FILE nonexistent -> exit 2"; pass=$((pass+1)); } || { echo "FAIL GATE_FILES_FILE nonexistent -> exit 2 (got $g)"; fail=$((fail+1)); }

# git diff failure (unfetched SHA / shallow clone) must fail closed, not exit 0
(cd "$gate" && unset GATE_FILES_FILE GATE_SKIP_TEST; BASE_SHA=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef HEAD_SHA=cafebabecafebabecafebabecafebabecafebabe bash "$gate/check-needs-test.sh") >/dev/null 2>&1
g=$?
[[ "$g" == 2 ]] && { echo "PASS bogus SHAs (git diff fails) -> exit 2"; pass=$((pass+1)); } || { echo "FAIL bogus SHAs (git diff fails) -> exit 2 (got $g)"; fail=$((fail+1)); }

echo "== $pass passed / $fail failed =="; [[ "$fail" == 0 ]]
