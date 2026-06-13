#!/usr/bin/env bash
# install.sh — curl-pipe entry point and CLI dispatcher for ghostty-tmux-attach.

set -euo pipefail

GTA_VERSION="0.1.0-dev"
GTA_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export GTA_VERSION GTA_SCRIPT_DIR

usage() {
  cat <<USAGE
ghostty-tmux-attach $GTA_VERSION

Usage:
  ghostty-tmux-attach <command> [options]

Commands:
  init                 Install (default: main mode). Patches Ghostty config + ~/.tmux.conf.
  init --minimal       Install minimal mode (single shared 'main' session, no per-cwd).
  init --dry-run       Show diffs without writing.
  init --update        Update an existing install to the current shipped version.
  init --force         Bypass user-edited-block check.
  uninstall            Remove sentinels + binaries. Does NOT restore pre-install state.
  uninstall --restore-snapshot
                       Restore from the install-time snapshot (loses post-install edits).
  doctor               Report prereq + config state. --json for machine-readable.
  --version            Print version and exit.
  --help               Show this help.

See https://github.com/gunwoo/ghostty-tmux-attach for docs.
USAGE
}

main() {
  if [ $# -eq 0 ]; then usage; exit 0; fi
  case "$1" in
    --version) echo "ghostty-tmux-attach $GTA_VERSION"; exit 0 ;;
    --help|-h) usage; exit 0 ;;
    init)      shift; cmd_init "$@" ;;
    uninstall) shift; cmd_uninstall "$@" ;;
    doctor)    shift; cmd_doctor "$@" ;;
    *) echo "Unknown command: $1" >&2; usage >&2; exit 2 ;;
  esac
}

cmd_init() { echo "init not yet implemented" >&2; exit 99; }
cmd_uninstall() { echo "uninstall not yet implemented" >&2; exit 99; }
cmd_doctor() {
  local json=0
  while [ $# -gt 0 ]; do
    case "$1" in --json) json=1; shift ;; *) shift ;; esac
  done

  # shellcheck source=/dev/null
  . "$GTA_SCRIPT_DIR/lib/os_detect.sh"

  local tmux_path tmux_ver=""
  tmux_path=$(command -v tmux 2>/dev/null || true)
  if [ -n "$tmux_path" ]; then
    tmux_ver=$("$tmux_path" -V 2>/dev/null | awk '{print $2}')
  fi

  local ghostty_present=0
  [ -n "$GTA_GHOSTTY_RESOURCES" ] && ghostty_present=1

  local bash_major="${BASH_VERSION%%.*}"

  if [ "$json" -eq 1 ]; then
    cat <<JSON
{
  "version": "$GTA_VERSION",
  "os": "$GTA_OS",
  "arch": "$GTA_ARCH",
  "is_wsl": $GTA_IS_WSL,
  "is_docker": $GTA_IS_DOCKER,
  "is_rosetta": $GTA_IS_ROSETTA,
  "distro": "${GTA_DISTRO:-}",
  "homebrew_prefix": "${GTA_HOMEBREW_PREFIX:-}",
  "tmux_path": "${tmux_path:-}",
  "tmux_version": "${tmux_ver:-}",
  "ghostty_resources": "${GTA_GHOSTTY_RESOURCES:-}",
  "bash_major": "$bash_major"
}
JSON
    return 0
  fi

  echo "ghostty-tmux-attach $GTA_VERSION — doctor"
  echo
  if [ "$GTA_IS_ROSETTA" = "1" ]; then
    echo "OS:          $GTA_OS / $GTA_ARCH (Rosetta)"
  else
    echo "OS:          $GTA_OS / $GTA_ARCH"
  fi
  if [ -n "$GTA_DISTRO" ]; then
    echo "Distro:      $GTA_DISTRO"
  fi
  echo "Homebrew:    ${GTA_HOMEBREW_PREFIX:-<not found>}"
  if [ -n "$tmux_path" ]; then
    echo "tmux:        $tmux_path ($tmux_ver)"
  else
    echo "tmux:        NOT FOUND — install via brew/apt/pacman/dnf"
  fi
  if [ "$ghostty_present" -eq 1 ]; then
    echo "Ghostty:     $GTA_GHOSTTY_RESOURCES"
  else
    echo "Ghostty:     NOT FOUND — install from https://ghostty.org"
  fi
  echo "bash:        major version $bash_major (need 4+)"
  if [ "$GTA_IS_WSL" = "1" ]; then
    echo "WSL:         detected — install refuses"
  fi
  if [ "$GTA_IS_DOCKER" = "1" ]; then
    echo "Docker:      detected — install refuses"
  fi
}

main "$@"
