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

# M-3: remote ตอบสำเร็จ (rc=0) แต่ไม่มี branch เลย ต้องแยกจาก "ถาม remote ไม่ได้"
: >"$tmp/empty-branches.txt"
run "remote สำเร็จแต่ไม่มี branch เลย -> main + exit 0 (ไม่ใช่ ls-remote ล้ม)" "" "feature/app-loan-executed" "$tmp/empty-branches.txt" "main" 0

# ls-remote จริงที่ auth ไม่ผ่าน (repo private ของจริง, ไม่ตั้ง GATE_TOKEN, ไม่ตั้ง GATE_LSREMOTE_FILE)
# ต้องทนทั้งสองกรณีของเครื่องที่รันเทสต์: มีเน็ต (repo private -> auth ล้ม) หรือไม่มีเน็ต
# (resolve/connect ล้ม) — ทั้งสองทางต้องได้ stdout=main, exit=3, และมี diagnostic โผล่ทาง stderr
# (ก่อนหน้านี้ 2>/dev/null กลืน stderr ทิ้งไปหมด ทำให้เดา root cause ไม่ได้)
#
# `env -i` + HOME ว่าง + GIT_CONFIG_NOSYSTEM=1: ตัด credential helper แวดล้อม (เช่น
# `gh auth` ของเครื่อง dev) ออกก่อน ไม่งั้นเครื่องที่ล็อกอิน gh ไว้แล้วจะ ls-remote ผ่านจริง
# (มี access เข้า org) ทำให้เคสนี้ไม่ deterministic — พิสูจน์แล้วว่าไม่มี ambient credential
# ก็ยังคง auth ล้มแบบเดียวกับที่ยืนยันบน gec-dev-app (SSH probe รอบก่อน): "could not read
# Username ... terminal prompts disabled"
stderr_file="$tmp/real-remote.stderr"
homeless="$tmp/no-ambient-creds-home"; mkdir -p "$homeless"
out="$(env -i PATH="$PATH" HOME="$homeless" GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 \
  INPUT_REF="" CANDIDATE_REF="feature/app-loan-executed" GATE_LSREMOTE_FILE="" \
  REPO_URL="https://github.com/gec-core-leasing-org/db-migration-service" \
  bash "$gate/resolve-migration-ref.sh" 2>"$stderr_file")"
g=$?
if [[ "$out" == "main" && "$g" == "3" && -s "$stderr_file" ]]; then
  echo "PASS ls-remote จริงล้ม (repo private, ไม่มี token) -> main + exit 3 + diagnostic บน stderr"
  pass=$((pass+1))
else
  echo "FAIL ls-remote จริงล้ม -> main + exit 3 + diagnostic บน stderr (got '$out' exit $g, stderr size $(wc -c <"$stderr_file"))"
  fail=$((fail+1))
fi

# I-2: ls-remote สำเร็จในสภาพแวดล้อมที่มี http.extraheader ค้าง (จำลองสิ่งที่ actions/checkout
# ทิ้งไว้ใน local git config ของ workspace) — คลาสบั๊กนี้หลุดมาแล้ว 2 รอบโดย self-test เขียว
# เพราะเทสต์เดิมครอบแต่ขาที่ ls-remote "ล้ม" ไม่เคยครอบขาที่ "สำเร็จ + มี stale header ค้าง"
# ต้องการเน็ต (repo สาธารณะจริง) — ถ้าเครื่อง dev ไม่มีเน็ตให้ SKIP ไม่นับ fail, บน CI ที่มีเน็ต
# ต้องรันจริง
net_probe="$tmp/net-probe.log"
if timeout 8 git ls-remote --heads https://github.com/actions/checkout >/dev/null 2>"$net_probe"; then
  repo_dir="$tmp/stale-extraheader-repo"; mkdir -p "$repo_dir"
  ( cd "$repo_dir" && git init -q && \
    git config --local http.https://github.com/.extraheader \
      "AUTHORIZATION: basic $(printf 'x-access-token:%s' bogus | base64 | tr -d '\n')" )
  out="$(cd "$repo_dir" && INPUT_REF="" CANDIDATE_REF="releases/v3" GATE_LSREMOTE_FILE="" \
    REPO_URL="https://github.com/actions/checkout" GIT_TERMINAL_PROMPT=0 \
    bash "$gate/resolve-migration-ref.sh" 2>"$tmp/stale-extraheader.stderr")"
  g=$?
  if [[ "$out" == "releases/v3" && "$g" == "0" ]]; then
    echo "PASS ls-remote สำเร็จแม้มี stale http.extraheader ค้างใน local git config (จำลอง actions/checkout)"
    pass=$((pass+1))
  else
    echo "FAIL ls-remote ควรสำเร็จแม้มี stale extraheader ค้าง (got '$out' exit $g)"
    fail=$((fail+1))
  fi
else
  echo "SKIP ls-remote สำเร็จแม้มี stale extraheader ค้าง (ไม่มีเน็ตบนเครื่องนี้ — ข้ามเทสต์นี้)"
fi

echo "== $pass passed / $fail failed =="; [[ "$fail" == 0 ]]
