#!/usr/bin/env bats
# Tests for libexec/ghostty-tmux-attach-shell — routes to per-shell shim.
#
# The shell stubs are installed under custom names (zsh-stub, bash-stub,
# fish-stub) rather than the real shell names, because the wrapper's own
# `#!/usr/bin/env bash` shebang resolves `bash` via PATH — and stubbing the
# literal "bash" name would poison the wrapper's own interpreter lookup.
# The wrapper sees GHOSTTY_USER_SHELL as an absolute path and dispatches off
# basename(), so we point that absolute path at a stub whose *basename* is
# the real shell name. We do that with symlinks below.

load '../helpers/common'
load '../helpers/sandbox'
load '../helpers/stubs'

setup() {
  sandbox_setup
  stubs_setup
  WRAPPER="$REPO_ROOT/libexec/ghostty-tmux-attach-shell"

  # Install dummy shells in a SEPARATE directory (NOT on PATH) so they don't
  # shadow the system `bash` that the wrapper's shebang needs. Each stub is
  # invoked via its absolute path; the wrapper uses basename() to dispatch.
  FAKE_SHELL_BIN=$(mktemp -d)
  cat > "$FAKE_SHELL_BIN/zsh" <<'EOSH'
#!/usr/bin/env bash
echo "STUB ZSH ZDOTDIR=${ZDOTDIR:-} GHOSTTY_USER_ZDOTDIR=${GHOSTTY_USER_ZDOTDIR:-}"
EOSH
  cat > "$FAKE_SHELL_BIN/bash" <<'EOSH'
#!/usr/bin/env bash
echo "STUB BASH ARGS=$*"
EOSH
  cat > "$FAKE_SHELL_BIN/fish" <<'EOSH'
#!/usr/bin/env bash
echo "STUB FISH (no rcfile expected)"
EOSH
  chmod +x "$FAKE_SHELL_BIN/zsh" "$FAKE_SHELL_BIN/bash" "$FAKE_SHELL_BIN/fish"
}

teardown() {
  if [ -n "${FAKE_SHELL_BIN:-}" ] && [ -d "$FAKE_SHELL_BIN" ]; then
    case "$FAKE_SHELL_BIN" in
      /tmp/*|/var/folders/*|"$TMPDIR"*) rm -rf "$FAKE_SHELL_BIN" ;;
    esac
  fi
  unset FAKE_SHELL_BIN
  stubs_teardown
  sandbox_teardown
}

@test "zsh branch sets ZDOTDIR to shim/zsh when ACTIVE=1" {
  GHOSTTY_TMUX_ATTACH_ACTIVE=1 \
  GHOSTTY_RESOURCES_DIR=/tmp/fake-ghostty \
  GHOSTTY_USER_SHELL="$FAKE_SHELL_BIN/zsh" \
    run "$WRAPPER"
  assert_success
  assert_output --partial "ZDOTDIR=$REPO_ROOT/shim/zsh"
}

@test "zsh branch preserves user's existing ZDOTDIR in GHOSTTY_USER_ZDOTDIR" {
  GHOSTTY_TMUX_ATTACH_ACTIVE=1 \
  GHOSTTY_RESOURCES_DIR=/tmp/fake-ghostty \
  GHOSTTY_USER_SHELL="$FAKE_SHELL_BIN/zsh" \
  ZDOTDIR=/custom/user/zdotdir \
    run "$WRAPPER"
  assert_success
  assert_output --partial "GHOSTTY_USER_ZDOTDIR=/custom/user/zdotdir"
}

@test "bash branch passes --rcfile pointing at shim/bash/bashrc when ACTIVE=1" {
  GHOSTTY_TMUX_ATTACH_ACTIVE=1 \
  GHOSTTY_RESOURCES_DIR=/tmp/fake-ghostty \
  GHOSTTY_USER_SHELL="$FAKE_SHELL_BIN/bash" \
    run "$WRAPPER"
  assert_success
  assert_output --partial "--rcfile $REPO_ROOT/shim/bash/bashrc"
}

@test "fish branch does plain exec (no shim arguments)" {
  GHOSTTY_TMUX_ATTACH_ACTIVE=1 \
  GHOSTTY_RESOURCES_DIR=/tmp/fake-ghostty \
  GHOSTTY_USER_SHELL="$FAKE_SHELL_BIN/fish" \
    run "$WRAPPER"
  assert_success
  assert_output --partial "STUB FISH (no rcfile expected)"
}

@test "pass-through when ACTIVE marker missing (zsh)" {
  GHOSTTY_TMUX_ATTACH_ACTIVE=0 \
  GHOSTTY_USER_SHELL="$FAKE_SHELL_BIN/zsh" \
    run "$WRAPPER"
  assert_success
  # Plain exec → no ZDOTDIR set by wrapper
  refute_output --partial "ZDOTDIR=$REPO_ROOT/shim/zsh"
}

@test "pass-through when GHOSTTY_RESOURCES_DIR missing (zsh)" {
  GHOSTTY_TMUX_ATTACH_ACTIVE=1 \
  GHOSTTY_RESOURCES_DIR= \
  GHOSTTY_USER_SHELL="$FAKE_SHELL_BIN/zsh" \
    run "$WRAPPER"
  assert_success
  refute_output --partial "ZDOTDIR=$REPO_ROOT/shim/zsh"
}

@test "falls back to \$SHELL when GHOSTTY_USER_SHELL not set" {
  unset GHOSTTY_USER_SHELL
  GHOSTTY_TMUX_ATTACH_ACTIVE=1 \
  GHOSTTY_RESOURCES_DIR=/tmp/fake-ghostty \
  SHELL="$FAKE_SHELL_BIN/zsh" \
    run "$WRAPPER"
  assert_success
  assert_output --partial "ZDOTDIR=$REPO_ROOT/shim/zsh"
}
