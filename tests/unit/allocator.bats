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
