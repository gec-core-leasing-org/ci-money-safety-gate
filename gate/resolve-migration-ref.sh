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
#
# ห้ามฝัง token ใน URL (x-access-token:$TOKEN@...) — actions/checkout ทิ้ง
# `http.https://github.com/.extraheader` ไว้ใน git config ของ workspace ที่ checkout
# แล้ว header นั้นทับ credential ที่ฝังใน URL จน auth ล้ม (พิสูจน์ซ้ำได้ 100% ในเครื่อง)
# ทางแก้: ตั้ง extraheader คีย์เดียวกันเป๊ะ ๆ ผ่าน `-c` ให้ทับของเดิมแทน
if [[ -n "${GATE_LSREMOTE_FILE:-}" ]]; then
  if [[ ! -f "$GATE_LSREMOTE_FILE" ]]; then echo main; exit 3; fi
  branches="$(cat "$GATE_LSREMOTE_FILE")"
else
  errfile="$(mktemp)"
  trap 'rm -f "$errfile"' EXIT
  if [[ -n "${GATE_TOKEN:-}" ]]; then
    hdr="AUTHORIZATION: basic $(printf 'x-access-token:%s' "$GATE_TOKEN" | base64 | tr -d '\n')"
    branches="$(git -c "http.https://github.com/.extraheader=$hdr" ls-remote --heads "$repo" 2>"$errfile")"
    rc=$?
  else
    branches="$(git ls-remote --heads "$repo" 2>"$errfile")"
    rc=$?
  fi
  if [[ "$rc" -ne 0 ]]; then
    # เก็บ stderr จริงไว้แล้ว — ห้ามกลืนทิ้ง (2>/dev/null เดิมทำให้เดา root cause ไม่ได้)
    # พิมพ์ทาง stderr ของสคริปต์เท่านั้น (ห้ามปนกับ stdout ซึ่งเป็นค่า ref)
    sed 's/^/resolve-migration-ref: /' "$errfile" >&2
    echo main; exit 3
  fi
fi
if [[ -z "$branches" ]]; then echo main; exit 3; fi

# 4) เทียบชื่อแบบ literal ทั้งสตริง (awk เทียบ field ตรง ๆ ไม่ใช่ regex)
if awk -v want="refs/heads/$cand" '$2 == want { found = 1 } END { exit !found }' <<<"$branches"; then
  echo "$cand"; exit 0
fi

echo main; exit 0
