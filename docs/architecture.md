> Originally drafted 2026-06-13 in collaboration with Claude Code (superpowers brainstorming + writing-plans).
> Three independent review passes (general-purpose + code-reviewer subagents) shaped the final design.
>

# ghostty-tmux-attach — design

**Status:** draft, awaiting user review
**Date:** 2026-06-13
**Author:** Gunwoo Lee (designed via Claude Code session)
**Architecture review:** two independent subagent reviews (teammate-UX lens + maintainer lens) both picked **B (launcher-wrapper)** over A (zshrc-source) and C (single-session). Pivoted accordingly. C is included as an opt-in "minimal mode."
**Audience:** public OSS; macOS and Linux developers using Ghostty + tmux

## 1. Problem

Ghostty 1.3.1's `window-save-state = always` correctly restores windows, tabs, and splits across `Cmd+Q`. But for users running tmux underneath, restored surfaces drop to a bare `$HOME` shell instead of reattaching to tmux. Continuum's saved sessions sit idle on the server with zero clients.

Three independent traps cause this; all three must be addressed for restore to actually work:

1. **PATH gap.** Ghostty cold-start spawns the user's shell as a login shell (`-l`), so `~/.zprofile` runs and `eval "$(brew shellenv)"` puts `/opt/homebrew/bin` on `PATH`. But on `window-save-state` restore, Ghostty respawns surfaces **without** `-l`. `~/.zprofile` is skipped, `/opt/homebrew/bin` is missing from `PATH`, `command -v tmux` returns non-zero.

2. **OSC 7 timing.** Ghostty's auto-injected zsh shell-integration script sends OSC 7 (`kitty-shell-cwd://<host><path>`) only from `precmd` and `chpwd` hooks. An auto-attach script that `exec`s tmux during `.zshrc` does so **before the first prompt ever renders**, so neither hook fires, Ghostty never learns the surface's cwd, `window-save-state` saves nothing useful. Inner-tmux OSC 7 doesn't help — tmux intercepts it for its own per-pane cwd tracking and does not forward to the outer terminal even with `allow-passthrough on`.

3. **Allocator race.** A "find a tmux session that has no clients" loop using `tmux list-clients -t "=NAME"` has a TOCTOU window. When `window-save-state` restores N surfaces simultaneously, all see "no clients," all `exec tmux new-session -A -s SAME_NAME`, all share the one session, and the user sees N panes mirroring identical content.

## 2. Goals and non-goals

### Goals

- **One-line install via curl-pipe** (`curl … | bash`). The Homebrew tap is an alternative install path but, per Homebrew conventions, formulae cannot patch user dotfiles — so the brew path is two commands: `brew install <tap>/ghostty-tmux-attach` then `ghostty-tmux-attach init`. Both result in the same final state.
- **Idempotent**: re-running is a no-op; `update` cleanly replaces previous-version blocks; `uninstall` truly restores pre-install state.
- **Zero interactive-shell-rc patching**: no edits to `.zshrc`, `.bashrc`, `.zshenv`, `.zprofile`, `.bash_profile`, or `.shell_common`. The user's interactive-shell config is sacred ground. (`~/.profile` falls outside this scope — we don't write it either, but documentation may recommend the user add a `~/.local/bin` PATH entry there themselves.)
- **Cross-shell, first-class**: zsh AND bash both get auto-integration in v0.1, including inner-tmux Ghostty integration sourcing. Bash 4+ required on macOS (system bash 3.2 not supported in v0.1; installer prompts `brew install bash`). zsh 5.0+ supported.
- **Cross-platform**: macOS (Apple Silicon + Intel) AND Linux (x86_64 + aarch64) in v0.1. The launcher is POSIX sh; the only OS-specific code is install-path detection and `brew` probing.
- **Cross-architecture**: Apple Silicon and Intel Macs; x86_64 and aarch64 Linux.
- **Observable**: a `doctor` subcommand reports prereq state and config; `GHOSTTY_TMUX_ATTACH_DEBUG=1` logs every guard decision.
- **Safe**: dry-run mode; checksum-verifiable releases.
- **Race-free** session-name allocation; correct under N-surface simultaneous restore using real `flock(2)` (since we now have a real binary, not a sourced shell snippet).
- **Cleanly deprecatable** when Ghostty ships native session restore.

### Non-goals (v0.1)

