#!/bin/bash
#
# The one command. Everything that can be verified without a human looking at a screen.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FAILED=0

echo "==> build"
if ! swift build 2>&1 | xcsift; then FAILED=1; fi

echo "==> tests"
if ! swift test 2>&1 | xcsift; then FAILED=1; fi

if command -v swiftlint >/dev/null 2>&1 && [ -f .swiftlint.yml ]; then
    echo "==> swiftlint"
    if ! swiftlint lint --quiet --strict; then FAILED=1; fi
fi

echo
if [ "$FAILED" -eq 0 ]; then echo "PASS"; else echo "FAIL"; fi
exit "$FAILED"
