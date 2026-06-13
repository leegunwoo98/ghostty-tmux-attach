#!/usr/bin/env bats
# Tests for lib/os_detect.sh

load '../helpers/common'

@test "os_detect exports GTA_OS as macos|linux" {
  source "$REPO_ROOT/lib/os_detect.sh"
  case "$GTA_OS" in
    macos|linux) ;;
    *) flunk "GTA_OS=$GTA_OS (want macos or linux)" ;;
  esac
}

@test "os_detect exports GTA_ARCH as arm64|x86_64" {
  source "$REPO_ROOT/lib/os_detect.sh"
  case "$GTA_ARCH" in
    arm64|x86_64) ;;
    *) flunk "GTA_ARCH=$GTA_ARCH (want arm64 or x86_64)" ;;
  esac
}

@test "os_detect declares GTA_HOMEBREW_PREFIX (may be empty)" {
  source "$REPO_ROOT/lib/os_detect.sh"
  # bash 3.2 (macOS default) lacks `[ -v ]`; use declare -p which is portable.
  declare -p GTA_HOMEBREW_PREFIX >/dev/null 2>&1
}

@test "os_detect exports GTA_IS_WSL as 0 or 1" {
  source "$REPO_ROOT/lib/os_detect.sh"
  case "$GTA_IS_WSL" in 0|1) ;; *) flunk "GTA_IS_WSL=$GTA_IS_WSL" ;; esac
}

@test "os_detect exports GTA_IS_DOCKER as 0 or 1" {
  source "$REPO_ROOT/lib/os_detect.sh"
  case "$GTA_IS_DOCKER" in 0|1) ;; *) flunk "GTA_IS_DOCKER=$GTA_IS_DOCKER" ;; esac
}

@test "os_detect exports GTA_IS_ROSETTA as 0 or 1" {
  source "$REPO_ROOT/lib/os_detect.sh"
  case "$GTA_IS_ROSETTA" in 0|1) ;; *) flunk "GTA_IS_ROSETTA=$GTA_IS_ROSETTA" ;; esac
}

@test "on macOS: GTA_DISTRO empty" {
  source "$REPO_ROOT/lib/os_detect.sh"
  if [ "$GTA_OS" = "macos" ]; then
    [ -z "$GTA_DISTRO" ]
  fi
}

@test "GTA_GHOSTTY_RESOURCES is empty or a valid directory" {
  source "$REPO_ROOT/lib/os_detect.sh"
  if [ -n "$GTA_GHOSTTY_RESOURCES" ]; then
    assert_dir_exist "$GTA_GHOSTTY_RESOURCES"
  fi
}
