# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Archived] — 2026-06-15

### Project archived — post-mortem

After one week of personal dogfooding (v0.1.0 → v0.1.3, three patch releases), the
architecture proved structurally too fragile to ship as a general tool. Archiving
in favor of a libghostty-based successor.

**What the architecture required.** Per-cwd tmux session inheritance under Ghostty's
`window-save-state` only works if five layers align in lockstep:

1. Launcher binary at Ghostty `command =` (right path, right shebang, right exit codes)
2. tmux `default-command` directive loaded into the right server instance
3. Per-pane shell-wrapper firing (depends on `default-command` actually triggering)
4. ZDOTDIR shim wiring (depends on env-marker propagating through `update-environment`)
5. DCS-passthrough OSC 7 hook in the shim (depends on shim having loaded)

If any layer fails, the symptom is "wrong cwd, wrong session" — silently. The bugs
that surfaced in dogfooding were all manifestations of one of these layers degrading:

- **v0.1.1** — Installer never copied the CLI dispatcher; bash 3.2 shebang trap on macOS
  (launchd's PATH doesn't resolve `/usr/bin/env bash` to brew bash)
- **v0.1.2** — Catastrophic data loss when default install prefix `/opt/homebrew` was
  rolled back by a failed `brew install`
- **v0.1.3** — User `.zshrc` re-sourcing Ghostty integration clobbered the shim's OSC 7 wrap
- **Continuum-restored panes** bypass `default-command` entirely (resurrect spawns the
  recorded command), so the shim never loads on restore — meaning new panes spawned
  from restored ones can't propagate cwd
- **Nondeterministic Cmd+D cwd inheritance** — the same surface, same parent, would
  sometimes inherit current cwd and sometimes the launch-time cwd, depending on
  timing in tmux's session env vs the running pane's env

The core issue is that OSC 7 cwd propagation across the Ghostty↔tmux boundary requires
shell-escape-sequence tricks that tmux is allowed to intercept, transform, or drop.
Each fix added a layer; each layer added a failure mode.

