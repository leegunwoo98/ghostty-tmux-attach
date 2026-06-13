#!/usr/bin/env bats
# Tests for lib/known_hashes.sh.

load '../helpers/common'

setup() {
  # shellcheck source=/dev/null
  source "$REPO_ROOT/lib/known_hashes.sh"
}

@test "GTA_HASHES has ghostty/0.1.0 entry" {
  [ -n "${GTA_HASHES[ghostty/0.1.0]:-}" ]
}

@test "GTA_HASHES has tmux-main/0.1.0 entry" {
  [ -n "${GTA_HASHES[tmux-main/0.1.0]:-}" ]
}

@test "GTA_HASHES has tmux-minimal/0.1.0 entry" {
  [ -n "${GTA_HASHES[tmux-minimal/0.1.0]:-}" ]
}

@test "gta_hash_known returns true for known key" {
  run gta_hash_known "ghostty/0.1.0"
  assert_success
}

@test "gta_hash_known returns false for unknown key" {
  run gta_hash_known "ghostty/99.99.99"
  assert_failure
}

@test "gta_hash_for returns the hash for a known key" {
  run gta_hash_for "ghostty/0.1.0"
  assert_success
  [ -n "$output" ]
  # Hash should be 16 hex chars (matching gta_patch_hash's output format)
  [[ "$output" =~ ^[a-f0-9]{16}$ ]] || fail "hash format wrong: '$output'"
}

@test "gta_hash_for returns empty for unknown key" {
  run gta_hash_for "ghostty/99.99.99"
  assert_success
  assert_output ""
}

@test "computed snippet hash matches table for ghostty/0.1.0" {
  # The installer will read snippets/ghostty.conf and hash it; the table must
  # match. (This is the contract that lets --update detect hand-edits.)
  source "$REPO_ROOT/lib/patches.sh"
  local body
  body=$(cat "$REPO_ROOT/snippets/ghostty.conf")
  local computed expected
  computed=$(gta_patch_hash "$body")
  expected=$(gta_hash_for "ghostty/0.1.0")
  assert_equal "$computed" "$expected"
}

@test "computed snippet hash matches table for tmux-main/0.1.0" {
  source "$REPO_ROOT/lib/patches.sh"
  local body computed expected
  body=$(cat "$REPO_ROOT/snippets/tmux.conf")
  computed=$(gta_patch_hash "$body")
  expected=$(gta_hash_for "tmux-main/0.1.0")
  assert_equal "$computed" "$expected"
}

@test "computed snippet hash matches table for tmux-minimal/0.1.0" {
  source "$REPO_ROOT/lib/patches.sh"
  local body computed expected
  body=$(cat "$REPO_ROOT/snippets/tmux.conf.minimal")
  computed=$(gta_patch_hash "$body")
  expected=$(gta_hash_for "tmux-minimal/0.1.0")
  assert_equal "$computed" "$expected"
}
