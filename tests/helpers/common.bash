#!/usr/bin/env bash
# common.bash — sourced via `load 'helpers/common'` at the top of each .bats.
# Establishes:
#   - REPO_ROOT          → absolute path of the repo
#   - bats helper libs   → bats-support, bats-assert, bats-file
#   - Helpful assertions → assert_file_contains_block, assert_sentinel_present

# Resolve REPO_ROOT once per test file (BATS_TEST_DIRNAME is /tests/<category>).
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
export REPO_ROOT

# Load bats helper libraries
load "$REPO_ROOT/tests/bats-support/load"
load "$REPO_ROOT/tests/bats-assert/load"
load "$REPO_ROOT/tests/bats-file/load"

# Common assertions

assert_sentinel_present() {
  local file="$1"
  assert_file_contains "$file" "^# >>> ghostty-tmux-attach@"
  assert_file_contains "$file" "^# <<< ghostty-tmux-attach <<<$"
}

assert_sentinel_absent() {
  local file="$1"
  run grep -c "^# >>> ghostty-tmux-attach" "$file" 2>/dev/null || true
  [ "${output:-0}" = "0" ]
}

assert_one_sentinel_only() {
  local file="$1"
  run bash -c "grep -c '^# >>> ghostty-tmux-attach' '$file'"
  assert_output "1"
}
