# ghostty-tmux-attach: zsh ZDOTDIR shim
# Sources Ghostty's shell-integration, then chains to the user's actual .zshrc.

# Source Ghostty integration if available
if [[ -n "${GHOSTTY_RESOURCES_DIR:-}" ]]; then
  _gta_int="$GHOSTTY_RESOURCES_DIR/shell-integration/zsh/ghostty-integration"
  if [[ -r "$_gta_int" ]]; then
    builtin source "$_gta_int"
  fi
  unset _gta_int
fi

# Inside tmux, override Ghostty's OSC 7 emitter to wrap in tmux DCS
# passthrough so the cwd reaches the outer Ghostty terminal. Without this,
# new Ghostty panes/tabs inherit the OUTER shell's launch-time cwd (stale
# once the user cd's inside tmux), and they open at the wrong directory.
if [[ -n "${TMUX:-}" ]]; then
  _ghostty_report_pwd() {
    builtin print -n -- $'\ePtmux;\e\e]7;kitty-shell-cwd://'"${HOST}${PWD}"$'\a\e\\'
  }
fi

# Restore the user's original ZDOTDIR and chain to their .zshrc
if [[ -n "${GHOSTTY_USER_ZDOTDIR:-}" ]]; then
  ZDOTDIR="$GHOSTTY_USER_ZDOTDIR"
  unset GHOSTTY_USER_ZDOTDIR
else
  ZDOTDIR="$HOME"
fi
export ZDOTDIR

if [[ -r "$ZDOTDIR/.zshrc" ]]; then
  builtin source "$ZDOTDIR/.zshrc"
fi
