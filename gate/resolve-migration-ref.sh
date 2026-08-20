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
# stdout: ref ที่เลือก (บรรทัดเดียว)
# stderr: diagnostic เท่านั้น (error จาก ls-remote / sha ของ branch ที่เลือกไว้ไล่ย้อนได้)
# exit:   0 = resolve ปกติ (รวมกรณี remote ตอบสำเร็จแต่ไม่มี branch คู่ — ยังคง fallback main)
#         3 = ถาม remote ไม่ได้ (ล้ม/timeout) จึง fallback main (workflow ควรเตือน)
set -uo pipefail

input="${INPUT_REF:-}"
cand="${CANDIDATE_REF:-}"
repo="${REPO_URL:-https://github.com/gec-core-leasing-org/db-migration-service}"

# 1) caller ระบุมาเอง — ไม่ต้องถาม remote
if [[ -n "$input" ]]; then printf '%s\n' "$input"; exit 0; fi

# 2) ไม่ใช่ PR (push/schedule) หรือ candidate คือ main อยู่แล้ว
if [[ -z "$cand" || "$cand" == "main" ]]; then printf '%s\n' main; exit 0; fi

# 3) ถามรายชื่อ branch จาก remote (หรือแฟ้มจำลองตอนเทสต์)
#
# ห้ามฝัง token ใน URL (x-access-token:$TOKEN@...) — actions/checkout ทิ้ง
# `http.https://github.com/.extraheader` ไว้ใน git config ของ workspace ที่ checkout
# แล้ว header นั้นทับ credential ที่ฝังใน URL จน auth ล้ม (พิสูจน์ซ้ำได้ 100% ในเครื่อง)
#
# ทางแก้รอบแรก (ตั้ง `-c http.https://github.com/.extraheader=...` ให้ "ทับ" ของเดิม) ไม่พอ:
# `http.extraHeader` เป็น multi-valued config — ค่าจาก `-c` ถูก**เพิ่ม**เข้าไปในลิสต์ ไม่ได้
# แทนที่ค่าที่มาจาก local git config ของ repo ที่ checkout ไว้ ผลคือ git ส่ง Authorization
# header สองใบ แล้วโดน GitHub ปฏิเสธ (`remote: Duplicate header: "Authorization"`, HTTP 400)
# — พิสูจน์จาก log จริงบน CI (master-service PR #70, run 32349691918)
#
# ทางแก้ที่ถูกต้อง: รัน `git ls-remote` จาก scratch dir ที่ไม่ใช่ working tree ของ repo ที่
# checkout ไว้เลย ไม่มี local `.git/config` ให้ค้นพบ จึงไม่มี extraheader เดิมให้ชนกับของเรา
#
# ส่ง header ผ่าน env (GIT_CONFIG_COUNT/KEY/VALUE) แทน `-c` ทาง argv — `-c` โผล่ใน
# `/proc/<pid>/cmdline` ซึ่งอ่านได้จาก process อื่นบนเครื่องที่ใช้ร่วมกัน (self-hosted runner)
if [[ -n "${GATE_LSREMOTE_FILE:-}" ]]; then
  if [[ ! -f "$GATE_LSREMOTE_FILE" ]]; then printf '%s\n' main; exit 3; fi
  branches="$(cat "$GATE_LSREMOTE_FILE")"
  rc=0
else
  errfile="$(mktemp)"
  scratch="$(mktemp -d)"
  trap 'rm -f "$errfile"; rm -rf "$scratch"' EXIT
  if [[ -n "${GATE_TOKEN:-}" ]]; then
    hdr="AUTHORIZATION: basic $(printf 'x-access-token:%s' "$GATE_TOKEN" | base64 | tr -d '\n')"
    branches="$(cd "$scratch" && GIT_TERMINAL_PROMPT=0 GIT_CONFIG_COUNT=1 \
      GIT_CONFIG_KEY_0="http.https://github.com/.extraheader" \
      GIT_CONFIG_VALUE_0="$hdr" \
      timeout 30 git ls-remote --heads "$repo" 2>"$errfile")"
    rc=$?
  else
    branches="$(cd "$scratch" && GIT_TERMINAL_PROMPT=0 timeout 30 git ls-remote --heads "$repo" 2>"$errfile")"
    rc=$?
  fi
  if [[ "$rc" -ne 0 ]]; then
    # timeout(1) คืน 124 เมื่อ ls-remote ค้างเกิน 30s — ถือเป็นเส้นทางเดียวกับ ls-remote ล้ม
    if [[ "$rc" -eq 124 ]]; then
      printf 'resolve-migration-ref: git ls-remote timed out after 30s\n' >&2
    fi
    # เก็บ stderr จริงไว้แล้ว — ห้ามกลืนทิ้ง (2>/dev/null เดิมทำให้เดา root cause ไม่ได้)
    # พิมพ์ทาง stderr ของสคริปต์เท่านั้น (ห้ามปนกับ stdout ซึ่งเป็นค่า ref)
    sed 's/^/resolve-migration-ref: /' "$errfile" >&2
    printf '%s\n' main; exit 3
  fi
fi

# remote ตอบสำเร็จ (rc=0) แต่ไม่มี branch เลย — ไม่ใช่ "ถาม remote ไม่ได้" จึง exit 0
if [[ -z "$branches" ]]; then printf '%s\n' main; exit 0; fi

# 4) เทียบชื่อแบบ literal ทั้งสตริง (awk เทียบ field ตรง ๆ ไม่ใช่ regex)
if awk -v want="refs/heads/$cand" '$2 == want { found = 1 } END { exit !found }' <<<"$branches"; then
  sha="$(awk -v want="refs/heads/$cand" '$2 == want { print $1; exit }' <<<"$branches")"
  printf 'resolve-migration-ref: ref=%s sha=%s\n' "$cand" "${sha:0:7}" >&2
  printf '%s\n' "$cand"; exit 0
fi

printf '%s\n' main; exit 0
