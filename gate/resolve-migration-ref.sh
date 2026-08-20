#!/usr/bin/env bash
# เลือก ref ของ db-migration-service ที่ char-test จะใช้สร้าง schema+seed
#
# ลำดับ: caller ระบุเอง > branch ที่ชื่อตรงกับ branch ของ PR > main
#
# env:
#   INPUT_REF           ค่า db-migration-ref ที่ caller ส่ง (ว่าง = ให้ resolve เอง)
#   CANDIDATE_REF       ชื่อ branch ของ PR (github.event.pull_request.head.ref) — ว่างได้
#   REPO_URL            default https://github.com/gec-core-leasing-org/db-migration-service
#   GATE_TOKEN          token สำหรับ ls-remote (db-migration-service เป็น private)
#   GATE_LSREMOTE_FILE  เทสต์เท่านั้น: ไฟล์ที่มีรูปแบบเดียวกับผลลัพธ์ git ls-remote --heads
#
# stdout: ref ที่เลือก
# exit:   0 = resolve ปกติ · 3 = ถาม remote ไม่ได้ จึง fallback main (workflow ควรเตือน)
set -uo pipefail

input="${INPUT_REF:-}"
cand="${CANDIDATE_REF:-}"
repo="${REPO_URL:-https://github.com/gec-core-leasing-org/db-migration-service}"

# 1) caller ระบุมาเอง — ไม่ต้องถาม remote
if [[ -n "$input" ]]; then echo "$input"; exit 0; fi

# 2) ไม่ใช่ PR (push/schedule) หรือ candidate คือ main อยู่แล้ว
if [[ -z "$cand" || "$cand" == "main" ]]; then echo main; exit 0; fi

# 3) ถามรายชื่อ branch จาก remote (หรือแฟ้มจำลองตอนเทสต์)
if [[ -n "${GATE_LSREMOTE_FILE:-}" ]]; then
  if [[ ! -f "$GATE_LSREMOTE_FILE" ]]; then echo main; exit 3; fi
  branches="$(cat "$GATE_LSREMOTE_FILE")"
else
  url="$repo"
  if [[ -n "${GATE_TOKEN:-}" ]]; then url="https://x-access-token:${GATE_TOKEN}@${repo#https://}"; fi
  if ! branches="$(git ls-remote --heads "$url" 2>/dev/null)"; then echo main; exit 3; fi
fi
if [[ -z "$branches" ]]; then echo main; exit 3; fi

# 4) เทียบชื่อแบบ literal ทั้งสตริง (awk เทียบ field ตรง ๆ ไม่ใช่ regex)
if awk -v want="refs/heads/$cand" '$2 == want { found = 1 } END { exit !found }' <<<"$branches"; then
  echo "$cand"; exit 0
fi

echo main; exit 0
