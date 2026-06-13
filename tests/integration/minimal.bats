#!/usr/bin/env bats
# Tests for `install.sh init --minimal`.

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

@test "init --minimal writes a sentinel to ~/.tmux.conf" {
  "$REPO_ROOT/install.sh" init --minimal >/dev/null
  assert_file_contains "$HOME/.tmux.conf" "^# >>> ghostty-tmux-attach@"
  run grep -c "^set -g default-command" "$HOME/.tmux.conf"
  assert_output "0"
}

@test "init --minimal writes one-line Ghostty config calling tmux directly" {
  "$REPO_ROOT/install.sh" init --minimal >/dev/null
  assert_file_contains "$HOME/.config/ghostty/config" "^# >>> ghostty-tmux-attach@"
  run bash -c "grep -E '^command = .*tmux new-session -A -s main$' '$HOME/.config/ghostty/config'"
  assert_success
}

@test "init --minimal does NOT install the launcher binary" {
  "$REPO_ROOT/install.sh" init --minimal >/dev/null
  assert_file_not_exist "$HOME/.local/libexec/ghostty-tmux-attach/ghostty-tmux-attach-launch"
}

@test "init --minimal is idempotent (re-run produces single sentinel)" {
  "$REPO_ROOT/install.sh" init --minimal >/dev/null
  "$REPO_ROOT/install.sh" init --minimal >/dev/null
  run bash -c "grep -c '^# >>> ghostty-tmux-attach' '$HOME/.tmux.conf'"
  assert_output "1"
}
