# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
