#!/usr/bin/env bash
# Fail if an added line builds SQL via fmt.Sprintf (injection risk).
# ข้าม vendor/ ให้สอดคล้องกับ check-no-float / check-needs-test (กัน false positive ตอน go mod vendor)
set -uo pipefail

if [[ -n "${GATE_DIFF_FILE:-}" ]]; then
  [[ -r "$GATE_DIFF_FILE" ]] || { echo "FATAL: diff file not readable: $GATE_DIFF_FILE" >&2; exit 2; }
else
  [[ -n "${BASE_SHA:-}" && -n "${HEAD_SHA:-}" ]] || { echo "FATAL: set BASE_SHA and HEAD_SHA" >&2; exit 2; }
  : "${BASE_SHA:?set BASE_SHA}" "${HEAD_SHA:?set HEAD_SHA}"
fi

get_diff(){ if [[ -n "${GATE_DIFF_FILE:-}" ]]; then cat "$GATE_DIFF_FILE";
  else git diff --unified=0 "${BASE_SHA:?}...${HEAD_SHA:?}"; fi; }

sink='(\.Raw\(|\.Exec\(|\.Query\(|\.QueryRow\(|ORDER BY|SELECT |INSERT |UPDATE |DELETE )'
violation=0; skip=0
while IFS= read -r line; do
  if [[ "$line" == +++\ b/* ]]; then f="${line#+++ b/}"
    if [[ "$f" == vendor/* || "$f" == */vendor/* ]]; then skip=1; else skip=0; fi
  elif [[ "$skip" == 0 && "$line" == +* && "$line" != +++* ]]; then
    if grep -Eq 'fmt\.Sprintf' <<<"$line" && grep -Eq "$sink" <<<"$line"; then
      grep -q 'sqli:allow' <<<"$line" || { echo "❌ SQLi risk: ${line}"; violation=1; }
    fi
  fi
done < <(get_diff)
exit $violation
