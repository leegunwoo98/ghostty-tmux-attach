#!/usr/bin/env bash
# stubs.bash — installable command stubs for tests.

stubs_setup() {
  STUB_BIN=$(mktemp -d)
  export PATH="$STUB_BIN:$PATH"
}

stubs_teardown() {
  if [ -n "${STUB_BIN:-}" ] && [ -d "$STUB_BIN" ]; then
    case "$STUB_BIN" in
      /tmp/*|/var/folders/*|"$TMPDIR"*) rm -rf "$STUB_BIN" ;;
      *) echo "REFUSING to clean unsafe stub path: $STUB_BIN" >&2 ;;
    esac
  fi
  unset STUB_BIN
}

stub_install() {
  local name="$1" body="$2"
  cat > "$STUB_BIN/$name" <<EOSTUB
#!/usr/bin/env bash
$body
EOSTUB
  chmod +x "$STUB_BIN/$name"
}

stub_tmux_no_sessions() {
  # shellcheck disable=SC2016  # $1 is intentionally literal — expanded inside the stub
  stub_install tmux '
    case "$1" in
      has-session) exit 1 ;;
      list-clients) exit 0 ;;
      list-sessions) exit 0 ;;
      *) exit 0 ;;
    esac
  '
}

stub_tmux_session_exists_with_clients() {
  # shellcheck disable=SC2016  # $1 is intentionally literal — expanded inside the stub
  stub_install tmux '
    case "$1" in
      has-session) exit 0 ;;
      list-clients) echo "fake-client: 1 windows" ; exit 0 ;;
      *) exit 0 ;;
    esac
  '
}

stub_ghostty_resources() {
  local dir
  dir=$(mktemp -d)
  mkdir -p "$dir/shell-integration/zsh" "$dir/shell-integration/bash"
  cat > "$dir/shell-integration/zsh/ghostty-integration" <<'INT'
echo "STUB_ZSH_GHOSTTY_INTEGRATION_SOURCED"
INT
  cat > "$dir/shell-integration/bash/ghostty-integration" <<'INT'
echo "STUB_BASH_GHOSTTY_INTEGRATION_SOURCED"
INT
  export GHOSTTY_RESOURCES_DIR="$dir"
}
