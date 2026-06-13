# ghostty-tmux-attach

Make Ghostty's `window-save-state = always` restore actually re-attach to tmux sessions instead of dropping you at a plain `$HOME` shell.

[![CI](https://github.com/gunwoo/ghostty-tmux-attach/actions/workflows/ci.yml/badge.svg)](https://github.com/gunwoo/ghostty-tmux-attach/actions/workflows/ci.yml)

## What it does

Ghostty 1.3+ can restore windows, tabs, and splits across `Cmd+Q`. For tmux users, the restored shells should land back inside their tmux sessions — but by default they don't, because of three independent traps:

1. **PATH gap.** Ghostty's restore respawns non-login shells; brew isn't on `PATH`; `tmux` isn't found.
2. **OSC 7 timing.** Auto-attach scripts `exec` tmux before the first prompt; Ghostty never learns the surface's cwd.
3. **Allocator race.** Simultaneous restore of N surfaces races on per-cwd session names; all attach to the same session; panes mirror.

This package solves all three with a launcher binary wired into Ghostty's `command =`, a tmux `default-command` shell-wrapper that sets up per-shell shims, and a race-free session allocator using `mkdir`-based atomic locking + PID-tuple claim files.

**No interactive-shell rc file (`.zshrc`, `.bashrc`, etc.) is touched, ever.**

## Install

### curl-pipe (recommended)

```sh
curl -fsSL https://raw.githubusercontent.com/gunwoo/ghostty-tmux-attach/main/install.sh | bash -s -- init
```

Idempotent. Re-run safely.

### Homebrew

```sh
brew tap gunwoo/tap
brew install gunwoo/tap/ghostty-tmux-attach
ghostty-tmux-attach init
```

Per Homebrew norms, the formula installs binaries; `init` patches your configs.

## Quickstart

After install:

1. **Cmd+Q** to fully quit Ghostty (not Cmd+W).
2. Reopen.
3. Each restored surface lands inside its previously-bound tmux session, named after the cwd basename (e.g., `~/Documents/foo` → tmux session `foo`).

## Modes

| Mode | What it does | Choose if |
|---|---|---|
| **main** (default) | Per-cwd tmux sessions; each Ghostty surface is independent; splits in the same dir get `-2`/`-3` suffixes | You want different Ghostty surfaces showing different content |
| **minimal** (`init --minimal`) | All surfaces attach to a single `main` session; splits mirror; use tmux splits (`prefix + \|`) for independent content | You're a tmux purist who prefers tmux splits over Ghostty splits |

## Uninstall

```sh
ghostty-tmux-attach uninstall
```

Surgical sentinel-block removal by default. User edits outside the sentinel block (added pre- OR post-install) are preserved.

```sh
ghostty-tmux-attach uninstall --restore-snapshot
```

Full restore to pre-install state. Loses post-install edits.

## Doctor

```sh
ghostty-tmux-attach doctor          # human-readable
ghostty-tmux-attach doctor --json   # machine-readable
```

Reports prereq state, config sentinel hashes, OS detection, known gaps.

## Debugging

```sh
GHOSTTY_TMUX_ATTACH_DEBUG=1 ghostty   # or set env=GHOSTTY_TMUX_ATTACH_DEBUG=1 in Ghostty config
```

Launcher logs every guard decision to `~/.local/state/ghostty-tmux-attach/launch.log`.

If anything seems stuck:

```sh
rm -rf ~/.cache/ghostty-tmux-attach   # clears allocator state; safe to do anytime
```

## Recommendations & known gaps

See [`docs/architecture.md`](docs/architecture.md#5-recommendations--known-gaps) for guidance on:

- **Shells**: zsh, bash 4+, fish. macOS system bash 3.2 not supported in v0.1 — `brew install bash` and use that.
- **Dotfile managers** (chezmoi / yadm / stow / home-manager): the package writes only to `~/.config/ghostty/config`, `~/.tmux.conf`, and `~/.config/ghostty-tmux-attach/`. See `docs/architecture.md` §5.2 for chezmoi-specific advice.
- **SSH and remote sessions**: the launcher runs only as Ghostty's direct child — SSH'd remote shells run normally.
- **tmux plugin managers other than TPM** (antigen-tmux, etc.): installer skips tmux.conf patch and prints the snippet for manual merge.
- **`$HOME` workflow**: by default the package doesn't auto-attach when you open a surface at `$HOME`. Toggle with `GHOSTTY_TMUX_ATTACH_SKIP_HOME=0` in Ghostty's `env =` config line.
- **p10k instant-prompt**: our shim sources Ghostty integration before chaining to your `.zshrc`, which p10k-instant-prompt may complain about. Three workarounds in §5.1.

## Future work

- **zmx backend** (when [neurosnap/zmx#76](https://github.com/neurosnap/zmx/issues/76) ships reboot-persistence). zmx is a cleaner persistence layer built on libghostty-vt; today it doesn't survive reboot, so it's not a tmux replacement for our use case.
- **Linux brew prefix probe** (Asahi Linux specifics).
- **Curl-pipe `--verify` flag** for checksum validation.
- **Bash 3.2 support** via pure-bash-3.2 urlencode.
- **CI matrix expansion** to tmux 3.2a + 3.3a + 3.5, older macOS, Arch, Fedora.

## License

MIT. See [`LICENSE`](LICENSE).
