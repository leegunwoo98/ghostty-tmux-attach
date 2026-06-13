#!/usr/bin/env bats
# 5-process race test for the allocator — verify each gets a distinct name.

load '../helpers/common'

setup() {
  STUB=$(mktemp -d)
  cat > "$STUB/tmux" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  has-session) exit 1 ;;
  list-clients) exit 0 ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$STUB/tmux"

  WORKDIR=$(mktemp -d)
  CACHE="$WORKDIR/.cache/ghostty-tmux-attach"
  PWD_DIR="$WORKDIR/racetest-dir"
  mkdir -p "$PWD_DIR"

  WORKER="$WORKDIR/worker.sh"
  cat > "$WORKER" <<EOFWORKER
#!/usr/bin/env bash
set -eu
export PATH="$STUB:\$PATH"
export XDG_CACHE_HOME="$WORKDIR/.cache"
cd "$PWD_DIR"
source "$REPO_ROOT/lib/allocator.sh"
gta_choose_session
echo "\$\$ -> \$GTA_CHOSEN"
sleep 2
EOFWORKER
  chmod +x "$WORKER"
}

teardown() {
  rm -rf "$STUB" "$WORKDIR" 2>/dev/null || true
}

@test "5 concurrent allocators get distinct session names" {
  for i in 1 2 3 4 5; do
    bash "$WORKER" &
  done
  wait

  # Count distinct claim files
  n=$(ls "$CACHE/claims" 2>/dev/null | wc -l | tr -d ' ')
  assert_equal "$n" "5"
}