- No Windows (Ghostty hasn't shipped Windows yet; revisit when it does).
- No fish shell auto-integration (manual snippet documented in Section 5).
- No telemetry, no auto-update check, no dotfile-manager features.
- No installing Ghostty, tmux, or Homebrew on the user's behalf — `doctor` reports missing prereqs and exits with a non-zero code.
- No `chsh`-ing the user.
- No opinionated keybindings, themes, sesh popup, lazygit popup.

## 3. Design

### 3.1 Architecture: launcher wrapper

The package ships **two bash executables** (shebang `#!/usr/bin/env bash`) and a small **per-shell shim directory**, installed to one of these locations (probed at install time, first-writable wins). We use bash rather than `/bin/sh` because `/bin/sh` differs across macOS (bash-in-POSIX-mode) and Linux (often dash) on `printf` escape interpretation, and we already require Ghostty + tmux as hard prereqs — bash is the only additional shell dep and it's universally present on both OSes.

| OS | Preferred path | Fallback |
|---|---|---|
| macOS Apple Silicon w/ Homebrew | `/opt/homebrew/bin/` | `$HOME/.local/bin/` |
| macOS Intel w/ Homebrew | `/usr/local/bin/` | `$HOME/.local/bin/` |
| macOS w/o Homebrew | `$HOME/.local/bin/` | `/usr/local/bin/` (if writable; sudo prompt) |
| Linux w/ linuxbrew | `$HOMEBREW_PREFIX/bin/` | `$HOME/.local/bin/` |
| Linux distro-installed (Arch, Fedora, Ubuntu, etc.) | `$HOME/.local/bin/` | `/usr/local/bin/` (sudo prompt) |

The three executables (paths chosen by Homebrew convention: user-facing CLI in `bin/`, internal helpers in `libexec/`):

- `bin/ghostty-tmux-attach` — user-facing CLI (`init`, `uninstall`, `doctor`, `update`).
- `libexec/ghostty-tmux-attach-launch` — Ghostty's `command =` target. Runs the conditions check + OSC 7 emit + race-free allocator, then `exec`s tmux. Not on user's PATH.
- `libexec/ghostty-tmux-attach-shell` — tmux's `default-command` target. Detects `$SHELL`, wires up the right per-shell shim (ZDOTDIR for zsh, `--rcfile` for bash, plain exec for others), and `exec`s the user's shell. Not on user's PATH.

On curl-pipe installs without Homebrew, the layout collapses to `~/.local/bin/ghostty-tmux-attach` (CLI) and `~/.local/libexec/ghostty-tmux-attach/{launch,shell}` (helpers — the dir is created and added to absolute paths in Ghostty/tmux config; not added to PATH).

The shim directory at `${XDG_CONFIG_HOME:-$HOME/.config}/ghostty-tmux-attach/`:

```
zsh-shim/.zshrc        # ZDOTDIR target: sources Ghostty integration, chains to user's .zshrc
bash-shim/bashrc       # --rcfile target: sources Ghostty integration, chains to user's .bashrc
```

The Ghostty config is patched with:

```
command = </absolute/path/to>/ghostty-tmux-attach-launch
```

This makes the launcher run as Ghostty's direct child for **every** surface — cold-start and `window-save-state` restore alike. The user's tmux.conf gets `set -g default-command </path>/ghostty-tmux-attach-shell` so every new tmux pane wires up the right shim regardless of which shell they're on.

The Ghostty config is patched with:

```
command = </absolute/path/to>/ghostty-tmux-attach-launch
```

This makes the launcher run as Ghostty's direct child for **every** surface — cold-start and `window-save-state` restore alike. There is no "did the user fully Cmd+Q or just Cmd+W" ambiguity.

The launcher runs its conditions check, emits OSC 7 manually (Ghostty learns the cwd in time for save-state checkpoints), runs the race-free allocator, then `exec`s either tmux (success path) or the user's actual login shell (fallback path).

**No interactive-shell rc file (`.zshrc`, `.bashrc`, `.zshenv`, `.bash_profile`) is touched, ever.** That single design decision eliminates large classes of failure modes:

- Dotfile-manager (chezmoi/yadm/stow) sync conflicts on user-owned files.
- p10k-instant-prompt / starship / `compinit` ordering interactions in the user's shell-rc — though the inner-tmux shim still has to source Ghostty integration before chaining to user's `.zshrc`, so a related p10k hazard is documented in §5.1.
- The SSH-env trap: `shell-integration-features = ssh-env` forwards `GHOSTTY_RESOURCES_DIR` to remote shells, but those remote shells don't run our launcher — they run whatever the user normally runs over SSH. Remote behavior is unaffected.

(Sentinel-hash maintenance is **reduced, not eliminated** — §3.4 carries a 5-version hash table for the two patched config files. Architecture A would have carried the same for four files plus user-rc; that's the saved cost.)

### 3.2 The launcher (`libexec/ghostty-tmux-attach-launch`)

Bash (via `#!/usr/bin/env bash`). Lives in `libexec/` of the package (Homebrew convention: internal helpers, not on user PATH). Exec'd directly by Ghostty via the absolute path written into `~/.config/ghostty/config`'s `command =` line.

```bash
#!/usr/bin/env bash
# ghostty-tmux-attach-launch — Ghostty `command =` target
# Decides whether to exec tmux or the user's normal shell.

set -u

# --- Resolve user's login shell ---
# Used as the fallback exec target if any guard fails.
# $SHELL is set by every modern OS; if missing (exotic containers),
# fall back through getent (Linux) / dscl (macOS) / /bin/sh (universal).
GTA_USER_SHELL="${SHELL:-}"
if [ -z "$GTA_USER_SHELL" ]; then
  if command -v getent >/dev/null 2>&1; then
    GTA_USER_SHELL=$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f7)
  elif command -v dscl >/dev/null 2>&1; then
    GTA_USER_SHELL=$(dscl . -read "/Users/$(id -un)" UserShell 2>/dev/null | awk '{print $2}')
  fi
  : "${GTA_USER_SHELL:=/bin/sh}"
fi

# --- Decide log destination ---
GTA_DEBUG="${GHOSTTY_TMUX_ATTACH_DEBUG:-0}"
GTA_LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/ghostty-tmux-attach"
# Hoist dir creation to script-startup so per-line mkdir doesn't storm
# during multi-surface restore (10 surfaces × 8 guard lines = 80 mkdirs).
[ "$GTA_DEBUG" = "1" ] && mkdir -p "$GTA_LOG_DIR" 2>/dev/null
gta_log() {
  [ "$GTA_DEBUG" = "1" ] || return 0
  printf '[%s] [%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$$" "$*" \
    >> "$GTA_LOG_DIR/launch.log" 2>/dev/null
}

# --- Guard 1: TTY ---
# Multi-surface restore can race PTY allocation. Without a real TTY,
# tmux will print "open terminal failed: not a terminal" and the user
# gets a dead surface. Fall through to user's shell instead.
if ! { [ -t 0 ] && [ -t 1 ]; }; then
  gta_log "no TTY; exec user shell"
  exec "$GTA_USER_SHELL" -l
fi

# --- Guard 2: not nested under tmux ---
if [ -n "${TMUX:-}" ]; then
  gta_log "already in tmux; exec user shell"
  exec "$GTA_USER_SHELL" -l
fi

# --- Guard 3: not in an SSH session ---
# Defensive — ssh-env shouldn't propagate to Ghostty's command, but
# guard anyway in case future Ghostty versions change behavior.
if [ -n "${SSH_CONNECTION:-}" ] || [ -n "${SSH_CLIENT:-}" ] || [ -n "${SSH_TTY:-}" ]; then
  gta_log "SSH session; exec user shell"
  exec "$GTA_USER_SHELL" -l
fi

# --- Guard 4: configurable HOME skip ---
# Default: skip tmux for $HOME surfaces (parity with author's original
# setup; a fresh "just open a terminal at home" doesn't pin you to tmux).
# Set GHOSTTY_TMUX_ATTACH_SKIP_HOME=0 to disable.
if [ "${GHOSTTY_TMUX_ATTACH_SKIP_HOME:-1}" = "1" ] && [ "$PWD" = "$HOME" ]; then
  gta_log "PWD == HOME and SKIP_HOME=1; exec user shell"
  exec "$GTA_USER_SHELL" -l
fi

# --- Guard 5: tmux must be on PATH ---
# Because Ghostty respawns us without a login shell, PATH may not include
# /opt/homebrew/bin. Probe explicit common locations as a fallback.
if ! command -v tmux >/dev/null 2>&1; then
  for tmux_candidate in /opt/homebrew/bin/tmux /usr/local/bin/tmux; do
    if [ -x "$tmux_candidate" ]; then
      PATH="${tmux_candidate%/tmux}:$PATH"
      export PATH
      break
    fi
  done
fi
if ! command -v tmux >/dev/null 2>&1; then
  gta_log "tmux not found; exec user shell"
  exec "$GTA_USER_SHELL" -l
fi

# --- OSC 7 emit: tell Ghostty our cwd ---
# Bash does NOT set $HOST (only $HOSTNAME); we're a POSIX-sh launcher,
# so check both. URL-encode $PWD for safety (spaces, '#', etc).
GTA_HOST="${HOST:-${HOSTNAME:-$(hostname 2>/dev/null)}}"
GTA_PWD_ENC=$(gta_urlencode "$PWD")
printf '\033]7;kitty-shell-cwd://%s%s\a' "$GTA_HOST" "$GTA_PWD_ENC"
gta_log "OSC 7 emitted: $GTA_HOST $PWD"

# --- Allocate session name (see 3.3) ---
if ! gta_choose_session; then
  gta_log "allocator failed; exec user shell"
  exec "$GTA_USER_SHELL" -l
fi
gta_log "allocator chose: $GTA_CHOSEN"

# --- Pre-flight TTY re-check ---
if ! { [ -t 0 ] && [ -t 1 ]; }; then
  gta_log "TTY vanished post-allocator; exec user shell"
  exec "$GTA_USER_SHELL" -l
fi

# --- Mark that we're orchestrating, so the shell-wrapper knows to ---
# wire up its shim. The launcher itself never sets ZDOTDIR or --rcfile;
# those decisions live in ghostty-tmux-attach-shell (3.3a), which tmux
# invokes as default-command for each new pane.
export GHOSTTY_TMUX_ATTACH_ACTIVE=1
export GHOSTTY_USER_SHELL="$GTA_USER_SHELL"

# --- Close any leaked fds (defense in depth — see Notes) before exec ---
# Bash's `exec N>FILE` does NOT set FD_CLOEXEC, so if any earlier code
# path opened fd 9 (the flock path in 3.3 does), it would survive into
# tmux. Close it explicitly here to prevent tmux from inheriting our
# allocator lock fd.
exec 9>&- 2>/dev/null || true

# --- exec tmux (fall back to user's shell if tmux exec itself fails) ---
exec tmux new-session -A -s "$GTA_CHOSEN"
gta_log "exec tmux returned (unexpected); falling back to shell"
exec "$GTA_USER_SHELL" -l
```

Helper: `gta_urlencode` (percent-encode bytes outside the safe set, bash 4+ compatible):

```bash
gta_urlencode() {
  # Percent-encode anything outside RFC 3986 "unreserved" plus '/'
  # so paths survive the OSC 7 URI. LC_ALL=C makes byte iteration
  # deterministic (non-ASCII UTF-8 bytes get %XX-encoded).
  LC_ALL=C
  local s="$1" out="" i c
  for ((i=0; i<${#s}; i++)); do
    c=${s:i:1}
    case "$c" in
      [A-Za-z0-9._~/-]) out+="$c" ;;
      *) printf -v c '%%%02X' "'$c" ; out+="$c" ;;
    esac
  done
  printf '%s' "$out"
}
```

(Bash 3.2 fallback NOT supported in v0.1; macOS users on system bash 3.2 are asked via the installer to `brew install bash` and re-run. The launcher's shebang `#!/usr/bin/env bash` resolves to brew bash if installed; otherwise the installer warns at install time and refuses unless `--force`. See §5.1.)

Notes:

- `gta_choose_session` is in §3.3; the helper bodies live in `lib/allocator.sh`.
- Variables are namespaced `GTA_*`. The launcher exec's away on success, so any leakage is bounded by the brief fallback-to-shell path.
- Every fallback path is `exec "$GTA_USER_SHELL" -l`. The user never sees a "dead surface" — they either get tmux or a normal shell, never a stuck launcher process.

### 3.3 Race-free allocator (`gta_choose_session`)

Now that we ship a real binary, we use **real `flock(2)` via `flock -n`** (which IS available on macOS — it ships with `util-linux` as a brew dep, or we use `shlock(1)` from `procmail` as a fallback, or we use `mkdir`-based atomic locking as the universal floor). The flock approach is preferred when available because it auto-releases on process death — no PID-tuple tracking needed.

```sh
gta_choose_session() {
  GTA_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/ghostty-tmux-attach"
  GTA_LOCK_FILE="$GTA_ROOT/allocator.lock"

  # Sanitize base name: tmux is hostile to spaces, parens, dots.
  # LC_ALL=C so non-ASCII paths (e.g., ~/문서, ~/déploiement) don't trip
  # "Illegal byte sequence" on BSD `tr` — non-ASCII chars get folded to _.
  GTA_BASE=$(printf '%s' "${PWD##*/}" | LC_ALL=C tr -c 'A-Za-z0-9_-' '_')
  [ -n "$GTA_BASE" ] || GTA_BASE="root"

  # Create lock dir; fall back to $TMPDIR for read-only $HOME edge cases.
  if ! mkdir -p "$GTA_ROOT" 2>/dev/null; then
    GTA_ROOT="${TMPDIR:-/tmp}/ghostty-tmux-attach-$(id -u)"
    GTA_LOCK_FILE="$GTA_ROOT/allocator.lock"
    mkdir -p "$GTA_ROOT" 2>/dev/null || {
      gta_log "no writable cache dir; bailing"
      return 1
    }
  fi

  # Use mkdir-based atomic locking by default — works identically on
  # macOS and Linux. flock(1) is an OPTIONAL optimization: only used
  # when we detect util-linux's flock with -w support (Linux distros
  # ship it; macOS does NOT ship flock(1) in base — `brew install
  # util-linux` adds it but we don't assume the user installed it).
  if command -v flock >/dev/null 2>&1 && flock --version 2>/dev/null | grep -qi util-linux; then
    exec 9>"$GTA_LOCK_FILE"
    if ! flock -w 5 9; then
      gta_log "flock timeout; bailing"
      return 1
    fi
    gta_pick_session_name
    flock -u 9
    exec 9>&-
  else
    gta_mkdir_lock_and_pick
  fi

  return 0
}

gta_pick_session_name() {
  # Conflate-resistant: distinguish "session exists, no clients" (we may
  # safely attach to continuum-restored content) from "session does not
  # exist" (we create fresh). Use has-session and list-clients separately.
  GTA_CHOSEN="$GTA_BASE"
  GTA_IDX=1
  while :; do
    # Does the session exist at all?
    if ! tmux has-session -t "=$GTA_CHOSEN" 2>/dev/null; then
      # Doesn't exist — claim it. (Free to attach to.)
      break
    fi
    # Exists. Is anyone attached?
    if [ -z "$(tmux list-clients -t "=$GTA_CHOSEN" 2>/dev/null)" ]; then
      # Detached. We will attach and inherit continuum-restored content.
      break
    fi
    # Exists and has clients. Try next suffix.
    GTA_IDX=$((GTA_IDX + 1))
    GTA_CHOSEN="$GTA_BASE-$GTA_IDX"
  done
}

# gta_mkdir_lock_and_pick is the fallback when flock isn't installed.
# Uses atomic mkdir + a tuple-keyed claim file (PID + process start time)
# to prevent PID-reuse impostors. Fails closed if lock acquisition takes
# longer than 5s — never breaks the lock from a waiter (would re-create
# the mirroring bug).
```

Detailed `gta_mkdir_lock_and_pick` body is in the implementation; the key invariant is the same one the author already tested in their own dotfiles (the 5-process race test passes for both `mkdir` and `flock` variants).

`flock(1)` availability and our use of it:

- **Default everywhere is `mkdir`-based locking.** It's atomic on every POSIX filesystem on both macOS (APFS, HFS+) and Linux (ext4, btrfs, xfs, zfs). The 5-process race test in the author's own dotfiles validated correctness.
- **Linux:** `flock(1)` from `util-linux` is always present and gets used as a small performance optimization (fd-level locking, no spin loop). Both versions are equally correct.
- **macOS:** `flock(1)` is **not** in the base system; the launcher detects this and uses the mkdir path. `brew install util-linux` adds it but is never required.

The launcher detects util-linux flock specifically via `flock --version | grep -i util-linux` because BSD-style `flock(2)` semantics differ from the GNU `-w` flag we'd use; we'd rather fall back to mkdir than partially-support flock variants.

### 3.3a Shell wrapper (`ghostty-tmux-attach-shell`)

The launcher exec's tmux directly; tmux's `default-command` then invokes this script for every new pane **including the first window of a fresh `new-session`** (verified via test — see Section 7 fixme). This script handles the per-shell integration shim.

```bash
#!/usr/bin/env bash
# ghostty-tmux-attach-shell — tmux `default-command` target
# Wires up Ghostty shell-integration into each new tmux pane.

set -u

# Resolve the user's actual shell. Prefer GHOSTTY_USER_SHELL (set by the
# launcher in 3.2) over $SHELL because tmux's own $SHELL may be wrong if
# `chsh` happened mid-session.
GTAS_SHELL="${GHOSTTY_USER_SHELL:-${SHELL:-/bin/sh}}"
GTAS_NAME=$(basename "$GTAS_SHELL")
GTAS_SHIMS="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty-tmux-attach"

# Only wire up integration if our launcher orchestrated this surface.
# Otherwise (e.g., user runs `tmux` directly outside Ghostty), pass through.
if [ "${GHOSTTY_TMUX_ATTACH_ACTIVE:-0}" != "1" ] || [ -z "${GHOSTTY_RESOURCES_DIR:-}" ]; then
  exec "$GTAS_SHELL"
fi

case "$GTAS_NAME" in
  zsh)
    # ZDOTDIR shim: point at our dir, preserve user's original.
    SHIM="$GTAS_SHIMS/zsh-shim"
    if [ -r "$SHIM/.zshrc" ]; then
      export GHOSTTY_USER_ZDOTDIR="${ZDOTDIR:-$HOME}"
      export ZDOTDIR="$SHIM"
    fi
    exec "$GTAS_SHELL"
    ;;
  bash)
    # --rcfile shim. Interactive non-login bash reads --rcfile; that's
    # what tmux panes are.
    SHIM="$GTAS_SHIMS/bash-shim/bashrc"
    if [ -r "$SHIM" ]; then
      exec "$GTAS_SHELL" --rcfile "$SHIM"
    fi
    exec "$GTAS_SHELL"
    ;;
  fish|*)
    # Unknown shell: no shim. Document a manual snippet in README (5.x).
    exec "$GTAS_SHELL"
    ;;
