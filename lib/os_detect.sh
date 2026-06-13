#!/usr/bin/env bash
# os_detect.sh — sourced by install.sh, doctor, and tests.
# Exports: GTA_OS, GTA_ARCH, GTA_HOMEBREW_PREFIX, GTA_IS_WSL, GTA_IS_DOCKER,
#         GTA_IS_ROSETTA, GTA_DISTRO (linux only), GTA_GHOSTTY_RESOURCES.

# OS
case "$(uname -s)" in
  Darwin) GTA_OS=macos ;;
  Linux)  GTA_OS=linux ;;
  *)      GTA_OS=unknown ;;
esac

# Architecture
case "$(uname -m)" in
  arm64|aarch64) GTA_ARCH=arm64 ;;
  x86_64|amd64)  GTA_ARCH=x86_64 ;;
  *)             GTA_ARCH=unknown ;;
esac

# WSL: /proc/version contains 'microsoft'
GTA_IS_WSL=0
if [ -r /proc/version ] && grep -qi microsoft /proc/version 2>/dev/null; then
  GTA_IS_WSL=1
fi

# Docker / OCI container
GTA_IS_DOCKER=0
if [ -f /.dockerenv ] || \
   ([ -r /proc/1/cgroup ] && grep -qE 'docker|kubepods' /proc/1/cgroup 2>/dev/null); then
  GTA_IS_DOCKER=1
fi

# Rosetta (macOS only)
GTA_IS_ROSETTA=0
if [ "$GTA_OS" = macos ]; then
  if [ "$(sysctl -in sysctl.proc_translated 2>/dev/null || echo 0)" = "1" ]; then
    GTA_IS_ROSETTA=1
  fi
fi

# Homebrew prefix (probe regardless of arch — Rosetta means uname can lie)
GTA_HOMEBREW_PREFIX=""
for candidate in /opt/homebrew /usr/local /home/linuxbrew/.linuxbrew; do
  if [ -x "$candidate/bin/brew" ]; then
    GTA_HOMEBREW_PREFIX="$candidate"
    break
  fi
done

# Linux distro
GTA_DISTRO=""
if [ "$GTA_OS" = linux ] && [ -r /etc/os-release ]; then
  GTA_DISTRO=$(. /etc/os-release && printf '%s' "${ID:-unknown}")
fi

# Ghostty resources dir (allow env override)
GTA_GHOSTTY_RESOURCES="${GHOSTTY_RESOURCES_DIR:-}"
if [ -z "$GTA_GHOSTTY_RESOURCES" ]; then
  if [ "$GTA_OS" = macos ]; then
    for candidate in \
      /Applications/Ghostty.app/Contents/Resources/ghostty \
      "$HOME/Applications/Ghostty.app/Contents/Resources/ghostty"; do
      [ -d "$candidate" ] && GTA_GHOSTTY_RESOURCES="$candidate" && break
    done
  else
    for candidate in \
      /usr/share/ghostty /usr/lib/ghostty \
      "$HOME/.local/share/ghostty" \
      "$HOME/.local/share/flatpak/exports/share/ghostty"; do
      [ -d "$candidate" ] && GTA_GHOSTTY_RESOURCES="$candidate" && break
    done
  fi
fi

export GTA_OS GTA_ARCH GTA_HOMEBREW_PREFIX GTA_IS_WSL GTA_IS_DOCKER
export GTA_IS_ROSETTA GTA_DISTRO GTA_GHOSTTY_RESOURCES