**Why a libghostty successor avoids this.** A session manager that talks to Ghostty's
own C API (like [zmx](https://github.com/neurosnap/zmx)) owns session state directly:

- No OSC 7 forwarding chain — pane cwd is queried from the surface
- No `default-command` vs continuum tug-of-war — the manager owns session lifecycle
- No five-layer shim — one binary, one state file
- Reboot persistence becomes a single well-defined feature (serialize on quit,
  restore on launch), not a multi-tool coordination problem

This repo is preserved as a reference. The code that holds up best:
`lib/allocator.sh` (race-free POSIX `link(2)` allocator with PID+start-time tuples),
`lib/patches.sh` (sentinel-versioned config block patching), and the bats-core
test harness.

## [0.1.3] — 2026-06-15

### Fixed
- **zsh shim's tmux-DCS OSC 7 wrap was clobbered by user `.zshrc` re-sourcing Ghostty integration.** Legacy/manual setups where users have `if [[ -n "$TMUX" ]]; then source ".../ghostty-integration"; fi` in their `.zshrc` re-registered the plain `_ghostty_report_pwd` AFTER the shim's override, defeating the wrap. Visible symptom: new Ghostty panes inherit the launch-time cwd instead of the current cwd, and attach to a "previous" session matching the original launch dir. Fix: shim now uses `add-zsh-hook chpwd/precmd _gta_tmux_osc7` for a SEPARATE function that survives re-sources. Regression test added.

## [0.1.2] — 2026-06-15

### Fixed
- **Catastrophic data loss when installing alongside brew.** `install.sh` defaulted to `/opt/homebrew` as the install prefix whenever brew was present and the bin dir was writable. brew owns that path. Any subsequent `brew install` of this formula (even a *failed* one — e.g., the Xcode CLI Tools transition error) triggers brew's rollback, which wipes the entire install dir, including files written by `install.sh`. End-user symptom: Ghostty fails to launch after Cmd+Q reopen with `cannot execute: No such file or directory`. Fix: install prefix defaults to `$HOME/.local`; `/opt/homebrew` is only used when brew has already installed the formula's binaries there (probed via `-x` on the expected launcher path).

## [0.1.1] — 2026-06-15

### Fixed
- **Installer never copied `bin/ghostty-tmux-attach`** to the install dir. After v0.1.0 install, the CLI dispatcher was missing — `ghostty-tmux-attach doctor` would print `command not found`. Discovered via dogfooding.
- **Launcher + shell-wrapper shebangs** (`#!/usr/bin/env bash`) resolved to system bash 3.2 under Ghostty's `command =` exec context, because launchd's PATH is `/usr/bin:/bin`. The launcher's `printf -v` urlencode requires bash 4+. Fix: install-time shebang rewrite to the absolute path of the bash that ran install.sh.

## [0.1.0] — 2026-06-15

### Added
- **Launcher binary** (`libexec/ghostty-tmux-attach-launch`) as Ghostty `command =` target. Handles guards (TTY, TMUX, SSH, PWD!=HOME, tmux on PATH), OSC 7 emit with bash-4+ urlencode, allocator integration, fd-hygiene before exec.
- **Shell-wrapper** (`libexec/ghostty-tmux-attach-shell`) as tmux `default-command` target. Detects `$SHELL` and applies the appropriate shim (zsh ZDOTDIR / bash `--rcfile` / pass-through for fish+others).
- **Race-free per-cwd session allocator** (`lib/allocator.sh`). POSIX `link(2)`-based atomic claim + PID+start-time tuples to defeat PID-reuse impostors. Validated with 5-process race test (50/50 stress runs, no flakes).
- **OSC 7 cwd emission** wrapped in tmux DCS-passthrough format inside tmux, so new Ghostty panes/tabs inherit the active tmux pane's current cwd rather than the outer shell's launch-time cwd.
- **zsh ZDOTDIR shim** and **bash --rcfile shim** for inner-tmux Ghostty integration sourcing + user-rc chaining.
- **Installer** (`install.sh`, `bin/ghostty-tmux-attach`) with `init`, `uninstall`, `doctor`, `update`, `dry-run`, `force`, `minimal` subcommands.
- **Sentinel-versioned patches** with template-hash refusal of hand-edited blocks (`--update`).
- **Set-merge** for `shell-integration-features` preserving user values (cursor/title/etc.).
- **Surgical uninstall** preserves user content; opt-in `--restore-snapshot` for full pre-install revert.
- **Continuum resurrect file purge** on uninstall (so old saves don't carry our env marker).
- **OS detection** (`lib/os_detect.sh`): macOS (Apple Silicon + Intel + Rosetta) + Linux (x86_64 + arm64). WSL2/Docker refusal.
- **Doctor with `--json` output** (stable schema for scripting).
- **CI matrix** (8 cells): macos-15 + ubuntu-24.04 × tmux 3.4, with shellcheck + V5 telemetry-grep gate.
- **96 tests** across unit / integration / race / e2e categories using bats-core.

### Limitations
- macOS bash 3.2 not supported (use `brew install bash` and `chsh`).
- Flatpak Ghostty's sandboxed `GHOSTTY_RESOURCES_DIR` may not be detected.
- Fish shell: pass-through; manual snippet documented in `docs/architecture.md`.
- Continuum's 15-min default save interval applies — work done in the final minutes before quit may not survive reboot.

### Deferred to v0.2+
- `zmx` backend as an alternative to tmux+continuum (pending [zmx#76](https://github.com/neurosnap/zmx/issues/76) shipping reboot-persistence).
- AUR / Nix / Home Manager / `.deb` / RPM packaging.
- Checksum-verified snapshot uninstall.
- `--verify` flag for curl-pipe download integrity.
- Tmux 3.2a / 3.3a / 3.5 in CI matrix.
- Linux SELinux/AppArmor + Flatpak Ghostty support.

## [Unreleased]

Tracked here pending the first tagged release.
