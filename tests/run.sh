#!/usr/bin/env bash
# Run bats tests in a given category (default: all).
set -eu
REPO=$(cd "$(dirname "$0")/.." && pwd)
BATS="$REPO/tests/bats/bin/bats"

category="${1:-all}"
case "$category" in
  unit|integration|race|e2e)
    exec "$BATS" --print-output-on-failure --recursive "$REPO/tests/$category"
    ;;
  all)
    exec "$BATS" --print-output-on-failure --recursive \
      "$REPO/tests/unit" "$REPO/tests/integration" "$REPO/tests/race" "$REPO/tests/e2e"
    ;;
  *)
    echo "Usage: $0 [unit|integration|race|e2e|all]" >&2
    exit 2
    ;;
esac
