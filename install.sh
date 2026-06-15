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

See https://github.com/leegunwoo98/ghostty-tmux-attach for docs.
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

  # --update: verify existing sentinel's hash matches the current shipped
  # snippet. If not, the user has hand-edited inside the sentinel; refuse
  # unless --force was passed.
  if [ "$update" -eq 1 ] && [ "$force" -eq 0 ]; then
    local files=("ghostty:$HOME/.config/ghostty/config" "tmux-main:$HOME/.tmux.conf")
    local entry snippet_id file found ver hash body body_hash
    for entry in "${files[@]}"; do
      snippet_id="${entry%%:*}"
      file="${entry#*:}"
      [ -e "$file" ] || continue
      found=$(gta_patch_version_hash "$file")
      [ -n "$found" ] || continue
      ver="${found%% *}"
      hash="${found##* }"
      body=$(gta_patch_read "$file")
      body_hash=$(gta_patch_hash "$body")
      if [ "$body_hash" != "$hash" ]; then
        echo "Refusing --update: sentinel in $file appears edited by hand." >&2
        echo "Either re-run with --force (clobbers) or restore the sentinel block." >&2
        exit 5
      fi
    done
  fi

  # Minimal mode: single shared 'main' session. No launcher, allocator,
  # or shell-wrapper. Just continuum-backed tmux + one Ghostty command line.
  if [ "$minimal" -eq 1 ]; then
    local tmux_path
    tmux_path=$(command -v tmux 2>/dev/null || true)
    if [ -z "$tmux_path" ]; then
      for c in /opt/homebrew/bin/tmux /usr/local/bin/tmux /usr/bin/tmux; do
        if [ -x "$c" ]; then tmux_path="$c"; break; fi
      done
    fi
    if [ -z "$tmux_path" ]; then
      echo "Refusing: tmux not found. Install tmux first." >&2
      exit 6
    fi

    local ghostty_cfg="$HOME/.config/ghostty/config"
    local tmux_cfg="$HOME/.tmux.conf"

    local minimal_ghostty_body
    minimal_ghostty_body=$(printf 'command = %s new-session -A -s main\nwindow-save-state = always' "$tmux_path")
    local minimal_tmux_body
    minimal_tmux_body=$(cat "$GTA_SCRIPT_DIR/snippets/tmux.conf.minimal")

    if [ "$dry_run" -eq 1 ]; then
      echo "--- $ghostty_cfg (current)"
      echo "+++ $ghostty_cfg (after init --minimal)"
      printf '%s\n' "$minimal_ghostty_body" | sed 's/^/+ /'
      echo
      echo "--- $tmux_cfg (current)"
      echo "+++ $tmux_cfg (after init --minimal)"
      printf '%s\n' "$minimal_tmux_body" | sed 's/^/+ /'
      return 0
    fi

    local snap_dir
    snap_dir="$HOME/.local/share/ghostty-tmux-attach/snapshots/$(date -u +%Y%m%dT%H%M%SZ)"
    mkdir -p "$snap_dir"
    if [ -e "$ghostty_cfg" ]; then
      cp "$ghostty_cfg" "$snap_dir/ghostty-config"
    fi
    if [ -e "$tmux_cfg" ]; then
      cp "$tmux_cfg" "$snap_dir/tmux.conf"
    fi

    gta_patch_write "$ghostty_cfg" "$GTA_VERSION" "$minimal_ghostty_body"
    gta_patch_write "$tmux_cfg" "$GTA_VERSION" "$minimal_tmux_body"

    echo "Installed (minimal mode). Restart Ghostty to take effect."
    return 0
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
cmd_uninstall() {
  local restore_snapshot=0
  while [ $# -gt 0 ]; do
    case "$1" in --restore-snapshot) restore_snapshot=1; shift ;; *) shift ;; esac
  done

  # shellcheck source=/dev/null
  . "$GTA_SCRIPT_DIR/lib/patches.sh"
  # shellcheck source=/dev/null
  . "$GTA_SCRIPT_DIR/lib/os_detect.sh"

  local ghostty_cfg="$HOME/.config/ghostty/config"
  local tmux_cfg="$HOME/.tmux.conf"
  local did_restore=0

  if [ "$restore_snapshot" -eq 1 ]; then
    local snap_root="$HOME/.local/share/ghostty-tmux-attach/snapshots"
    local latest=""
    if [ -d "$snap_root" ]; then
      latest=$(ls -1 "$snap_root" 2>/dev/null | sort | tail -1)
    fi
    if [ -z "$latest" ]; then
      echo "No snapshot found; falling back to surgical removal." >&2
    else
      if [ -e "$snap_root/$latest/ghostty-config" ]; then
        cp "$snap_root/$latest/ghostty-config" "$ghostty_cfg"
      fi
      if [ -e "$snap_root/$latest/tmux.conf" ]; then
        cp "$snap_root/$latest/tmux.conf" "$tmux_cfg"
      fi
      echo "Restored from snapshot $latest"
      did_restore=1
    fi
  fi

  if [ "$did_restore" -eq 0 ]; then
    gta_patch_remove "$ghostty_cfg"
    gta_patch_remove "$tmux_cfg"
    # Un-comment "disabled by ghostty-tmux-attach: see sentinel below" annotations.
    # Pattern is two lines: a marker comment, then "# <original line>".
    local f tmp
    for f in "$ghostty_cfg" "$tmux_cfg"; do
      [ -e "$f" ] || continue
      tmp=$(mktemp)
      awk '
        /^# disabled by ghostty-tmux-attach/ { prev_was_marker=1; next }
        prev_was_marker { sub(/^# /, ""); prev_was_marker=0 }
        { print }
      ' "$f" > "$tmp"
      mv "$tmp" "$f"
    done
  fi

  # Remove installed binaries + shims + lib + snippets (probe all known prefixes)
  local prefix
  for prefix in "${GTA_INSTALL_PREFIX:-}" "${GTA_HOMEBREW_PREFIX:-}" "$HOME/.local"; do
    [ -n "$prefix" ] || continue
    rm -rf "$prefix/libexec/ghostty-tmux-attach" 2>/dev/null || true
    rm -rf "$prefix/share/ghostty-tmux-attach" 2>/dev/null || true
  done

  # Purge continuum resurrect saves containing our marker.
  local resurrect_dir stash moved f2
  for resurrect_dir in \
    "${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect" \
    "$HOME/.tmux/resurrect"; do
    [ -d "$resurrect_dir" ] || continue
    stash="$resurrect_dir/uninstalled-$(date -u +%Y%m%dT%H%M%SZ)"
    moved=0
    for f2 in "$resurrect_dir"/*.txt; do
      [ -e "$f2" ] || continue
      if grep -q "GHOSTTY_TMUX_ATTACH_ACTIVE" "$f2" 2>/dev/null; then
        if [ "$moved" -eq 0 ]; then
          mkdir -p "$stash"
          moved=1
        fi
        mv "$f2" "$stash/"
      fi
    done
  done

  rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/ghostty-tmux-attach"

  echo "Uninstalled. Restart Ghostty for the change to take effect."
}
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
