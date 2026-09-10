#!/usr/bin/env bash
# แดงถ้ามี access token ฝังเป็น literal อยู่ในไฟล์ที่ track ไว้
#
# ทำไมสแกนทั้ง tree ไม่ใช่แค่ diff (ต่างจาก check-no-float / check-sqli):
# gitleaks ใน money-safety-gate.yml รันแบบ ratchet (--log-opts=BASE..HEAD) จึงเห็น
# เฉพาะ commit ใหม่ใน PR — token ที่ commit ไว้ก่อนหน้าจึงรอดมาได้เป็นปี
# (กวาด 2026-09-10 เจอ 5 token ใน 11 repo ตัวหนึ่งยังใช้ได้และมี scope admin:org)
# ด่านนี้ปิดรูนั้น: PR ไหนก็ตามที่ยังมี token ค้างใน tree จะแดง
#
# ข้าม vendor/ ให้สอดคล้องกับ check-no-float / check-sqli
# escape hatch: ใส่ secret:allow ในบรรทัดนั้น (เช่นตัวอย่างในเอกสาร)
set -uo pipefail

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "FATAL: ไม่ได้อยู่ใน git repo — สแกนไม่ได้" >&2; exit 2; }

# ต้องเป็น format ที่ระบุตัวได้จริงเท่านั้น กัน false positive จาก string สุ่ม
#   ghp_ + 36        classic PAT
#   glpat- + 20      GitLab PAT
#   github_pat_ + 59 fine-grained PAT
#   gho_/ghu_/ghs_/ghr_ + 36  OAuth / user / server / refresh token
pattern='(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36}|glpat-[A-Za-z0-9_-]{20}|github_pat_[A-Za-z0-9_]{59,}'

violation=0
while IFS= read -r hit; do
  f="${hit%%:*}"
  case "$f" in vendor/*|*/vendor/*) continue ;; esac
  grep -q 'secret:allow' <<<"$hit" && continue
  # ตัดค่า token ออกจาก log ไม่งั้น CI log กลายเป็นที่รั่วเสียเอง
  echo "❌ พบ access token ฝังไว้: ${hit%%:*}:$(cut -d: -f2 <<<"$hit") (ค่าถูกตัดออกจาก log)"
  violation=1
done < <(git grep -nEI "$pattern" -- . 2>/dev/null)

[[ "$violation" == 1 ]] && echo "→ ย้ายไปใช้ ARG/env (ดู base-images/Dockerfile ที่ใช้ ARG CORE_SECRET) แล้ว revoke token ตัวนั้น"
exit $violation
