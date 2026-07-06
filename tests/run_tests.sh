#!/usr/bin/env bash
# Test runner: executes every tests/test_*.sh in its own bash process.
# Plain bash asserts are used (see helpers.sh) so the suite runs without
# bats-core installed.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

failed=0
total=0
for t in "$TESTS_DIR"/test_*.sh; do
  total=$((total + 1))
  if ! bash "$t"; then
    failed=$((failed + 1))
  fi
  echo
done

if [ "$failed" -eq 0 ]; then
  printf 'All %d test files passed.\n' "$total"
else
  printf '%d of %d test files FAILED.\n' "$failed" "$total" >&2
  exit 1
fi