esac
```

The two shim files (`zsh-shim/.zshrc` and `bash-shim/bashrc`) source Ghostty's integration script from `$GHOSTTY_RESOURCES_DIR/shell-integration/<shell>/ghostty-integration`, then chain to the user's actual rc (ZDOTDIR or `$HOME/.bashrc`).

### 3.4 What the installer patches (just 2 files)

| File | What's added | Idempotency |
|---|---|---|
| `~/.config/ghostty/config` | `command = </path>/ghostty-tmux-attach-launch`, `window-save-state = always`, `shell-integration = detect`, set-union of `shell-integration-features` with existing (preserves user's `cursor`/`title` if set) | Sentinel block + features-set merge |
| `~/.tmux.conf` | `set -g status on`, `set -g allow-passthrough on`, `set -g default-command "</path>/ghostty-tmux-attach-shell"`, **`set -ga update-environment ' GHOSTTY_TMUX_ATTACH_ACTIVE GHOSTTY_USER_SHELL'`** (so re-attaches preserve the orchestration marker), TPM bootstrap (only if absent), `set -g @plugin tmux-resurrect`, `set -g @plugin tmux-continuum`, `set -g @continuum-restore 'on'`, `set -g @continuum-save-interval '15'` — inserted **before** any existing `run '...tpm'` line, not at EOF. The `default-command` is what wires our shell-wrapper into every new pane. | Sentinel block + TPM-line scan + default-command override warning |

Sentinel format:

```
# >>> ghostty-tmux-attach@VERSION sha=HASH >>>
<patch body>
# <<< ghostty-tmux-attach <<<
```

Update logic: hash the **template** (the snippet before set-merging into the user's existing values), not the rendered output, so set-merge changes triggered by the user editing their original line don't cause hash-mismatch refusals on `--update`. The hash table maps `version → template-hash`; the installer regenerates rendered output from the template each time. Refuses on `--update` only if the user edited **inside** our sentinel block, not if their inputs (outside the sentinel) changed.

#### Hash table prune policy

`lib/known_hashes.sh` carries the **last 5 released versions' template hashes** for each patched file. Users updating directly from older versions (e.g., v0.7 user updates straight to v1.2 having skipped v0.8–v1.1) get an explicit error: `"Installed version is too old to safely auto-update; please re-run install: --force (clobbers) or curl-pipe a fresh install."` This bounds the table at constant size and frees us to refactor block contents over time.

#### Set-merge behavior on `--update`

The four states for a user's original `shell-integration-features` line (the only set-merged key in v0.1) are handled explicitly:

| State at `--update` | Behavior |
|---|---|
| Original line still commented out exactly as we wrote it | Re-parse the comment, re-union with current required set, write fresh union inside sentinel |
| Original line un-commented by user (now two active lines) | **Refuse with a clear message**: "your `shell-integration-features` outside our sentinel is now active and conflicts with ours. Either re-comment it (revert) or `--force` to let ours win." |
| Original line deleted (no comment, no live line) | Treat as clean slate: write required set inside sentinel, no commented annotation |
| Original line edited (still commented, contents changed) | Re-parse the new contents; re-union; write fresh union. (The annotation tag survives edits to the value.) |

Each path is unit-tested. The "two active lines" refusal is the one that genuinely needs human decision; everything else is mechanical.

Maintenance burden is much smaller than architecture A because the installer only owns blocks in 2 files instead of 4, and the user's interactive-shell rc files are never touched.

#### Set-merge for `shell-integration-features`

The Ghostty config grammar treats `key = value` as last-wins for scalar keys, and `shell-integration-features` is a comma-list. Appending our line after a user's existing line would **replace**, dropping whatever the user had set. Installer:

1. Parses the existing `shell-integration-features` value from outside our sentinel.
2. Computes the union with **our required set**: `sudo,ssh-terminfo,cursor,title`. (We deliberately do NOT include `ssh-env` — it's an opinionated forwarding feature unrelated to this package's correctness and may surprise users who SSH from Ghostty surfaces.)
3. Writes the union inside our sentinel; comments out the user's original line with a `# disabled by ghostty-tmux-attach: see sentinel below` annotation.

