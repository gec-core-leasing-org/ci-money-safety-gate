# ci-money-safety-gate
Reusable GitHub Actions workflow ที่บล็อก PR ที่ (1) ใส่ float บน money path, (2) แตะไฟล์เงินโดยไม่มี test, (3) มี SQLi pattern + secret. ratchet บน diff เท่านั้น.
Consumers: pilot financial-service, financial-calculator-decimal (ดู .github/workflows/ci.yml ในแต่ละ repo).
Escape: `//money:allow-float reason=...`, PR label `skip-test-gate`.

## Known limitations
- `check-no-float.sh` จับเฉพาะ token `float32`/`float64` ตัวอักษรตรงๆ — `strconv.ParseFloat`, `decimal.InexactFloat64()`, `.Float64()` ไม่ถูกจับ (ไม่ใช่ float type แต่แปลง/ดึงค่า float ออกมาได้เหมือนกัน)
- `check-sqli.sh` จับเฉพาะ SQL keyword ตัวพิมพ์ใหญ่ (`SELECT `, `INSERT `, ฯลฯ) ที่อยู่บรรทัดเดียวกับ `fmt.Sprintf` เท่านั้น — SQL ที่ build ข้ามหลายบรรทัด หรือ lowercase keyword จะหลุด
- แนะนำ: workflow ที่เรียก gate ควร `git config core.quotePath false` ก่อน `git diff` เพิ่มด้วย (belt-and-braces คู่กับ quoted-path parsing ใน gate scripts เอง)