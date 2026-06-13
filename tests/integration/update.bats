#!/usr/bin/env bats
# Tests for `install.sh init --update`.

load '../helpers/common'
load '../helpers/sandbox'

setup() {
  sandbox_setup
  sandbox_seed_ghostty_config
  sandbox_seed_tmux_conf yes
}

teardown() {
  sandbox_teardown
}

@test "update on unedited sentinel succeeds" {
  "$REPO_ROOT/install.sh" init >/dev/null
  run "$REPO_ROOT/install.sh" init --update
  assert_success
}

@test "update refuses when user hand-edited inside the sentinel" {
  "$REPO_ROOT/install.sh" init >/dev/null
  # Insert a user edit inside the sentinel block
  sed -i.bak '/^command = /a\
USER_HAND_EDIT' "$HOME/.config/ghostty/config"
  rm -f "$HOME/.config/ghostty/config.bak"

  run "$REPO_ROOT/install.sh" init --update
  assert_failure
  # The user's edit should still be in the file (refusal = no clobber)
  run bash -c "grep -c USER_HAND_EDIT '$HOME/.config/ghostty/config'"
  [ "$output" -ge "1" ]
}

@test "update --force overrides the user-edited check" {
  "$REPO_ROOT/install.sh" init >/dev/null
  sed -i.bak '/^command = /a\
USER_HAND_EDIT' "$HOME/.config/ghostty/config"
  rm -f "$HOME/.config/ghostty/config.bak"

  run "$REPO_ROOT/install.sh" init --update --force
  assert_success
  # --force clobbers the edit
  run bash -c "grep -c USER_HAND_EDIT '$HOME/.config/ghostty/config' 2>/dev/null; true"
  assert_output "0"
}
