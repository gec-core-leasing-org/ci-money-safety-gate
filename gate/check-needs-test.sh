#!/usr/bin/env bash
# Fail if a money-path *.go is changed without a *_test.go in the same dir.
# bash 3.2-compatible (macOS) — no mapfile / declare -A
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
paths_file="${GATE_MONEY_PATHS:-$here/money-paths.txt}"
[[ "${GATE_SKIP_TEST:-0}" == "1" ]] && exit 0

[[ -f "$paths_file" && -r "$paths_file" ]] || { echo "FATAL: money-paths file not readable: $paths_file" >&2; exit 2; }
# materialize the file list BEFORE use — a git failure inside $(...) doesn't
# stop the script; the loops would see empty input (silent pass)
if [[ -n "${GATE_FILES_FILE:-}" ]]; then
  [[ -f "$GATE_FILES_FILE" && -r "$GATE_FILES_FILE" ]] || { echo "FATAL: files list not readable: $GATE_FILES_FILE" >&2; exit 2; }
  src="$GATE_FILES_FILE"
else
  [[ -n "${BASE_SHA:-}" && -n "${HEAD_SHA:-}" ]] || { echo "FATAL: set BASE_SHA and HEAD_SHA" >&2; exit 2; }
  : "${BASE_SHA:?set BASE_SHA}" "${HEAD_SHA:?set HEAD_SHA}"
  src="$(mktemp)"; trap 'rm -f "$src"' EXIT
  git diff --name-only "${BASE_SHA}...${HEAD_SHA}" >"$src" || { echo "FATAL: git diff failed (unfetched SHA? shallow clone?)" >&2; exit 2; }
fi

in_money(){ local f="$1" g
  [[ "$f" == vendor/* || "$f" == */vendor/* ]] && return 1
  while IFS= read -r g; do [[ -z "$g" ]] && continue;
  [[ "$f" == *"$g"* ]] && return 0; done <"$paths_file"; return 1; }

files="$(cat "$src")"
# dirs ที่มี *_test.go ถูกแตะ (newline-delimited lookup แทน assoc array)
# strip trailing TAB and one leading/trailing '"' — git quotes paths with
# non-ASCII/special chars (core.quotePath), so raw lines from get_files
# may be wrapped in quotes; the .go-suffix checks below must run AFTER this.
test_dirs="$(while IFS= read -r f; do f="${f%$'\t'}"; f="${f#\"}"; f="${f%\"}"; if [[ "$f" == *_test.go ]]; then dirname "$f"; fi; done <<<"$files")"

violation=0
while IFS= read -r f; do
  f="${f%$'\t'}"; f="${f#\"}"; f="${f%\"}"
  [[ "$f" == *.go && "$f" != *_test.go ]] || continue
  in_money "$f" || continue
  d="$(dirname "$f")"
  printf '%s\n' "$test_dirs" | grep -qxF "$d" || { echo "❌ money file without sibling test: $f"; violation=1; }
done <<<"$files"
exit $violation
