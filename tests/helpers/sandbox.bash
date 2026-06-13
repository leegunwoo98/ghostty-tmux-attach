#!/usr/bin/env bash
# sandbox.bash — sandboxed $HOME isolation helpers.

sandbox_setup() {
  SANDBOX_HOME=$(mktemp -d)
  SANDBOX_CACHE="$SANDBOX_HOME/.cache"
  SANDBOX_STATE="$SANDBOX_HOME/.local/state"
  SANDBOX_DATA="$SANDBOX_HOME/.local/share"
  mkdir -p "$SANDBOX_HOME/.config" "$SANDBOX_CACHE" "$SANDBOX_STATE" "$SANDBOX_DATA"
  export HOME="$SANDBOX_HOME"
  export XDG_CACHE_HOME="$SANDBOX_CACHE"
  export XDG_STATE_HOME="$SANDBOX_STATE"
  export XDG_DATA_HOME="$SANDBOX_DATA"
}

sandbox_teardown() {
  if [ -n "${SANDBOX_HOME:-}" ] && [ -d "$SANDBOX_HOME" ]; then
    # Safety check: never rm -rf a path that isn't under /tmp or $TMPDIR
    case "$SANDBOX_HOME" in
      /tmp/*|/var/folders/*|"$TMPDIR"*) rm -rf "$SANDBOX_HOME" ;;
      *) echo "REFUSING to clean unsafe sandbox path: $SANDBOX_HOME" >&2 ;;
    esac
  fi
  unset SANDBOX_HOME SANDBOX_CACHE SANDBOX_STATE SANDBOX_DATA
  unset XDG_CACHE_HOME XDG_STATE_HOME XDG_DATA_HOME
}

sandbox_seed_ghostty_config() {
  local content="${1:-}"
  mkdir -p "$HOME/.config/ghostty"
  if [ -n "$content" ]; then
    printf '%s\n' "$content" > "$HOME/.config/ghostty/config"
  else
    cat > "$HOME/.config/ghostty/config" <<'GCFG'
# user's existing ghostty config
font-family = JetBrainsMono Nerd Font
shell-integration-features = cursor,sudo,title
GCFG
  fi
}

sandbox_seed_tmux_conf() {
  local with_tpm="${1:-yes}"
  cat > "$HOME/.tmux.conf" <<'TCFG'
# user's existing tmux config
set -g prefix C-a
unbind C-b
TCFG
  if [ "$with_tpm" = "yes" ]; then
    echo "run '~/.tmux/plugins/tpm/tpm'" >> "$HOME/.tmux.conf"
  fi
}
