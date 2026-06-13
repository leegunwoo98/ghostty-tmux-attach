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

cmd_init() {
  local dry_run=0 force=0 update=0 minimal=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) dry_run=1; shift ;;
      --force)   force=1; shift ;;
      --update)  update=1; shift ;;
      --minimal) minimal=1; shift ;;
      *) echo "unknown init flag: $1" >&2; exit 2 ;;
    esac
  done

  # shellcheck source=/dev/null
  . "$GTA_SCRIPT_DIR/lib/os_detect.sh"
  # shellcheck source=/dev/null
  . "$GTA_SCRIPT_DIR/lib/patches.sh"

  # Refusal cases
  if [ "$GTA_IS_WSL" = "1" ]; then
    echo "Refusing: WSL detected. Ghostty does not ship on Windows yet; install on the host OS." >&2
    exit 3
  fi
  if [ "$GTA_IS_DOCKER" = "1" ]; then
    echo "Refusing: container detected. Install on the host OS." >&2
    exit 3
  fi

  # macOS bash version check (allow override via --force)
  if [ "$GTA_OS" = "macos" ] && [ "${BASH_VERSION%%.*}" -lt 4 ]; then
    if [ "$force" -eq 0 ]; then
      echo "Refusing: macOS bash $BASH_VERSION (need bash 4+). Run: brew install bash" >&2
      echo "Or rerun with --force to ignore." >&2
      exit 4
    fi
  fi

  # Minimal mode is Phase 7b — stub for now
  if [ "$minimal" -eq 1 ]; then
    echo "minimal mode not yet implemented (Phase 7b)" >&2
    exit 99
  fi

  # Resolve install paths.
  # Test/override hook: GTA_INSTALL_PREFIX wins if set.
  # Otherwise: prefer $HOMEBREW_PREFIX if its bin/ is writable; else ~/.local.
  local install_prefix
  if [ -n "${GTA_INSTALL_PREFIX:-}" ]; then
    install_prefix="$GTA_INSTALL_PREFIX"
  elif [ -n "$GTA_HOMEBREW_PREFIX" ] && [ -w "$GTA_HOMEBREW_PREFIX/bin" ]; then
    install_prefix="$GTA_HOMEBREW_PREFIX"
  else
    install_prefix="$HOME/.local"
  fi
  local bin_dir="$install_prefix/bin"
  local libexec_dir="$install_prefix/libexec/ghostty-tmux-attach"
  local share_dir="$install_prefix/share/ghostty-tmux-attach"
  local lib_dir="$share_dir/lib"
  local shim_dir="$share_dir/shim"
  local snippets_dir="$share_dir/snippets"

  local launch_path="$libexec_dir/ghostty-tmux-attach-launch"
  local wrapper_path="$libexec_dir/ghostty-tmux-attach-shell"
  local ghostty_cfg="$HOME/.config/ghostty/config"
  local tmux_cfg="$HOME/.tmux.conf"

  # Set-union of user's existing shell-integration-features with our required set
  local existing_features=""
  if [ -e "$ghostty_cfg" ]; then
    existing_features=$(awk -F'= *' '
      /^shell-integration-features *=/ && !/disabled by ghostty-tmux-attach/ { print $2; exit }
    ' "$ghostty_cfg")
  fi
  local required_features="sudo,ssh-terminfo,cursor,title"
  local merged_features
  merged_features=$(gta_set_union "$existing_features" "$required_features")

  # Render snippet bodies
  local ghostty_body
  ghostty_body=$(sed -e "s|__LAUNCH__|$launch_path|g" \
                     -e "s|__FEATURES__|$merged_features|g" \
                     "$GTA_SCRIPT_DIR/snippets/ghostty.conf")
  local tmux_body
  tmux_body=$(sed -e "s|__SHELL_WRAPPER__|$wrapper_path|g" \
                   "$GTA_SCRIPT_DIR/snippets/tmux.conf")

  if [ "$dry_run" -eq 1 ]; then
    echo "--- $ghostty_cfg (current)"
    echo "+++ $ghostty_cfg (after init)"
    echo "(would add sentinel block:)"
    printf '%s\n' "$ghostty_body" | sed 's/^/+ /'
    echo
    echo "--- $tmux_cfg (current)"
    echo "+++ $tmux_cfg (after init)"
    echo "(would add sentinel block:)"
    printf '%s\n' "$tmux_body" | sed 's/^/+ /'
    echo
    echo "would-create: $launch_path"
    echo "would-create: $wrapper_path"
    echo "would-create: $shim_dir/zsh/.zshrc"
    echo "would-create: $shim_dir/bash/bashrc"
    echo "would-create: $lib_dir/allocator.sh"
    echo "would-create: $lib_dir/os_detect.sh"
    echo "would-create: $lib_dir/patches.sh"
    echo "would-create: $lib_dir/known_hashes.sh"
    return 0
  fi

  # Snapshot
  local snap_dir
  snap_dir="$HOME/.local/share/ghostty-tmux-attach/snapshots/$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p "$snap_dir"
  if [ -e "$ghostty_cfg" ]; then
    cp "$ghostty_cfg" "$snap_dir/ghostty-config"
  fi
  if [ -e "$tmux_cfg" ]; then
    cp "$tmux_cfg" "$snap_dir/tmux.conf"
  fi

  # Install binaries + lib + shims + snippets
  mkdir -p "$bin_dir" "$libexec_dir" "$lib_dir" "$shim_dir/zsh" "$shim_dir/bash" "$snippets_dir"
  cp "$GTA_SCRIPT_DIR/libexec/ghostty-tmux-attach-launch" "$launch_path"
  cp "$GTA_SCRIPT_DIR/libexec/ghostty-tmux-attach-shell" "$wrapper_path"
  cp "$GTA_SCRIPT_DIR/lib/allocator.sh" "$lib_dir/"
  cp "$GTA_SCRIPT_DIR/lib/os_detect.sh" "$lib_dir/"
  cp "$GTA_SCRIPT_DIR/lib/patches.sh" "$lib_dir/"
  cp "$GTA_SCRIPT_DIR/lib/known_hashes.sh" "$lib_dir/"
  cp "$GTA_SCRIPT_DIR/shim/zsh/.zshrc" "$shim_dir/zsh/.zshrc"
  cp "$GTA_SCRIPT_DIR/shim/bash/bashrc" "$shim_dir/bash/bashrc"
  cp -R "$GTA_SCRIPT_DIR/snippets/." "$snippets_dir/"
  chmod +x "$launch_path" "$wrapper_path"

  # Comment out user's existing shell-integration-features line (outside sentinel)
  if [ -n "$existing_features" ] && [ -e "$ghostty_cfg" ]; then
    local tmp
    tmp=$(mktemp)
    awk '
      /^shell-integration-features *=/ && !/^# / && !marked {
        print "# disabled by ghostty-tmux-attach: see sentinel below"
        print "# " $0
        marked=1
        next
      }
      { print }
    ' "$ghostty_cfg" > "$tmp"
    mv "$tmp" "$ghostty_cfg"
  fi

  # Write sentinels
  gta_patch_write "$ghostty_cfg" "$GTA_VERSION" "$ghostty_body"
  gta_patch_write "$tmux_cfg" "$GTA_VERSION" "$tmux_body"

  echo "Installed. Restart Ghostty to take effect."
  echo "Run 'ghostty-tmux-attach doctor' to verify."
}
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