Uninstall reverses step 3: restores the user's commented-out line.

#### TPM-line aware tmux.conf insertion

If a user has TPM, their `~/.tmux.conf` ends with:

```
run '~/.tmux/plugins/tpm/tpm'
```

This line **must** be last. Continuum **must** be the last `@plugin` line.

Installer behavior:

1. Detect existing TPM `run` line; record its position.
2. Detect any existing `@plugin tmux-continuum` line; remove if outside our sentinel and re-add inside our sentinel.
3. Insert our sentinel block **before** the TPM `run` line.
4. If no TPM `run` line exists: append our sentinel + a TPM bootstrap block at EOF.
5. If a non-TPM plugin manager is detected (e.g., `antigen-tmux`): refuse to patch; print snippet for manual merge; doctor flags.

#### Newline normalization

Before any append, run `tail -c 1 <file>`; if not `\n`, prepend one. Applies to both files.

### 3.5 The installer

`install.sh` is the curl-pipe entry. It dispatches to:

- `install.sh init` (default) — detects OS (uname), patches both config files, installs launcher + shell-wrapper + shims per the table in 3.1.
- `install.sh init --dry-run` — outputs unified diff (`---`/`+++`) for each modified file + a flat `would-create: <path>` list for binaries/shims/snapshot. Writes nothing.
- `install.sh init --update` — sentinel-version aware update.
- `install.sh init --force` — bypasses user-edited-block check.
- `install.sh init --minimal` — installs the **C architecture** instead: single shared `main` session, ~5 lines of tmux.conf. For users who explicitly want simplicity.
- `install.sh uninstall` — surgical sentinel-block removal (default); add `--restore-snapshot` for full pre-install state restore (see 3.6).
- `install.sh doctor` — runs all guard checks against the current shell env; reads the two config files; reports state. Default human-readable; `--json` emits machine-readable.
- `install.sh` (no subcommand) — prints `--help` and exits 0. Never auto-runs `init`.

The user-facing `ghostty-tmux-attach` CLI (installed to `bin/`) is a thin wrapper that calls `install.sh` with the appropriate subcommand. Same behavior, same flags, same no-args-prints-help.

OS-aware behavior of `init`:

| Step | macOS | Linux |
|---|---|---|
| Detect tmux | `command -v tmux` + probe `$HOMEBREW_PREFIX/bin/tmux` + `/opt/homebrew/bin/tmux` + `/usr/local/bin/tmux` | `command -v tmux` only (distro pkg manager handles PATH) |
| Detect Ghostty resources dir | `/Applications/Ghostty.app/Contents/Resources/ghostty` (or via `$GHOSTTY_RESOURCES_DIR` if set) | `/usr/share/ghostty` / `/usr/lib/ghostty` / `$HOME/.local/share/ghostty` probe, or via `$GHOSTTY_RESOURCES_DIR` |
| Brew probe | Required | Optional (skipped unless linuxbrew detected) |
| Install path | `$HOMEBREW_PREFIX/bin/` if brew, else `$HOME/.local/bin/` | `$HOME/.local/bin/` by default; `/usr/local/bin/` with sudo prompt if requested |
| Suggest pkg install on missing tmux | `brew install tmux` | `apt install tmux` / `pacman -S tmux` / `dnf install tmux` (per distro detection) |

#### Refusal cases (install.sh aborts with a clear error)

- **WSL2 / WSL1**: detected via `grep -qi microsoft /proc/version` (or `/proc/sys/kernel/osrelease`). Ghostty doesn't run on Windows yet; installing here is a footgun. Error: `"Ghostty doesn't ship on Windows yet; install on the host OS instead."`
- **Docker / OCI container**: detected via `[ -f /.dockerenv ]` or `grep -q docker /proc/1/cgroup`. Same reason. Error: `"This installer can't run inside a container; install on the host."`
- **macOS via Rosetta on Apple Silicon**: detected via `sysctl -in sysctl.proc_translated`. We DON'T refuse here — we adjust: probe BOTH `/opt/homebrew` and `/usr/local` regardless of `uname -m`, prefer whichever has tmux.

