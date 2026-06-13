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
cmd_doctor() { echo "doctor not yet implemented" >&2; exit 99; }

main "$@"
