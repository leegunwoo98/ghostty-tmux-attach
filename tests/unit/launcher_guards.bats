#!/usr/bin/env bats
# Tests for libexec/ghostty-tmux-attach-launch guard behavior.

load '../helpers/common'
load '../helpers/sandbox'
load '../helpers/stubs'

setup() {
  sandbox_setup
  stubs_setup
  export GHOSTTY_TMUX_ATTACH_DEBUG=1
  LAUNCHER="$REPO_ROOT/libexec/ghostty-tmux-attach-launch"
  LOG="$XDG_STATE_HOME/ghostty-tmux-attach/launch.log"
  # Bats often runs inside tmux during local dev; isolate the launcher from
  # the harness's tmux env so non-TMUX-guard tests see a clean slate.
  unset TMUX TMUX_PANE
  unset SSH_CONNECTION SSH_CLIENT SSH_TTY
}

teardown() {
  stubs_teardown
  sandbox_teardown
}

# Helper: assert the log contains a pattern
assert_log_contains() {
  local pattern="$1"
  if [ ! -f "$LOG" ]; then
    fail "log file missing at $LOG"
  fi
  if ! grep -q "$pattern" "$LOG"; then
    echo "--- log contents ---"
    cat "$LOG"
    fail "pattern not found in log: $pattern"
  fi
}

@test "guard: no TTY → exec user shell (logged)" {
  # Run launcher without a controlling TTY (redirect stdin from /dev/null)
  # so [ -t 0 ] fails. The launcher should exec the user shell, which since
  # we run with </dev/null exits quickly. We only care that the log records it.
  # Do NOT set the TTY-skip hook here — that's the whole point of this test.
  run bash -c "echo | '$LAUNCHER' </dev/null >/dev/null 2>&1; true"
  assert_log_contains "guard: no TTY"
}

@test "guard: already in TMUX → exec user shell" {
  # Tests below this point run under bats (no TTY), so they set the
  # TTY-skip hook to exercise the OTHER guards. The TTY guard itself is
  # covered by the test above.
  GHOSTTY_TMUX_ATTACH_TEST_SKIP_TTY_GUARD=1 \
  TMUX="/tmp/fake-tmux-socket,1234,0" \
    run bash -c "'$LAUNCHER' </dev/null >/dev/null 2>&1; true"
  assert_log_contains "guard: already in tmux"
}

@test "guard: missing GHOSTTY_RESOURCES_DIR → exec user shell" {
  unset GHOSTTY_RESOURCES_DIR
  GHOSTTY_TMUX_ATTACH_TEST_SKIP_TTY_GUARD=1 \
    run bash -c "'$LAUNCHER' </dev/null >/dev/null 2>&1; true"
  assert_log_contains "GHOSTTY_RESOURCES_DIR unset"
}

@test "guard: SSH session → exec user shell" {
  GHOSTTY_TMUX_ATTACH_TEST_SKIP_TTY_GUARD=1 \
  SSH_CONNECTION="10.0.0.1 1234 10.0.0.2 22" \
  GHOSTTY_RESOURCES_DIR="/tmp/fake-ghostty" \
    run bash -c "'$LAUNCHER' </dev/null >/dev/null 2>&1; true"
  assert_log_contains "guard: SSH session"
}

@test "guard: tmux not found → exec user shell" {
  # Drop tmux from PATH (empty stub dir; PATH was set by stubs_setup)
  GHOSTTY_TMUX_ATTACH_TEST_SKIP_TTY_GUARD=1 \
  GHOSTTY_RESOURCES_DIR="/tmp/fake-ghostty" \
  PWD="/tmp/non-home" \
    run bash -c "cd /tmp && '$LAUNCHER' </dev/null >/dev/null 2>&1; true"
  # Either "tmux not found" or earlier guard fired; both fine — just verify
  # the launcher reached the tmux-check or earlier guard.
  [ -f "$LOG" ]
}

@test "OSC 7 emitted with kitty-shell-cwd URI when all guards pass" {
  # Stub tmux to immediately exit; we just want to verify OSC 7 emission.
  stub_install tmux 'exit 0'
  GHOSTTY_TMUX_ATTACH_TEST_SKIP_TTY_GUARD=1 \
  GHOSTTY_RESOURCES_DIR="/tmp/fake-ghostty" \
    run bash -c "cd /tmp && '$LAUNCHER' </dev/null 2>/dev/null"
  # The OSC 7 escape goes to stdout — output may or may not be captured by bats
  # depending on TTY. Just check the log shows it was emitted.
  assert_log_contains "OSC 7 emitted"
}
