#!/usr/bin/env bats
# Tests for `install.sh doctor`.

load '../helpers/common'
load '../helpers/sandbox'

setup() {
  sandbox_setup
}

teardown() {
  sandbox_teardown
}

@test "doctor reports OS line" {
  run "$REPO_ROOT/install.sh" doctor
  assert_success
  assert_output --partial "OS:"
}

@test "doctor reports tmux state" {
  run "$REPO_ROOT/install.sh" doctor
  assert_success
  assert_output --partial "tmux:"
}

@test "doctor reports Ghostty state" {
  run "$REPO_ROOT/install.sh" doctor
  assert_success
  assert_output --partial "Ghostty:"
}

@test "doctor --json emits parseable JSON" {
  if ! command -v python3 >/dev/null 2>&1; then
    skip "python3 not available"
  fi
  run "$REPO_ROOT/install.sh" doctor --json
  assert_success
  echo "$output" | python3 -c 'import sys, json; json.loads(sys.stdin.read())'
}

@test "doctor --json includes os and arch fields" {
  if ! command -v python3 >/dev/null 2>&1; then
    skip "python3 not available"
  fi
  run "$REPO_ROOT/install.sh" doctor --json
  assert_success
  echo "$output" | python3 -c 'import sys, json; d=json.loads(sys.stdin.read()); assert "os" in d and "arch" in d, d'
}
