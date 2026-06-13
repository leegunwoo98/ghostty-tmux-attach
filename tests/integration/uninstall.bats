#!/usr/bin/env bats
# Tests for `install.sh uninstall`.

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

@test "uninstall removes sentinel blocks (surgical, default)" {
  "$REPO_ROOT/install.sh" init >/dev/null
  "$REPO_ROOT/install.sh" uninstall >/dev/null
  # grep -c prints '0' and exits 1 on zero matches; ; true preserves the count
  run bash -c "grep -c '>>> ghostty-tmux-attach' '$HOME/.config/ghostty/config' 2>/dev/null; true"
  assert_output "0"
  run bash -c "grep -c '>>> ghostty-tmux-attach' '$HOME/.tmux.conf' 2>/dev/null; true"
  assert_output "0"
}

@test "uninstall preserves user content from before install" {
  "$REPO_ROOT/install.sh" init >/dev/null
  "$REPO_ROOT/install.sh" uninstall >/dev/null
  assert_file_contains "$HOME/.tmux.conf" "^set -g prefix C-a"
}

@test "uninstall preserves user content edited AFTER install" {
  "$REPO_ROOT/install.sh" init >/dev/null
  echo "set -g mouse on" >> "$HOME/.tmux.conf"
  "$REPO_ROOT/install.sh" uninstall >/dev/null
  assert_file_contains "$HOME/.tmux.conf" "^set -g mouse on"
}

@test "uninstall un-comments original shell-integration-features line" {
  "$REPO_ROOT/install.sh" init >/dev/null
  "$REPO_ROOT/install.sh" uninstall >/dev/null
  run bash -c "grep -c '^shell-integration-features = cursor,sudo,title' '$HOME/.config/ghostty/config'"
  assert_output "1"
  run bash -c "grep -c 'disabled by ghostty-tmux-attach' '$HOME/.config/ghostty/config' 2>/dev/null; true"
  assert_output "0"
}

@test "uninstall removes installed launcher binary" {
  "$REPO_ROOT/install.sh" init >/dev/null
  assert_file_exist "$HOME/.local/libexec/ghostty-tmux-attach/ghostty-tmux-attach-launch"
  "$REPO_ROOT/install.sh" uninstall >/dev/null
  assert_file_not_exist "$HOME/.local/libexec/ghostty-tmux-attach/ghostty-tmux-attach-launch"
}

@test "uninstall clears cache dir" {
  "$REPO_ROOT/install.sh" init >/dev/null
  mkdir -p "$XDG_CACHE_HOME/ghostty-tmux-attach/claims"
  touch "$XDG_CACHE_HOME/ghostty-tmux-attach/claims/somesession"
  "$REPO_ROOT/install.sh" uninstall >/dev/null
  assert_dir_not_exist "$XDG_CACHE_HOME/ghostty-tmux-attach"
}

@test "uninstall purges tmux-resurrect files containing our marker" {
  "$REPO_ROOT/install.sh" init >/dev/null
  local resurrect_dir="$XDG_DATA_HOME/tmux/resurrect"
  mkdir -p "$resurrect_dir"
  echo "pane GHOSTTY_TMUX_ATTACH_ACTIVE=1 ..." > "$resurrect_dir/pane_save_1.txt"
  echo "pane (clean, no marker)" > "$resurrect_dir/clean.txt"
  "$REPO_ROOT/install.sh" uninstall >/dev/null
  assert_file_exist "$resurrect_dir/clean.txt"
  assert_file_not_exist "$resurrect_dir/pane_save_1.txt"
  run bash -c "find '$resurrect_dir' -name 'pane_save_1.txt' -path '*/uninstalled-*' | head -1"
  [ -n "$output" ]
}

@test "uninstall --restore-snapshot reverts ghostty config to pre-install state" {
  local orig_content
  orig_content=$(cat "$HOME/.config/ghostty/config")
  "$REPO_ROOT/install.sh" init >/dev/null
  echo "user-added-after-install = yes" >> "$HOME/.config/ghostty/config"
  "$REPO_ROOT/install.sh" uninstall --restore-snapshot >/dev/null
  run cat "$HOME/.config/ghostty/config"
  assert_output "$orig_content"
}

@test "uninstall is idempotent (safe re-run)" {
  "$REPO_ROOT/install.sh" init >/dev/null
  "$REPO_ROOT/install.sh" uninstall >/dev/null
  run "$REPO_ROOT/install.sh" uninstall
  assert_success
}