The Homebrew formula installs the launcher + shell-wrapper to `$HOMEBREW_PREFIX/bin/` and ships `ghostty-tmux-attach` as a convenience CLI that calls `install.sh` subcommands. Works on macOS Homebrew and linuxbrew.

### 3.6 Backups and uninstall

Snapshot taken at install time:

```
$HOME/.local/share/ghostty-tmux-attach/snapshots/<timestamp>/
  ghostty-config
  tmux.conf
```

Keep last 3; prune older.

`uninstall` defaults to **surgical sentinel-block removal**, not snapshot restore. Reasoning: a user who edits `~/.tmux.conf` post-install would lose those edits if we restored a pre-install snapshot. Surgical removal:

1. Find each `# >>> ghostty-tmux-attach@... >>>` / `# <<< ghostty-tmux-attach <<<` block; delete in place.
2. For commented-out original lines marked `# disabled by ghostty-tmux-attach: see sentinel below`: uncomment.
3. Remove `~/.config/ghostty-tmux-attach/`, the launcher + shell-wrapper binaries, the cache dir.
4. **Purge continuum's resurrect saves** that contain our marker. Continuum saves pane env at save time; restored panes wake up with `GHOSTTY_TMUX_ATTACH_ACTIVE=1` baked in and try to source a shim that no longer exists. Uninstall scans `${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect/` (and the legacy `~/.tmux/resurrect/`) for saves whose contents reference our env marker and `mv`s them to `<dir>/uninstalled-<timestamp>/` (preserved for forensics, not deleted). Doctor warns if any resurrect file references our marker pre-uninstall.

`uninstall --restore-snapshot` is the opt-in nuclear path that restores from the most recent snapshot — for when the user wants exact pre-install state and accepts losing post-install edits. Snapshots are taken **only at install time**, not on `--update`. So `--restore-snapshot` after a sequence install→update→update→uninstall restores the pre-original-install state, not the pre-most-recent-update state. Documented in `--help`.

### 3.7 Observability

- `doctor` checks (per OS):
  - **macOS**: brew installed, tmux installed (via brew or system), Ghostty 1.3+ installed (`/Applications/Ghostty.app` present), bash version (3.2 warning, 4+ pass), system tmux conflict probe.
  - **Linux**: tmux installed (via `command -v tmux`), distro detected via `/etc/os-release`, Ghostty installed (probe `/usr/share/ghostty`, `/usr/lib/ghostty`, `$HOME/.local/share/ghostty`, `~/.local/share/flatpak/exports/share/ghostty` for flatpak), SELinux/AppArmor enforcing mode (warning — may block shim exec).
  - **Both**: the two config files exist and contain our sentinels with current-version hashes; launcher + shell-wrapper binaries are at the expected paths and executable; shim files exist; cache dir is writable; chezmoi detected (warning); WSL/Docker detected (refusal); continuum resurrect files probed for stale `GHOSTTY_TMUX_ATTACH_ACTIVE` marker.
- For OSC 7: doctor emits a sample escape sequence and prints what it sent; **doctor does NOT claim to verify Ghostty received it** (Ghostty has no query API for "what cwd did you last save?"). User can confirm by `cmd+S` + restart + observe restored cwd.
- **Output format**: default is human-readable with colored ✓/✗/warning markers (color disabled if `NO_COLOR=1` or `!isatty`). `doctor --json` emits a stable schema (versioned, documented in `docs/doctor-schema.md`) for scripting and 3rd-party integration.
- `GHOSTTY_TMUX_ATTACH_DEBUG=1`: launcher writes every guard decision and lock event to `${XDG_STATE_HOME:-$HOME/.local/state}/ghostty-tmux-attach/launch.log`. Disabled by default.

### 3.8 Minimal mode (C, opt-in)

For users who want maximum simplicity and don't care about per-surface independence:

```
install.sh init --minimal
```

Patches **only `~/.tmux.conf`** with continuum + resurrect + status, plus this one line in Ghostty config (path resolved per OS):

```
command = <absolute-path-to-tmux> new-session -A -s main
```

(absolute path picked at install time; on macOS Apple Silicon: `/opt/homebrew/bin/tmux`; on Intel Mac: `/usr/local/bin/tmux`; on Linux: result of `command -v tmux`).

That's it. No launcher, no allocator, no OSC 7 emit, no shell-wrapper. All Ghostty surfaces attach to `main`. Splits mirror. For independent content, the user uses tmux splits inside.

README documents the tradeoffs. v0.1 ships both modes.

#### Mode-switching matrix

| Current state | Command run | Behavior |
|---|---|---|
| Not installed | `init` | Fresh main-mode install |
| Not installed | `init --minimal` | Fresh minimal-mode install |
| Main mode installed | `init` | No-op (idempotent), or `--update` if hash differs |
| Main mode installed | `init --minimal` | Print uninstall-then-install plan with `--dry-run`; refuse without `--force` |
| Minimal mode installed | `init` | Print uninstall-then-install plan with `--dry-run`; refuse without `--force` |
| Minimal mode installed | `init --minimal` | No-op (idempotent), or update if needed |
| Either mode installed | `uninstall` | Removes the active mode's blocks; preserves the other's snapshot (only relevant if user ever switched modes, which `--force` allows) |

Doctor reports current mode in its summary line.

### 3.9 Repo layout

```
ghostty-tmux-attach/
├── README.md            install (main + minimal), what-it-does, FAQ
├── LICENSE              MIT
├── CHANGELOG.md         keep-a-changelog format
├── install.sh           curl-pipe entry
├── bin/
│   ├── ghostty-tmux-attach          CLI: init / uninstall / doctor / update
│   ├── ghostty-tmux-attach-launch   Ghostty `command =` target (3.2)
│   └── ghostty-tmux-attach-shell    tmux `default-command` target (3.3a)
├── lib/
│   ├── allocator.sh        flock + mkdir fallback allocator
│   ├── patches.sh          ghostty/tmux config patching helpers
│   ├── os_detect.sh        macOS vs Linux + distro detection
│   └── known_hashes.sh     table of released block hashes for safe update
├── shim/
│   ├── zsh/
│   │   └── .zshrc          ZDOTDIR target: source Ghostty integration, chain to user's .zshrc
│   └── bash/
│       └── bashrc          --rcfile target: source Ghostty integration, chain to user's .bashrc
├── snippets/
│   ├── ghostty.conf        exact lines for sentinel block
│   ├── tmux.conf           exact lines for sentinel block (main mode)
│   └── tmux.conf.minimal   exact lines for sentinel block (minimal mode)
├── test/
│   ├── race.sh             5-process race test
│   ├── shellcheck.sh       lints all .sh files
│   ├── osc7-roundtrip.sh   stub OSC 7 emitter test
│   └── shim-chain.sh       verify zsh-shim and bash-shim correctly chain to user rc
├── .github/workflows/
│   └── ci.yml              v0.1 baseline (8 cells):
│                             macos-15 (zsh + bash 5+)
│                             ubuntu-24.04 (zsh + bash 5+)
│                             tmux 3.4 only
│                             Plus: shellcheck on all .sh; telemetry-grep gate.
│                           v0.2+ extends matrix to macos-14, ubuntu-22.04,
│                           tmux 3.2a + 3.3a + 3.5.
└── docs/
    └── architecture.md     links to upstream issues (3.10)
```

Sibling repo `homebrew-tap/` with `Formula/ghostty-tmux-attach.rb`.

### 3.10 Upstream filings (parallel to shipping)

