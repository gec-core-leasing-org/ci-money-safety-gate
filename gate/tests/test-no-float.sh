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

# Fix 2 (I1): quoted-path handling (git core.quotePath octal-escapes non-ASCII names)
printf '+++ "b/finance/\\340\\270\\204.go"\n+\tvar rate float64 = 3.5\n' >"$tmp/quoted.diff"
run "quoted money-path file with float64 -> fail" "$tmp/quoted.diff" 1

printf '+++ b/finance/my calc.go\t\n+\tvar rate float64 = 3.5\n' >"$tmp/space.diff"
run "path-with-space (trailing tab) with float -> fail" "$tmp/space.diff" 1

# Fix 3 (I2): allow-float must require reason=
printf '+++ b/finance/calc.go\n+\tvar rate float64 = 3.5 //money:allow-float\n' >"$tmp/allow_bare.diff"
run "bare allow-float (no reason) -> fail" "$tmp/allow_bare.diff" 1

# Fix 1 (C1): fail-closed guards
(unset GATE_DIFF_FILE BASE_SHA HEAD_SHA; bash "$gate/check-no-float.sh") >/dev/null 2>&1
g=$?
[[ "$g" == 2 ]] && { echo "PASS no override + no SHAs -> exit 2"; pass=$((pass+1)); } || { echo "FAIL no override + no SHAs -> exit 2 (got $g)"; fail=$((fail+1)); }

(unset BASE_SHA HEAD_SHA; GATE_DIFF_FILE=/nonexistent bash "$gate/check-no-float.sh") >/dev/null 2>&1
g=$?
[[ "$g" == 2 ]] && { echo "PASS GATE_DIFF_FILE nonexistent -> exit 2"; pass=$((pass+1)); } || { echo "FAIL GATE_DIFF_FILE nonexistent -> exit 2 (got $g)"; fail=$((fail+1)); }

printf '+++ b/finance/calc.go\n+\tvar rate float64 = 3.5\n' >"$tmp/moneypaths.diff"
(unset BASE_SHA HEAD_SHA; GATE_MONEY_PATHS=/nonexistent GATE_DIFF_FILE="$tmp/moneypaths.diff" bash "$gate/check-no-float.sh") >/dev/null 2>&1
g=$?
[[ "$g" == 2 ]] && { echo "PASS GATE_MONEY_PATHS nonexistent -> exit 2"; pass=$((pass+1)); } || { echo "FAIL GATE_MONEY_PATHS nonexistent -> exit 2 (got $g)"; fail=$((fail+1)); }

# git diff failure (unfetched SHA / shallow clone) must fail closed, not exit 0
(cd "$gate" && unset GATE_DIFF_FILE; BASE_SHA=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef HEAD_SHA=cafebabecafebabecafebabecafebabecafebabe bash "$gate/check-no-float.sh") >/dev/null 2>&1
g=$?
[[ "$g" == 2 ]] && { echo "PASS bogus SHAs (git diff fails) -> exit 2"; pass=$((pass+1)); } || { echo "FAIL bogus SHAs (git diff fails) -> exit 2 (got $g)"; fail=$((fail+1)); }

# GATE_DIFF_FILE pointing at a directory passes -r but cat fails -> must exit 2
(unset BASE_SHA HEAD_SHA; GATE_DIFF_FILE="$tmp" bash "$gate/check-no-float.sh") >/dev/null 2>&1
g=$?
[[ "$g" == 2 ]] && { echo "PASS GATE_DIFF_FILE is a directory -> exit 2"; pass=$((pass+1)); } || { echo "FAIL GATE_DIFF_FILE is a directory -> exit 2 (got $g)"; fail=$((fail+1)); }

echo "== $pass passed / $fail failed =="; [[ "$fail" == 0 ]]
