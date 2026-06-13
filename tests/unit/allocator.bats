#!/usr/bin/env bats
# Tests for lib/allocator.sh

load '../helpers/common'
load '../helpers/sandbox'
load '../helpers/stubs'

setup() {
  sandbox_setup
  stubs_setup
  stub_tmux_no_sessions
  cd /tmp
}

teardown() {
  stubs_teardown
  sandbox_teardown
}

@test "allocator picks PWD basename when sessions empty" {
  source "$REPO_ROOT/lib/allocator.sh"
  gta_choose_session
  assert_equal "$GTA_CHOSEN" "tmp"
}

@test "allocator sanitizes non-ASCII basenames" {
  mkdir -p "$SANDBOX_HOME/한국"
  cd "$SANDBOX_HOME/한국"
  source "$REPO_ROOT/lib/allocator.sh"
  gta_choose_session
  # All non-ASCII bytes fold to underscores; result is some number of _ chars
  [[ "$GTA_CHOSEN" =~ ^_+$ ]] || flunk "Unsanitized: $GTA_CHOSEN"
}

@test "allocator handles PWD=/ → root" {
  cd /
  source "$REPO_ROOT/lib/allocator.sh"
  gta_choose_session
  assert_equal "$GTA_CHOSEN" "root"
}

@test "allocator writes claim file" {
  source "$REPO_ROOT/lib/allocator.sh"
  gta_choose_session
  assert_file_exist "$GTA_CLAIMS/$GTA_CHOSEN"
}

# Stale-claim GC: a claim file pointing at a dead PID must be reclaimed by
# the next acquirer. Verifies the gta_owner_alive → rm-and-retry path.
@test "allocator GCs claim with dead PID" {
  cd /tmp
  source "$REPO_ROOT/lib/allocator.sh"
  # Mirror gta_choose_session's path layout so we can pre-plant the claim.
  GTA_ROOT="${XDG_CACHE_HOME}/ghostty-tmux-attach"
  GTA_CLAIMS="$GTA_ROOT/claims"
  mkdir -p "$GTA_CLAIMS"
  # PID 99999 plus an obviously-bogus start time. `kill -0 99999` returns
  # 1 on a fresh sandbox, so gta_owner_alive bails before the start-time
  # check ever runs — this exercises the dead-PID GC branch.
  echo "99999:0" > "$GTA_CLAIMS/tmp"

  gta_choose_session
  assert_equal "$GTA_CHOSEN" "tmp"
  # The fresh claim must contain our own owner tuple (PID:something).
  run cat "$GTA_CLAIMS/tmp"
  assert_output --regexp "^$$:"
}

# PID-reuse impostor: a claim that names a live PID (ours) but a start time
# that doesn't match must be treated as stale and reclaimed. Verifies the
# tuple-equality branch of gta_owner_alive.
@test "allocator advances past claim with PID-mismatch impostor" {
  cd /tmp
  source "$REPO_ROOT/lib/allocator.sh"
  GTA_ROOT="${XDG_CACHE_HOME}/ghostty-tmux-attach"
  GTA_CLAIMS="$GTA_ROOT/claims"
  mkdir -p "$GTA_CLAIMS"
  # Our PID is alive (kill -0 succeeds) but the start time can't match our
  # real one — verifier should return false → GC → reclaim.
  echo "$$:99999999999" > "$GTA_CLAIMS/tmp"

  gta_choose_session
  assert_equal "$GTA_CHOSEN" "tmp"
  run cat "$GTA_CLAIMS/tmp"
  assert_output --regexp "^$$:"
}

# Live owner: a claim that names a genuinely-live process with the correct
# start time must block its name; the allocator must advance to the next
# candidate. Verifies the "alive" branch of gta_owner_alive.
@test "allocator skips claim with live owner" {
  cd /tmp
  source "$REPO_ROOT/lib/allocator.sh"
  GTA_ROOT="${XDG_CACHE_HOME}/ghostty-tmux-attach"
  GTA_CLAIMS="$GTA_ROOT/claims"
  mkdir -p "$GTA_CLAIMS"

  # Spawn a real sleeping process and forge an owner tuple for it using the
  # SAME pipeline gta_self_owner uses — otherwise the verifier wouldn't
  # match and this test would degenerate into the impostor case.
  sleep 10 &
  live_pid=$!
  if [ "$(uname -s)" = "Linux" ] && [ -r "/proc/$live_pid/stat" ]; then
    live_start=$(awk '{print $22}' "/proc/$live_pid/stat")
  else
    live_start=$(LC_ALL=C ps -o lstart= -p "$live_pid" 2>/dev/null | LC_ALL=C xargs -I{} date -j -f "%a %b %d %T %Y" "{}" +%s 2>/dev/null)
  fi
  echo "$live_pid:$live_start" > "$GTA_CLAIMS/tmp"

  gta_choose_session
  # "tmp" is held by a live owner → must advance to "tmp-2".
  assert_equal "$GTA_CHOSEN" "tmp-2"

  kill "$live_pid" 2>/dev/null || true
  wait "$live_pid" 2>/dev/null || true
}
