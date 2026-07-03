#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
rc=0
for t in "$here"/test-*.sh; do
  echo "--- $t"
  bash "$t" || rc=1
done
exit $rc
