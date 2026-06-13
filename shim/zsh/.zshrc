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
