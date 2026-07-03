# ci-money-safety-gate
Reusable GitHub Actions workflow ที่บล็อก PR ที่ (1) ใส่ float บน money path, (2) แตะไฟล์เงินโดยไม่มี test, (3) มี SQLi pattern + secret. ratchet บน diff เท่านั้น.
Consumers: pilot financial-service, financial-calculator-decimal (ดู .github/workflows/ci.yml ในแต่ละ repo).
Escape: `//money:allow-float reason=...`, PR label `skip-test-gate`.