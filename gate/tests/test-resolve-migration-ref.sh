#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; gate="$here/.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0

# แฟ้มจำลองผลลัพธ์ `git ls-remote --heads` (sha<TAB>refs/heads/<name>)
printf '%s\trefs/heads/main\n%s\trefs/heads/feature/app-loan-executed\n%s\trefs/heads/feature/foo-bar\n%s\trefs/heads/fix/a.b+c\n' \
  aaaa1111 bbbb2222 cccc3333 dddd4444 >"$tmp/branches.txt"

# $1=ชื่อเคส $2=INPUT_REF $3=CANDIDATE_REF $4=ไฟล์ ls-remote $5=stdout ที่ต้องได้ $6=exit ที่ต้องได้
# ห้ามห่อด้วย subshell — ตัวนับ pass/fail ต้องสะสมใน shell เดียวกัน ไม่งั้นเทสต์เขียวหลอก
run(){
  local out g
  out="$(INPUT_REF="$2" CANDIDATE_REF="$3" GATE_LSREMOTE_FILE="$4" bash "$gate/resolve-migration-ref.sh" 2>/dev/null)"; g=$?
  if [[ "$out" == "$5" && "$g" == "$6" ]]; then echo "PASS $1"; pass=$((pass+1));
  else echo "FAIL $1 (got '$out' exit $g want '$5' exit $6)"; fail=$((fail+1)); fi
}

run "caller ระบุ ref เอง -> ชนะเสมอ"            "feature/pinned" "feature/app-loan-executed" "$tmp/branches.txt"   "feature/pinned"            0
run "branch ชื่อตรงกัน -> ใช้ branch นั้น"        ""               "feature/app-loan-executed" "$tmp/branches.txt"   "feature/app-loan-executed" 0
run "ไม่มี branch คู่ -> main"                   ""               "feature/app-not-there"     "$tmp/branches.txt"   "main"                      0
run "ไม่ใช่ PR (head_ref ว่าง) -> main"          ""               ""                          "$tmp/branches.txt"   "main"                      0
run "ls-remote ล้ม -> main + exit 3"            ""               "feature/app-loan-executed" "$tmp/nonexistent.txt" "main"                     3
run "prefix ใกล้กันแต่ไม่เท่ากัน -> main"         ""               "feature/foo"               "$tmp/branches.txt"   "main"                      0
run "ชื่อ branch มี . และ + -> match แบบ literal" ""               "fix/a.b+c"                 "$tmp/branches.txt"   "fix/a.b+c"                 0
# "fix/aXbc" จะ match ถ้าเผลอเอา "fix/a.b+c" ไปใช้เป็น regex (. = อักขระใดก็ได้, b+ = b หนึ่งตัวขึ้นไป)
run "สตริงที่ match ได้ถ้าใช้ regex -> ต้องเป็น main" ""            "fix/aXbc"                  "$tmp/branches.txt"   "main"                      0

echo "== $pass passed / $fail failed =="; [[ "$fail" == 0 ]]
