#!/usr/bin/env bats
# Tests for `install.sh init` (main mode).

load '../helpers/common'
load '../helpers/sandbox'

setup() {
  sandbox_setup
}

teardown() {
  sandbox_teardown
}

@test "init --dry-run shows unified diff headers and would-create lines" {
  sandbox_seed_ghostty_config
  sandbox_seed_tmux_conf yes

  run "$REPO_ROOT/install.sh" init --dry-run
  assert_success
  assert_output --partial "---"
  assert_output --partial "+++"
  assert_output --partial "would-create:"
}

@test "init --dry-run writes nothing" {
  sandbox_seed_ghostty_config
  cp "$HOME/.config/ghostty/config" "$HOME/before.txt"
  "$REPO_ROOT/install.sh" init --dry-run >/dev/null
  run diff "$HOME/before.txt" "$HOME/.config/ghostty/config"
  assert_success
}

@test "init writes sentinel block to ~/.config/ghostty/config" {
  sandbox_seed_ghostty_config
  sandbox_seed_tmux_conf yes
  "$REPO_ROOT/install.sh" init >/dev/null
  assert_file_contains "$HOME/.config/ghostty/config" "^# >>> ghostty-tmux-attach@"
  assert_file_contains "$HOME/.config/ghostty/config" "^command = "
  assert_file_contains "$HOME/.config/ghostty/config" "^window-save-state = always"
}

@test "init writes sentinel block to ~/.tmux.conf" {
  sandbox_seed_ghostty_config
  sandbox_seed_tmux_conf yes
  "$REPO_ROOT/install.sh" init >/dev/null
  assert_file_contains "$HOME/.tmux.conf" "^# >>> ghostty-tmux-attach@"
  assert_file_contains "$HOME/.tmux.conf" "^set -g default-command "
}

@test "init preserves user's existing tmux content" {
  sandbox_seed_ghostty_config
  sandbox_seed_tmux_conf yes
  "$REPO_ROOT/install.sh" init >/dev/null
  assert_file_contains "$HOME/.tmux.conf" "^set -g prefix C-a"
}

@test "init unions shell-integration-features with user's existing values" {
  sandbox_seed_ghostty_config   # has shell-integration-features = cursor,sudo,title
  sandbox_seed_tmux_conf no
  "$REPO_ROOT/install.sh" init >/dev/null
  # Inside the sentinel: union should contain cursor, sudo, ssh-terminfo, title
  # (our required set is sudo,ssh-terminfo,cursor,title; user had cursor,sudo,title)
  run bash -c "awk '/>>> ghostty-tmux-attach/,/<<<.ghostty/' '$HOME/.config/ghostty/config' | grep '^shell-integration-features'"
  assert_success
  assert_output --partial "cursor"
  assert_output --partial "sudo"
  assert_output --partial "title"
  assert_output --partial "ssh-terminfo"
}

@test "init comments out user's existing shell-integration-features outside the sentinel" {
  sandbox_seed_ghostty_config
  sandbox_seed_tmux_conf no
  "$REPO_ROOT/install.sh" init >/dev/null
  assert_file_contains "$HOME/.config/ghostty/config" "^# disabled by ghostty-tmux-attach"
}

@test "init is idempotent (no duplicate sentinels)" {
  sandbox_seed_ghostty_config
  sandbox_seed_tmux_conf yes
  "$REPO_ROOT/install.sh" init >/dev/null
  "$REPO_ROOT/install.sh" init >/dev/null
  run bash -c "grep -c '^# >>> ghostty-tmux-attach' '$HOME/.config/ghostty/config'"
  assert_output "1"
  run bash -c "grep -c '^# >>> ghostty-tmux-attach' '$HOME/.tmux.conf'"
  assert_output "1"
}

@test "init takes a snapshot under ~/.local/share/ghostty-tmux-attach/snapshots/" {
  sandbox_seed_ghostty_config
  sandbox_seed_tmux_conf yes
  "$REPO_ROOT/install.sh" init >/dev/null
  run bash -c "ls $HOME/.local/share/ghostty-tmux-attach/snapshots/ 2>/dev/null | wc -l | tr -d ' '"
  [ "$output" -ge "1" ]
}

@test "init copies launcher binary to install dir" {
  sandbox_seed_ghostty_config
  sandbox_seed_tmux_conf yes
  "$REPO_ROOT/install.sh" init >/dev/null
  # Launcher lives at <prefix>/libexec/ghostty-tmux-attach/ghostty-tmux-attach-launch
  # Find it under either brew prefix or ~/.local
  run bash -c "test -x $HOME/.local/libexec/ghostty-tmux-attach/ghostty-tmux-attach-launch && echo OK"
  assert_output "OK"
}