- **Ghostty:** "Shell-integration OSC 7 only fires on precmd/chpwd; scripts that `exec` in `.zshrc` before first prompt never report cwd to `window-save-state`. Suggest OSC 7 emit at shell-integration init, or a documented escape that scripts can emit manually." Reference our package as workaround.
- **tmux-continuum:** "When multiple clients race `new-session -A -s NAME` on server start, content can be cross-attached. Document the race or add a per-session attach lock." Reference our package as workaround.

If either lands, the package shrinks. The launcher architecture means we can shrink without users having to do anything — just `brew upgrade`.

### 3.10a Release flow (homebrew tap maintenance)

Every release to `ghostty-tmux-attach` requires a corresponding formula update in the `homebrew-tap` repo. The release flow:

1. Tag in main repo: `git tag v0.x.y && git push --tags`.
2. GitHub Actions release workflow:
   - Builds tarball from the tag.
   - Computes sha256.
   - Opens a PR in `leegunwoo98/homebrew-tap` updating `Formula/ghostty-tmux-attach.rb` with new url + sha256 (using `brew bump-formula-pr --no-browse --strict`).
3. `homebrew-tap` CI:
   - Runs `brew install --build-from-source` on `macos-15` and `ubuntu-24.04`.
   - Runs `brew test ghostty-tmux-attach`.
   - Auto-merges on green; flags maintainer on red.

The CLI's `ghostty-tmux-attach update` subcommand does NOT auto-bump brew; it warns "for brew installs, run `brew upgrade`."

### 3.11 Excluded from v0.1 (deferred)

- **`@continuum-restore on` race with auto-attach.** Documented in README; mitigation deferred to v0.2.
- **macOS bash 3.2 support.** Doctor refuses; install prompt for `brew install bash`. v0.2 may add a 3.2-compatible `gta_urlencode`.
- **Windows support.** Pending Ghostty Windows availability.
- **Native distro packaging** (AUR, Nix flake, .deb, RPM, Home Manager module). Community contributions welcome.
- **Curl-pipe checksum verification flag.** v0.1 README documents `curl … | shasum -a 256 -c -` manually; v0.2 adds `--verify`.
- **CI matrix expansion beyond the 8-cell v0.1 baseline.** Adding tmux 3.2a + 3.3a + 3.5, macos-14, ubuntu-22.04, Arch, Fedora deferred.
- **Flatpak Ghostty support.** Sandboxed `GHOSTTY_RESOURCES_DIR` requires Flatpak-specific resource exposure; defer.

(Fish shell auto-integration was deferred in an earlier draft but the manual snippet in §5.1 is the documented v0.1 answer; not "deferred," just "supported by docs not code.")

## 4. Failure modes

| Failure | Surface | Behavior |
|---|---|---|
| Launcher binary missing or not executable | Botched install or moved binary | Ghostty surface starts → exec fails → user sees error in Ghostty's "command failed" UI. Doctor catches at install time. |
| `command -v tmux` fails | User installs without tmux | Launcher falls back to `exec $SHELL -l`; doctor warns at install time |
| Cache dir unwritable | Locked-down corporate MDM Mac | Falls back to `$TMPDIR/ghostty-tmux-attach-$UID`; doctor logs |
| Allocator timeout (5s) | Heavy disk pressure | Falls back to `exec $SHELL -l` with `gta_log` warning |
| flock unavailable | User without `util-linux` brew dep | Falls back to mkdir-based locking; same correctness, slightly slower |
| TTY race during restore | Multi-surface simultaneous restore | Pre-flight `[ -t 0 ] && [ -t 1 ]` falls back to shell |
| Bash without `$HOST` | First bash session post-install | Falls back through `$HOSTNAME`, then `$(hostname)` |
| SSH inside Ghostty | User SSHes from a Ghostty surface | Only relevant inside tmux (not at launcher level); remote shells don't run our launcher |
| User edits sentinel block | Customization | `--update` refuses; prints diff; offers `--force` |
| Non-TPM tmux plugin manager | Power user | Installer skips tmux.conf patch; prints snippet; doctor flags |
| User's existing `shell-integration-features` is non-default | Customization | Installer set-unions; preserves user's `cursor`/`title`; uninstall reverses |
| Ghostty config missing | Fresh install never ran Ghostty | Installer creates `~/.config/ghostty/config` with full sentinel block |
| Ghostty changes `command =` semantics | Future Ghostty update | Launcher detection via env or args; doctor flags; `brew upgrade` ships fix |
| `GHOSTTY_RESOURCES_DIR` not set or wrong path on Linux | Distro packages Ghostty in non-standard location | Installer probes common locations + lets user override via `--ghostty-resources-dir=PATH`; doctor verifies the shim's `source` path resolves |
| Linux user has no `~/.local/bin` in PATH | Some distros require explicit XDG addition | Installer adds an explicit note to the install summary; suggests adding `export PATH="$HOME/.local/bin:$PATH"` to `~/.profile`. (Note: `~/.profile` is a *login-shell* rc, distinct from the interactive-shell rcs `.zshrc` / `.bashrc` we never touch. Our promise is "no interactive-shell rc patching"; `~/.profile` advice is something the user runs themselves, not the installer.) |
| `flock` from util-linux conflicts with BSD-style flock | Theoretical edge case on macOS with both installed | We use `flock -w 5 fd` syntax which is Linux-flock-only; on macOS we either use brew util-linux's flock, or fall back to mkdir locking. Doctor detects which is active. |
| Linuxbrew user has both system tmux and brew tmux | Two tmux binaries on PATH | Installer picks the first one on PATH; doctor flags the duplicate and recommends one. Snapshotted for uninstall. |
| Distro tmux is older than 3.2 (no `allow-passthrough`) | Old Ubuntu / RHEL | Installer detects tmux version at install time; warns if <3.2; sentinel block omits `allow-passthrough` line on too-old tmux |

### Linux-specific failure modes

| Failure | Surface | Behavior |
|---|---|---|
| SELinux / AppArmor in enforcing mode blocks shim exec | RHEL, Fedora, Ubuntu hardened | doctor detects (`getenforce` returns Enforcing, `aa-status`); warns at install time; suggests `chcon -t bin_t` (SELinux) or apparmor profile addition. Falls back to bare shell if blocked at runtime. |
| Flatpak Ghostty has sandboxed `GHOSTTY_RESOURCES_DIR` | Flatpak install of Ghostty | Resources dir is inside the Flatpak sandbox and not host-visible. doctor warns; recommends native install. v0.1 may not work with Flatpak Ghostty. |
| Wayland-only session, no `DISPLAY` env | Modern Linux desktops | Irrelevant — tmux and shells don't need X. No failure. |
| Non-glibc systems (Alpine, musl) | Some containerized envs | bash exists; tmux exists; should work. Untested in v0.1 CI. |
| `getenforce` / `aa-status` not installed | Minimal distros | doctor falls back to "could not detect security module"; warning. |
| `/proc` not mounted | Exotic chroots | WSL/Docker detection becomes a `[ -f /.dockerenv ]` check only; doctor warns; install proceeds. |
| `/usr/bin/env bash` not present | Old/exotic distro | doctor fails clearly: "bash not found via /usr/bin/env; install bash 4+." |
| Distro tmux is custom-patched | Some Arch users (`tmux-3.4-vendor`) | Hash-based feature detection rather than version-string parsing — already done. |

## 4a. Verification gates (run before v0.1 tag)

The review surfaced three claims in this spec that I currently believe are correct but haven't measured. Each must pass a real test before we tag v0.1; if any fails, this section gets a "what we shipped instead" entry and the design adjusts.

### V1. tmux `default-command` applies to the first window of `new-session`

**Claim:** `set -g default-command "<shell-wrapper>"` is honored by tmux's `new-session`, so the very first pane in a fresh session is launched through our wrapper.

**Why it could be wrong:** tmux's `default-shell` and `default-command` interact in version-dependent ways. If `default-shell` is set with arguments (e.g., `/bin/bash -l`), some tmux versions ignore `default-command` for the initial window.

