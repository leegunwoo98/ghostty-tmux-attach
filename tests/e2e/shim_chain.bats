#!/usr/bin/env bats
# Verify shim/zsh/.zshrc and shim/bash/bashrc source Ghostty integration
# THEN chain to user's actual rc, in that order.

load '../helpers/common'
load '../helpers/sandbox'

setup() {
  sandbox_setup

  # Create fake Ghostty resources with recognizable integration scripts.
  # The zsh integration mimics the real Ghostty integration's relevant plumbing
  # so the shim's override path is actually exercised: it defines a stub
  # _ghostty_report_pwd (which the shim later overrides) and registers it in
  # chpwd_functions + precmd_functions. Without this, the shim's override is
  # defined but never called, and the test can't distinguish "override missing"
  # from "hook plumbing missing".
  FAKE_GHOSTTY=$(mktemp -d)
  mkdir -p "$FAKE_GHOSTTY/shell-integration/zsh" "$FAKE_GHOSTTY/shell-integration/bash"
  cat > "$FAKE_GHOSTTY/shell-integration/zsh/ghostty-integration" <<'ZINT'
echo GHOSTTY_INTEGRATION_SOURCED
# Stub of the real Ghostty zsh integration's OSC 7 emitter — plain (non-tmux)
# variant. The shim redefines this when $TMUX is set; either way the hooks
# call _ghostty_report_pwd on chpwd and on every prompt.
_ghostty_report_pwd() {
  builtin print -n -- $'\e]7;kitty-shell-cwd://'"${HOST}${PWD}"$'\a'
}
typeset -ga chpwd_functions precmd_functions
chpwd_functions+=(_ghostty_report_pwd)
precmd_functions+=(_ghostty_report_pwd)
ZINT
  echo "echo BASH_GHOSTTY_INTEGRATION_SOURCED" > "$FAKE_GHOSTTY/shell-integration/bash/ghostty-integration"

  # Fake user ZDOTDIR for zsh test
  USER_ZDOTDIR=$(mktemp -d)
  echo "echo USER_ZSHRC_SOURCED" > "$USER_ZDOTDIR/.zshrc"

  # Fake user HOME for bash test (bash --rcfile <shim> then shim sources ~/.bashrc)
  USER_BASH_HOME=$(mktemp -d)
  echo "echo USER_BASHRC_SOURCED" > "$USER_BASH_HOME/.bashrc"
}

teardown() {
  rm -rf "$FAKE_GHOSTTY" "$USER_ZDOTDIR" "$USER_BASH_HOME" 2>/dev/null || true
  sandbox_teardown
}

@test "zsh shim sources Ghostty integration THEN user's .zshrc, in that order" {
  if ! command -v zsh >/dev/null 2>&1; then
    skip "zsh not installed"
  fi
  output=$(env -i HOME="$HOME" PATH="$PATH" \
    ZDOTDIR="$REPO_ROOT/shim/zsh" \
    GHOSTTY_USER_ZDOTDIR="$USER_ZDOTDIR" \
    GHOSTTY_RESOURCES_DIR="$FAKE_GHOSTTY" \
    zsh -i -c exit 2>&1 || true)

  # Both markers present
  echo "$output" | grep -q "GHOSTTY_INTEGRATION_SOURCED" || \
    { echo "OUT: $output"; fail "missing Ghostty marker"; }
  echo "$output" | grep -q "USER_ZSHRC_SOURCED" || \
    { echo "OUT: $output"; fail "missing user rc marker"; }

  # Order: Ghostty integration first
  ghostty_line=$(echo "$output" | grep -n GHOSTTY_INTEGRATION_SOURCED | head -1 | cut -d: -f1)
  user_line=$(echo "$output" | grep -n USER_ZSHRC_SOURCED | head -1 | cut -d: -f1)
  [ "$ghostty_line" -lt "$user_line" ] || fail "Ghostty integration ran AFTER user .zshrc"
}

@test "bash shim sources Ghostty integration THEN user's .bashrc, in that order" {
  if ! command -v bash >/dev/null 2>&1; then
    skip "bash not installed"
  fi
  output=$(env -i HOME="$USER_BASH_HOME" PATH="$PATH" \
    GHOSTTY_RESOURCES_DIR="$FAKE_GHOSTTY" \
    bash --rcfile "$REPO_ROOT/shim/bash/bashrc" -i -c exit 2>&1 || true)

  echo "$output" | grep -q "BASH_GHOSTTY_INTEGRATION_SOURCED" || \
    { echo "OUT: $output"; fail "missing bash Ghostty marker"; }
  echo "$output" | grep -q "USER_BASHRC_SOURCED" || \
    { echo "OUT: $output"; fail "missing user bashrc marker"; }

  ghostty_line=$(echo "$output" | grep -n BASH_GHOSTTY_INTEGRATION_SOURCED | head -1 | cut -d: -f1)
  user_line=$(echo "$output" | grep -n USER_BASHRC_SOURCED | head -1 | cut -d: -f1)
  [ "$ghostty_line" -lt "$user_line" ] || fail "bash Ghostty integration ran AFTER user .bashrc"
}

