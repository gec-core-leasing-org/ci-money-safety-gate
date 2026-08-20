# ci-money-safety-gate
Reusable GitHub Actions workflow ที่บล็อก PR ที่ (1) ใส่ float บน money path, (2) แตะไฟล์เงินโดยไม่มี test, (3) มี SQLi pattern + secret. ratchet บน diff เท่านั้น.
Consumers: pilot financial-service, financial-calculator-decimal, financial-accounting-service, agreement-service (ดู .github/workflows/ci.yml ในแต่ละ repo).
Escape: `//money:allow-float reason=...`, PR label `skip-test-gate`.

## Tag policy
ก่อน move tag `v1` ไป commit ใหม่ทุกครั้ง ต้องแปะ immutable snapshot tag `v1.N` (เลขไล่ขึ้น) ไว้ที่ commit เดิมก่อน แล้ว push ทั้งคู่ (`v1.N` แล้วค่อย force-push `v1`) — เพื่อให้ consumer ที่ pin `v1.N` ยังอ้างอิง commit เดิมได้ ไม่ถูกกระทบจากการ move `v1`.

## Known limitations
- `check-no-float.sh` จับเฉพาะ token `float32`/`float64` ตัวอักษรตรงๆ — `strconv.ParseFloat`, `decimal.InexactFloat64()`, `.Float64()` ไม่ถูกจับ (ไม่ใช่ float type แต่แปลง/ดึงค่า float ออกมาได้เหมือนกัน)
- `check-sqli.sh` จับเฉพาะ SQL keyword ตัวพิมพ์ใหญ่ (`SELECT `, `INSERT `, ฯลฯ) ที่อยู่บรรทัดเดียวกับ `fmt.Sprintf` เท่านั้น — SQL ที่ build ข้ามหลายบรรทัด หรือ lowercase keyword จะหลุด
- แนะนำ: workflow ที่เรียก gate ควร `git config core.quotePath false` ก่อน `git diff` เพิ่มด้วย (belt-and-braces คู่กับ quoted-path parsing ใน gate scripts เอง)

## char-test: การเลือก migration ref

char-test สร้าง schema+seed จาก `db-migration-service` โดยเลือก ref ตามลำดับ:

1. `db-migration-ref` ที่ caller ส่งมาใน `ci.yml` (ชนะเสมอ)
2. branch ของ `db-migration-service` ที่ **ชื่อตรงเป๊ะ** กับ branch ของ PR
3. `main`

ผลลัพธ์พิมพ์เป็น `::notice::char-test schema ref = <ref>` ทุกครั้ง

**กติกา:** PR ของ service ที่พึ่ง migration/seed ใหม่ ให้ตั้งชื่อ branch ใน `db-migration-service`
ให้ตรงกับ branch ของ service เป๊ะ ๆ · เมื่อ gate รันด้วย ref ที่ไม่ใช่ main จะขึ้น warning
เตือนว่าต้อง merge `db-migration-service` ก่อน merge PR ของ service

**เมื่อถาม remote ไม่ได้ (auth ล้ม/timeout/เครือข่าย):** ได้ `main` เสมอ พร้อม warning
`ถาม branch ของ db-migration-service ไม่ได้ (token/เครือข่าย) — ใช้ main ตามค่าเดิม` — คนละข้อความ
กับ warning "ยังไม่ merge" ข้างต้น (กรณีนี้คือ resolve ไม่สำเร็จ ไม่ใช่ resolve ได้ ref ที่ไม่ใช่ main)

**event ที่ไม่ใช่ pull_request** (push, schedule, workflow_dispatch โดยไม่ระบุ `db-migration-ref`)
จะได้ `main` เสมอ เพราะ `github.event.pull_request.head.ref` ว่าง — ไม่มีการถาม remote เลย

**`checkout_token`:** ต้องตั้ง secret `checkout_token` ให้มีสิทธิ์ contents:read บน
`db-migration-service` (private repo) มิฉะนั้น `git ls-remote` จะ auth ล้มเงียบ ๆ ทุก PR แล้ว
fallback เป็น `main` โดยไม่มีใครสังเกต (ได้ warning ก็จริง แต่ถ้าไม่มีใครอ่าน log จะไม่รู้ตัว) —
ไม่ตั้ง secret นี้ = gate ใช้ `github.token` แทนซึ่งไม่มีสิทธิ์ข้าม repo

ตรรกะอยู่ใน `gate/resolve-migration-ref.sh` · เทสต์ `gate/tests/test-resolve-migration-ref.sh`
