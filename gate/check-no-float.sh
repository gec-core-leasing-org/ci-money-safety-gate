#!/usr/bin/env bash
# Fail (exit 1) if a PR adds float32/float64 inside a money path.
# Offline-testable: set GATE_DIFF_FILE to a unified-diff file.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
paths_file="${GATE_MONEY_PATHS:-$here/money-paths.txt}"

[[ -r "$paths_file" ]] || { echo "FATAL: money-paths file not readable: $paths_file" >&2; exit 2; }
if [[ -n "${GATE_DIFF_FILE:-}" ]]; then
  [[ -r "$GATE_DIFF_FILE" ]] || { echo "FATAL: diff file not readable: $GATE_DIFF_FILE" >&2; exit 2; }
else
  [[ -n "${BASE_SHA:-}" && -n "${HEAD_SHA:-}" ]] || { echo "FATAL: set BASE_SHA and HEAD_SHA" >&2; exit 2; }
  : "${BASE_SHA:?set BASE_SHA}" "${HEAD_SHA:?set HEAD_SHA}"
fi

get_diff(){ if [[ -n "${GATE_DIFF_FILE:-}" ]]; then cat "$GATE_DIFF_FILE";
  else git diff --unified=0 "${BASE_SHA:?set BASE_SHA}...${HEAD_SHA:?set HEAD_SHA}"; fi; }

in_money(){ local f="$1" g
  [[ "$f" == vendor/* || "$f" == */vendor/* ]] && return 1
  while IFS= read -r g; do [[ -z "$g" ]] && continue;
  [[ "$f" == *"$g"* ]] && return 0; done <"$paths_file"; return 1; }

violation=0; cur=0
while IFS= read -r line; do
  if [[ "$line" == +++\ b/* ]]; then
    f="${line#+++ b/}"; f="${f%$'\t'}"; f="${f%\"}"
    in_money "$f" && cur=1 || cur=0
  elif [[ "$line" == '+++ "b/'* ]]; then
    f="${line#+++ \"b/}"; f="${f%$'\t'}"; f="${f%\"}"
    in_money "$f" && cur=1 || cur=0
  elif [[ "$line" == +++\ * ]]; then
    cur=0
  elif [[ "$cur" == 1 && "$line" == +* && "$line" != +++* ]]; then
    if grep -Eq '\bfloat(32|64)\b' <<<"$line" && ! grep -q 'money:allow-float reason=' <<<"$line"; then
      echo "❌ float on money path: ${line}"; violation=1
    fi
  fi
done < <(get_diff)
exit $violation
