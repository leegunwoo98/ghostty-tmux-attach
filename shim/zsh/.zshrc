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

# Restore the user's original ZDOTDIR and chain to their .zshrc FIRST.
# We hook the OSC 7 wrap AFTER the user's rc so even if their rc re-sources
# Ghostty's integration (legacy/manual setups), our hook still fires on every
# precmd/chpwd via add-zsh-hook (the user's re-source merely appends another
# plain emitter — our DCS-wrapped emitter still runs and reaches Ghostty).
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

# Inside tmux, add a DCS-passthrough OSC 7 emitter so cwd updates reach the
# outer Ghostty terminal. Runs ALONGSIDE Ghostty's own plain OSC 7 emit
# (which tmux intercepts harmlessly) via separate chpwd/precmd hooks.
# Robust against user .zshrc re-sourcing Ghostty integration: re-sources
# append to the hook arrays without removing our function.
if [[ -n "${TMUX:-}" ]]; then
  _gta_tmux_osc7() {
    builtin print -n -- $'\ePtmux;\e\e]7;kitty-shell-cwd://'"${HOST}${PWD}"$'\a\e\\'
  }
  autoload -Uz add-zsh-hook
  add-zsh-hook chpwd _gta_tmux_osc7
  add-zsh-hook precmd _gta_tmux_osc7
  _gta_tmux_osc7   # fire once immediately so the wrap reaches Ghostty pre-first-prompt
fi