**Test:** spin up a fresh `tmux.conf` with only `set -g default-command "echo HELLO; exec $SHELL"`, run `tmux new-session`, confirm `HELLO` appears in the first pane.

**Fallback if false:** launcher splits the `-A` semantics. NOTE: `tmux new-session -A -- COMMAND` ignores `COMMAND` when `-A` attaches to an existing session — so we can't trust `--` for both branches. Instead:

```bash
if tmux has-session -t "=$GTA_CHOSEN" 2>/dev/null; then
  exec tmux attach -t "=$GTA_CHOSEN"
else
  exec tmux new-session -s "$GTA_CHOSEN" "$SHELL_WRAPPER"
fi
```

This guarantees: if the session exists (continuum restored it or another surface created it), we attach to existing panes that already ran through the wrapper. If creating fresh, we pass the wrapper explicitly. Section 3.2 updated accordingly if V1 fails.

### V2. bash `--rcfile` survives the user's `default-shell` override

**Claim:** the shell-wrapper's `exec bash --rcfile "$SHIM"` correctly sources our shim even if the user has set `set -g default-shell "/bin/bash -l"` in their tmux.conf.

**Why it could be wrong:** `bash --rcfile` is documented for **interactive non-login** bash. A login bash reads `~/.bash_profile` → `~/.bashrc` and the spec is silent on whether `--rcfile` is honored there.

**Test:** `tmux.conf` with `set -g default-shell /bin/bash` (and separately `-l`) + `default-command "bash --rcfile /tmp/test-shim"` where the shim prints `SHIM SOURCED`. Confirm `SHIM SOURCED` appears in the first pane in both configurations.

**Fallback if false:** shell-wrapper detects login mode (`$0` starts with `-`) and uses `BASH_ENV` + `INPUTRC` instead, OR forces non-login by `exec bash --rcfile "$SHIM"` regardless and documents that login-bash semantics are not preserved inside tmux panes.

### V3. Ghostty `env = KEY=VALUE` config syntax exists and works

**Claim:** users can set `env = GHOSTTY_TMUX_ATTACH_SKIP_HOME=0` in their Ghostty config to opt into HOME-surface auto-attach (Section 5.5).

**Why it could be wrong:** I haven't verified this against Ghostty 1.3.1 docs. The user's existing config uses `keybind = X = Y` and `command = X` — `env = X=Y` may or may not be a supported directive.

**Test:** read Ghostty 1.3.1 docs for `env` / `env-vars` / similar; if not supported, find the real escape hatch.

**Fallback if false:** the launcher reads optional `~/.config/ghostty-tmux-attach/config` for settings like `SKIP_HOME=0`. Section 5.5 advice updated.

### V4. tmux `set -ga update-environment` leading-space-append works on tmux 3.2

**Claim:** `set -ga update-environment ' GHOSTTY_TMUX_ATTACH_ACTIVE GHOSTTY_USER_SHELL'` (with leading space) appends the two variable names to the existing space-separated list on tmux 3.2 (Ubuntu 22.04 archive) and later.

**Why it could be wrong:** tmux's `-ga` append semantics for string options have shifted across versions; the leading-space convention may be parsed as part of the value on 3.2.

**Test:** on a fresh tmux 3.2 install, `tmux start; tmux set -g update-environment 'FOO BAR'; tmux set -ga update-environment ' BAZ QUX'; tmux show -gv update-environment` — confirm output is `FOO BAR BAZ QUX` not `FOO BAR BAZ QUX` mangled or with literal leading space.

**Fallback if false:** installer reads existing value via `tmux show -gv update-environment` at install time, computes union with our required vars, writes the full union explicitly via `set -g update-environment "<union>"` inside the sentinel.

### V5. install.sh contains no outbound network calls beyond the documented download URL

**Claim:** the package is telemetry-free; the only network call is the curl-pipe download itself.

**Why it could be wrong:** a contributor adds an `analytics` or `version-check` ping; the grep-based verification is a regression backstop.

**Test:** CI greps `install.sh` and all `lib/` files for `curl|wget|nc|http://` — only the documented download URL line (in a comment) and the `command -v curl` probe should match.

**Fallback if false:** the matched line is either justified (add to allowlist) or removed.

## 5. Recommendations & Known Gaps

This section documents situations where the package can't auto-handle everything, and what users should do. Doctor surfaces all of these at install time and on demand (`ghostty-tmux-attach doctor`).

### 5.1 Shells

**Zsh** (any version with `precmd_functions` hook support — 5.0+): fully supported. ZDOTDIR shim handles all integration.

**p10k-instant-prompt hazard**: powerlevel10k's "instant prompt" feature requires being the **first** output to stdout in the user's `.zshrc`. Our shim sources Ghostty's integration *before* chaining to the user's `.zshrc`; Ghostty's integration prints OSC escape sequences which p10k-instant-prompt treats as "real output" and complains about loudly. Three workarounds (documented in install summary and on doctor detection):

- Move p10k-instant-prompt initialization **before** any other source / `[[ -f ... ]] && source ...` in `.zshrc` — but our shim still runs before the entire `.zshrc`, so this doesn't actually help.
- Disable instant-prompt: `p10k configure` → choose non-instant mode. Recommended for users who want the package's full integration.
- Suppress the warning: `typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet` near the top of `.zshrc`. Functional but the warning's there for a reason; you may miss real issues.

doctor detects `powerlevel10k` presence (any `~/.p10k.zsh` or `POWERLEVEL9K_*` env vars) and flags the issue at install time.

**`setopt no_global_rcs` in user's `.zshrc`**: not relevant. Global rcs are `/etc/zshenv`, `/etc/zshrc`, etc. Our shim is in `ZDOTDIR`, not `/etc`. No contract breach.

**Bash 4.0+**: required (v0.1). Linux distros ship bash 4+ or 5+. On macOS the system bash is 3.2 (Apple stopped updating after the GPLv3 license change); v0.1 **does not support** bash 3.2 — the launcher's `gta_urlencode` uses bash 4+ `printf -v` semantics. Doctor refuses install on macOS if `$SHELL` is `/bin/bash` (3.2) and recommends:

> "macOS ships bash 3.2 which v0.1 does not support. Run `brew install bash`, then `chsh -s /opt/homebrew/bin/bash` (or `/usr/local/bin/bash` on Intel) and re-run the installer. Or use zsh, which is the macOS default since Catalina."