@test "zsh shim handles missing user ZDOTDIR (falls back to \$HOME)" {
  if ! command -v zsh >/dev/null 2>&1; then
    skip "zsh not installed"
  fi
  # No GHOSTTY_USER_ZDOTDIR — shim should fall back to $HOME
  echo "echo HOME_ZSHRC" > "$HOME/.zshrc"
  output=$(env -i HOME="$HOME" PATH="$PATH" \
    ZDOTDIR="$REPO_ROOT/shim/zsh" \
    GHOSTTY_RESOURCES_DIR="$FAKE_GHOSTTY" \
    zsh -i -c exit 2>&1 || true)
  echo "$output" | grep -q "HOME_ZSHRC" || \
    { echo "OUT: $output"; fail "zsh shim didn't fall back to \$HOME/.zshrc"; }
}

@test "zsh shim handles missing Ghostty integration script gracefully" {
  if ! command -v zsh >/dev/null 2>&1; then
    skip "zsh not installed"
  fi
  # Point at a non-existent Ghostty resources dir — shim should skip silently
  output=$(env -i HOME="$HOME" PATH="$PATH" \
    ZDOTDIR="$REPO_ROOT/shim/zsh" \
    GHOSTTY_USER_ZDOTDIR="$USER_ZDOTDIR" \
    GHOSTTY_RESOURCES_DIR="/nonexistent" \
    zsh -i -c exit 2>&1 || true)
  echo "$output" | grep -q "USER_ZSHRC_SOURCED" || \
    { echo "OUT: $output"; fail "user .zshrc not sourced when Ghostty integration missing"; }
}

@test "zsh shim emits tmux-wrapped OSC 7 when \$TMUX is set" {
  if ! command -v zsh >/dev/null 2>&1; then
    skip "zsh not installed"
  fi
  # Force a chpwd by cd'ing in the -c command so _ghostty_report_pwd fires
  output=$(env -i HOME="$HOME" PATH="$PATH" TERM=xterm \
    ZDOTDIR="$REPO_ROOT/shim/zsh" \
    GHOSTTY_USER_ZDOTDIR="$USER_ZDOTDIR" \
    GHOSTTY_RESOURCES_DIR="$FAKE_GHOSTTY" \
    TMUX="/tmp/fake-tmux,1234,0" \
    HOST=testhost \
    zsh -i -c 'cd /tmp; exit' 2>&1 || true)
  # Look for tmux DCS passthrough prefix: ESC P tmux ;
  # Use od to make the escape sequences visible in the assertion.
  # `od -c` on BSD/macOS renders ESC as `033` (octal); GNU coreutils renders
  # it as `esc`. Either way the rendering can split the prefix across two
  # `od -c` lines (e.g. ESC at end of one line, `P t m u x ;` at the start
  # of the next), so flatten the output with `tr -d \n` before grep so the
  # pattern matches across the original line boundary.
  printf '%s' "$output" | od -An -c | tr -d '\n' | grep -E '(033|esc)[[:space:]]+P[[:space:]]+t[[:space:]]+m[[:space:]]+u[[:space:]]+x[[:space:]]+;' >/dev/null || \
    { printf '%s' "$output" | od -c | head -20; fail "no tmux DCS passthrough prefix found in zsh shim output"; }
}

@test "zsh shim emits plain OSC 7 when \$TMUX is unset" {
  if ! command -v zsh >/dev/null 2>&1; then
    skip "zsh not installed"
  fi
  output=$(env -i HOME="$HOME" PATH="$PATH" TERM=xterm \
    ZDOTDIR="$REPO_ROOT/shim/zsh" \
    GHOSTTY_USER_ZDOTDIR="$USER_ZDOTDIR" \
    GHOSTTY_RESOURCES_DIR="$FAKE_GHOSTTY" \
    HOST=testhost \
    zsh -i -c 'cd /tmp; exit' 2>&1 || true)
  # Should NOT contain "Ptmux;" anywhere
  if printf '%s' "$output" | grep -q 'Ptmux;'; then
    fail "outside-tmux output should NOT contain tmux DCS wrap"
  fi
}

@test "bash shim emits tmux-wrapped OSC 7 when \$TMUX is set" {
  if ! command -v bash >/dev/null 2>&1; then
    skip "bash not installed"
  fi
  output=$(env -i HOME="$USER_BASH_HOME" PATH="$PATH" TERM=xterm \
    GHOSTTY_RESOURCES_DIR="$FAKE_GHOSTTY" \
    TMUX="/tmp/fake-tmux,1234,0" \
    bash --rcfile "$REPO_ROOT/shim/bash/bashrc" -i -c 'exit' 2>&1 || true)
  # `od -c` on BSD/macOS renders ESC as `033` (octal); GNU coreutils renders
  # it as `esc`. Either way the rendering can split the prefix across two
  # `od -c` lines (e.g. ESC at end of one line, `P t m u x ;` at the start
  # of the next), so flatten the output with `tr -d \n` before grep so the
  # pattern matches across the original line boundary.
  printf '%s' "$output" | od -An -c | tr -d '\n' | grep -E '(033|esc)[[:space:]]+P[[:space:]]+t[[:space:]]+m[[:space:]]+u[[:space:]]+x[[:space:]]+;' >/dev/null || \
    { printf '%s' "$output" | od -c | head -20; fail "no tmux DCS passthrough prefix found in bash shim output"; }
}
