#!/usr/bin/env bash
set -e
here="$(cd "$(dirname "$0")" && pwd)"
for t in "$here"/test-*.sh; do echo "--- $t"; bash "$t"; done