(v0.2 may revisit bash 3.2 with a pure-bash-3.2 urlencode implementation if there's demand.)

**Fish**: not auto-integrated in v0.1. The shell-wrapper falls through to `exec $SHELL`, so fish runs normally but without Ghostty's per-prompt cwd / mark reporting. Documented manual snippet for `~/.config/fish/config.fish`:

```fish
if status is-interactive
  and set -q GHOSTTY_RESOURCES_DIR
    source $GHOSTTY_RESOURCES_DIR/shell-integration/fish/vendor_conf.d/ghostty-shell-integration.fish
end
```

Add this AFTER any other plugin-manager init. v0.2 may add a fish-shim if requested by enough users.

**Nushell / Xonsh / Elvish / other shells**: not supported. Falls through to plain exec.

### 5.2 Dotfile managers

The package writes **only** to `~/.config/ghostty/config`, `~/.tmux.conf`, and `~/.config/ghostty-tmux-attach/` (plus the binary install path). Most dotfile managers either ignore `~/.config/ghostty-tmux-attach/` by default or treat it as a generated dir.

**chezmoi**: two safe paths, pick one:

- **Option A (recommended)**: add `dot_config/ghostty/config` and `dot_tmux.conf` to chezmoi's `.chezmoiignore`. We manage those files; chezmoi leaves them alone. This is the cleanest division of labor.
- **Option B**: extract our sentinel block from `~/.tmux.conf` and `~/.config/ghostty/config` into chezmoi `.chezmoitemplate` partials and reference them from your managed config files. This makes chezmoi the source of truth and our `--update` will refuse on next run because the captured block won't match our hash — manage updates manually after each `brew upgrade`.

**Do NOT use `chezmoi re-add` after install**: it would capture our post-install state into chezmoi's source, but the next `--update` we ship would refuse because the stored hash wouldn't match what chezmoi now holds. You'd end up with a divergent set of "our block" instances.

Doctor detects chezmoi via `[ -d "${XDG_DATA_HOME:-$HOME/.local/share}/chezmoi" ]` and warns at install time.

**yadm / stow / dotfiles**: similar pattern. Add the package's files to ignore, or re-stage after install.

**Nix Home Manager**: the package writes to user-owned files that home-manager controls. Recommendation: use the curl-pipe one-time install for the shim+binaries but copy our sentinel blocks INTO your home-manager modules and let home-manager manage them. Future work (v0.2): ship a home-manager flake.

### 5.3 SSH and remote sessions

The launcher runs as Ghostty's `command =` target — it executes **locally**, never on a remote host. When you SSH from a Ghostty surface, the remote shell runs normally; nothing on the remote host needs to be installed.

**Caveat**: if `shell-integration-features` includes `ssh-env` (we don't add it by default, but you may have it from before), `GHOSTTY_RESOURCES_DIR` and similar vars get forwarded to the remote. This is harmless unless the remote shell tries to load Ghostty's integration script from that path — which it can't, because the script doesn't exist on the remote. Remote shells run normally.

If you want the remote shell to ALSO report cwd to your Ghostty surface (so when you `cd` on a remote machine, Ghostty's titlebar updates), follow Ghostty's official SSH integration docs — that's not in scope for this package.

### 5.4 tmux plugin managers other than TPM

The installer detects TPM via a **grep against `~/.tmux.conf`** for `run ['"][^'"]*tpm['"]` — not a path check on disk. This avoids false positives where TPM is cloned to disk but not actually wired in. If grep finds a match, we treat it as TPM-managed; otherwise we treat it as no-plugin-manager and insert our block + a fresh TPM bootstrap. If you use:

- **Antigen-tmux**: installer refuses to patch tmux.conf, prints our sentinel block, asks you to add it manually somewhere your plugin manager won't fight. Doctor flags this and points at this section.
- **Manual `set -g @plugin` without TPM**: same as antigen — manual merge.
- **`tmux-fzf` or other helpers that wrap plugin lists**: works as long as TPM is the underlying runner.

### 5.5 `$HOME` workflow

By default the package does NOT auto-attach when you open a Ghostty surface in `$HOME` directly. This preserves the "fresh terminal at home for quick tasks" pattern. To opt in:

```sh
# In your environment (NOT in shell rc — set this in Ghostty config):
# env = GHOSTTY_TMUX_ATTACH_SKIP_HOME=0
```

Ghostty supports `env = KEY=VALUE` in its config to set env vars for all surfaces it spawns.

### 5.6 Custom `shell-integration-features`

If you already have `shell-integration-features = X,Y,Z` in your Ghostty config, the installer **set-unions** it with the package's required set (`sudo,ssh-terminfo,cursor,title`). Your existing values are preserved. If you specifically want to OPT OUT of one we add (say, `title`), edit the union inside our sentinel block — re-running `--update` will refuse to clobber until you `--force`.

We deliberately do NOT add `ssh-env`. If you want it, add it back inside our sentinel (it's opinionated forwarding that's unrelated to our package's correctness).

### 5.7 macOS Gatekeeper and the launcher binary

The launcher and shell-wrapper are POSIX-sh scripts, not Mach-O binaries — they don't require code signing or Gatekeeper exceptions. If you've enabled "Lock Down Mode" (Apple's hardened security profile), shell scripts run normally; Ghostty's `command =` invocation is unaffected.

### 5.8 Debugging recipes

When things don't work as expected, in order:

1. **`ghostty-tmux-attach doctor`** — checks all prereqs, config files, binary paths, cache dir, and roundtrips OSC 7. Reports plain English of what's wrong.
2. **`GHOSTTY_TMUX_ATTACH_DEBUG=1`** — set this in your Ghostty config (`env = GHOSTTY_TMUX_ATTACH_DEBUG=1`) and reopen Ghostty. Every guard decision and allocator event is logged to `~/.local/state/ghostty-tmux-attach/launch.log` with timestamps. Most "why didn't it attach?" questions answer themselves from this log.
3. **`tmux list-sessions`** in a working surface — confirms continuum's saved sessions are present.
4. **Lock dir reset**: `rm -rf ~/.cache/ghostty-tmux-attach` if anything seems stuck. The allocator self-clears stale state too, but the manual escape hatch is fast.
5. **Re-run install with `--dry-run`** to see what would change without writing.

### 5.9 When to NOT use this package

- You only ever use one Ghostty window, attached to one tmux session, and don't care about restore — use the **minimal mode** (`--minimal`) or just put `tmux attach || tmux new` in your shell rc by hand.
- You're a tmux-purist who uses tmux splits exclusively and doesn't care about native Ghostty splits — same answer: minimal mode or nothing.
- You're on Windows / fish-exclusive / use a non-Ghostty terminal — out of scope.
- You hand-manage your `~/.tmux.conf` with strong opinions about plugin order and continuum settings — the installer's tmux.conf patching is the most invasive part; review the snippet (`install.sh init --dry-run`) before letting it write.

## 6. Open questions

None blocking.

## 7. Future work (v0.2+)

- Fish shell auto-integration via fish-shim.
- Windows support (pending Ghostty Windows).
- AUR package, Nix flake, Home Manager module, .deb / RPM.
- Checksum-verified snapshot uninstall.
- `--verify` flag for curl-pipe install.
- Continuum auto-restore + auto-attach interaction mitigation.
- Optional sesh integration as session picker on top of per-cwd sessions.
- Bash/zsh/fish completion for the CLI.
- CI matrix expansion to tmux 3.5, older macOS, Arch, Fedora, RHEL.

## 8. Why this architecture (summary of review verdict)

Two independent subagent reviews picked B (launcher) over A (zshrc-source) and C (single-session). Key reasoning:

- **A's structural problem is that it edits `.zshrc`.** Every failure mode traces back to that one decision: dotfile-manager clobbering, debugging-by-reading-someone's-config, sentinel-hash-table-growing-monotonically-forever, CI matrix of 72+ cells (shell × rc-framework × tmux × arch × macOS).
- **B isolates logic in a package-owned binary.** Every fix is `brew upgrade` — users don't notice. CI matrix shrinks materially. LOC + test burden is roughly half of A. Deprecation when Ghostty ships native restore is `brew uninstall` + revert two lines.
- **B's one real risk** is Ghostty's shell-integration auto-injection looking at the direct child process and skipping our non-shell launcher. Mitigation: a `default-command` shell-wrapper (3.3a) that wires up the right per-shell shim (ZDOTDIR for zsh, `--rcfile` for bash) in every new tmux pane. Known, scoped, recurring-zero concern.
- **C is shipped as opt-in `--minimal`** for users who prefer simplicity over per-surface independence. Costs ~20 LOC to support.

### Scope widening (post-review)

After the architecture review, the scope was deliberately widened along three axes:

- **Linux added** to v0.1 (macOS + Ubuntu 22.04/24.04 in CI; other distros best-effort via the same POSIX sh code path).
- **Bash auto-integration added** to v0.1 via the `default-command` shell-wrapper that detects `$SHELL` and applies the right shim. Previously v0.2.
- **Recommendations & Known Gaps section** (5) added to document fish, dotfile managers, SSH, plugin managers, `$HOME` workflow, custom `shell-integration-features`, Gatekeeper, debugging, and when NOT to use the package — so users have clear guidance for anything we can't auto-fix.
