#!/usr/bin/env bats
# Tests for lib/patches.sh — sentinel-block I/O + set-union.

load '../helpers/common'
load '../helpers/sandbox'

setup() {
  sandbox_setup
  # shellcheck source=/dev/null
  source "$REPO_ROOT/lib/patches.sh"
  F="$HOME/test.conf"
  touch "$F"
}

teardown() {
  sandbox_teardown
}

# --- gta_patch_write inserts sentinel block ---

@test "gta_patch_write inserts sentinel header, body, footer" {
  gta_patch_write "$F" "0.1.0" "set -g foo bar"
  assert_file_contains "$F" "^# >>> ghostty-tmux-attach@0.1.0"
  assert_file_contains "$F" "^set -g foo bar"
  assert_file_contains "$F" "^# <<< ghostty-tmux-attach <<<$"
}

@test "gta_patch_write header includes sha=<hash>" {
  gta_patch_write "$F" "0.1.0" "set -g foo bar"
  # bats-file uses BRE grep, so `+` must be `\+`.
  assert_file_contains "$F" "^# >>> ghostty-tmux-attach@0.1.0 sha=[a-f0-9]\+ >>>$"
}

# --- gta_patch_read returns body ---

@test "gta_patch_read returns exact body" {
  gta_patch_write "$F" "0.1.0" "line1
line2
set -g foo bar"
  run gta_patch_read "$F"
  assert_success
  assert_output "line1
line2
set -g foo bar"
}

@test "gta_patch_read returns empty when no sentinel" {
  echo "user content only" > "$F"
  run gta_patch_read "$F"
  assert_success
  assert_output ""
}

# --- gta_patch_write replaces existing block (no duplicates) ---

@test "gta_patch_write replaces existing block (no duplicates)" {
  gta_patch_write "$F" "0.1.0" "old body"
  gta_patch_write "$F" "0.2.0" "new body"
  # Exactly one sentinel header
  run bash -c "grep -c '^# >>> ghostty-tmux-attach' '$F'"
  assert_output "1"
  assert_file_contains "$F" "new body"
  refute [ "$(grep -c 'old body' "$F")" -ne "0" ]
}

@test "gta_patch_write updates version in header on replace" {
  gta_patch_write "$F" "0.1.0" "x"
  gta_patch_write "$F" "0.2.0" "y"
  assert_file_contains "$F" "@0.2.0"
  assert_file_not_contains "$F" "@0.1.0"
}

# --- gta_patch_remove ---

@test "gta_patch_remove strips the sentinel block" {
  gta_patch_write "$F" "0.1.0" "block body"
  gta_patch_remove "$F"
  assert_file_not_contains "$F" ">>> ghostty-tmux-attach"
  assert_file_not_contains "$F" "<<< ghostty-tmux-attach"
  assert_file_not_contains "$F" "block body"
}

@test "gta_patch_remove preserves user content outside the block" {
  echo "user line 1" > "$F"
  gta_patch_write "$F" "0.1.0" "our body"
  echo "user line 2" >> "$F"
  gta_patch_remove "$F"
  assert_file_contains "$F" "^user line 1$"
  assert_file_contains "$F" "^user line 2$"
}

@test "gta_patch_remove is idempotent on file without sentinel" {
  echo "user content" > "$F"
  gta_patch_remove "$F"
  assert_file_contains "$F" "^user content$"
}

@test "gta_patch_remove is idempotent on missing file" {
  rm -f "$F"
  run gta_patch_remove "$F"
  assert_success
}

# --- newline normalization ---

@test "gta_patch_write normalizes file ending without \\n" {
  printf 'no newline at end' > "$F"
  gta_patch_write "$F" "0.1.0" "appended"
  # First line preserved (not merged with sentinel header)
  run head -1 "$F"
  assert_output "no newline at end"
  # Sentinel header is on its own line
  assert_file_contains "$F" "^# >>> ghostty-tmux-attach@"
}

@test "gta_patch_write works on missing file (creates it)" {
  rm -f "$F"
  gta_patch_write "$F" "0.1.0" "fresh body"
  assert_file_exist "$F"
  assert_file_contains "$F" "fresh body"
}

# --- gta_patch_version_hash ---

@test "gta_patch_version_hash returns 'VERSION HASH' from header" {
  gta_patch_write "$F" "0.1.0" "x"
  run gta_patch_version_hash "$F"
  assert_success
  # Output format: "VERSION HASH"
  [[ "$output" =~ ^0\.1\.0\ [a-f0-9]+$ ]] || fail "unexpected format: $output"
}

@test "gta_patch_version_hash empty when no sentinel" {
  echo "no sentinel" > "$F"
  run gta_patch_version_hash "$F"
  assert_success
  assert_output ""
}

# --- gta_set_union ---

@test "gta_set_union dedupes and sorts a comma list" {
  run gta_set_union "sudo,ssh-terminfo" "cursor,sudo,title"
  assert_success
  assert_output "cursor,ssh-terminfo,sudo,title"
}

@test "gta_set_union handles empty inputs" {
  run gta_set_union "" ""
  assert_output ""
  run gta_set_union "foo,bar" ""
  assert_output "bar,foo"
}

@test "gta_set_union trims whitespace within tokens" {
  run gta_set_union "  foo , bar " "bar,baz "
  assert_output "bar,baz,foo"
}

@test "gta_set_union ignores empty tokens (consecutive commas)" {
  run gta_set_union "foo,,bar" "baz"
  assert_output "bar,baz,foo"
}
