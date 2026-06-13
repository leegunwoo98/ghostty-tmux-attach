#!/usr/bin/env bats
# Verify shim/zsh/.zshrc and shim/bash/bashrc source Ghostty integration
# THEN chain to user's actual rc, in that order.

load '../helpers/common'
load '../helpers/sandbox'

setup() {
  sandbox_setup

  # Create fake Ghostty resources with recognizable integration scripts
  FAKE_GHOSTTY=$(mktemp -d)
  mkdir -p "$FAKE_GHOSTTY/shell-integration/zsh" "$FAKE_GHOSTTY/shell-integration/bash"
  echo "echo GHOSTTY_INTEGRATION_SOURCED" > "$FAKE_GHOSTTY/shell-integration/zsh/ghostty-integration"
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
