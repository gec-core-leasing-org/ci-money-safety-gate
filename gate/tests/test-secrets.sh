#!/usr/bin/env bash
# check-secrets.sh สแกนไฟล์ที่ track ไว้ทั้ง tree ไม่ใช่แค่ diff — จึงต้อง
# สร้าง git repo ชั่วคราวต่อเคส (ต่างจาก test อื่นที่ป้อน diff ผ่าน GATE_DIFF_FILE)
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; gate="$here/.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0

# สร้าง repo ชั่วคราวที่มีไฟล์ตามที่ระบุ แล้วรัน check-secrets.sh ในนั้น
# ใช้ชื่อไฟล์:เนื้อหา คั่นด้วย = (เนื้อหาห้ามมี =)
mk(){ local d="$tmp/$1"; shift; mkdir -p "$d"; git -C "$d" init -q
  while [[ $# -gt 0 ]]; do printf '%s\n' "${1#*=}" >"$d/${1%%=*}"; shift; done
  git -C "$d" add -A; echo "$d"; }

run(){ ( cd "$2" && bash "$gate/check-secrets.sh" ) >/dev/null 2>&1; local g=$?
  [[ "$g" == "$3" ]] && { echo "PASS $1"; pass=$((pass+1)); } || { echo "FAIL $1 (exit $g want $3)"; fail=$((fail+1)); }; }

# ตัวอย่าง token เป็นของปลอมที่ยาวตาม format จริง — ต้องยาวพอให้ pattern จับได้
GHP="ghp_$(printf 'A%.0s' {1..36})"
GLPAT="glpat-$(printf 'B%.0s' {1..20})"
PATNEW="github_pat_$(printf 'C%.0s' {1..60})"

run "GitHub PAT ใน Dockerfile -> fail" "$(mk ghp "Dockerfile=RUN git config url.\"https://$GHP@github.com/\".insteadOf x")" 1
run "GitLab PAT ใน Jenkinsfile -> fail" "$(mk glpat "Jenkinsfile=TOKEN = 'oauth2:$GLPAT'")" 1
run "fine-grained PAT ใน build.sh -> fail" "$(mk fgpat "build.sh=pw=\"$PATNEW\"")" 1
run "ARG CORE_SECRET -> pass" "$(mk argok "Dockerfile=RUN git config url.\"https://\${CORE_SECRET}@github.com/\".insteadOf x")" 0
run "env var -> pass" "$(mk envok "build.sh=pw=\"\${GITHUB_TOKEN:?required}\"")" 0
run "ไม่มีอะไรเลย -> pass" "$(mk empty "README.md=hello")" 0

# vendor/ ต้องข้าม ให้สอดคล้องกับ check-no-float / check-sqli
d="$(mk vend "README.md=x")"; mkdir -p "$d/vendor/x"
printf '%s\n' "tok=$GHP" >"$d/vendor/x/f.go"; git -C "$d" add -A
run "token ใน vendor/ -> pass (ยกเว้น vendor)" "$d" 0

# escape hatch สำหรับเคสที่จงใจ เช่นตัวอย่างในเอกสาร
run "บรรทัดที่มี secret:allow -> pass" "$(mk allow "README.md=ตัวอย่าง: $GHP  <!-- secret:allow -->")" 0

# ไฟล์ที่มีอยู่แต่ไม่ได้ track ต้องไม่ถูกสแกน (ผลลัพธ์ต้องเท่ากับที่ commit จริง)
d="$(mk untracked "README.md=x")"; printf '%s\n' "tok=$GHP" >"$d/scratch.txt"
run "ไฟล์ที่ไม่ได้ track -> pass" "$d" 0

# fail-closed: ไม่ได้อยู่ใน git repo ต้อง exit 2 ไม่ใช่ 0
run "ไม่ใช่ git repo -> exit 2" "$(mkdir -p "$tmp/nogit" && echo "$tmp/nogit")" 2

echo "== $pass passed / $fail failed =="; [[ "$fail" == 0 ]]
