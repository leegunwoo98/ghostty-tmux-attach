#!/usr/bin/env bash
# known_hashes.sh — last 5 released versions' template hashes per snippet.
# Prune to last 5 versions; older installs get "too old, --force or reinstall".
#
# Schema: GTA_HASHES["<snippet-id>/<version>"]=<16-char-sha256-prefix>
# Snippet IDs: ghostty | tmux-main | tmux-minimal

declare -gA GTA_HASHES=(
  ["ghostty/0.1.0"]="adba7dc3882a62b0"
  ["tmux-main/0.1.0"]="cda73c5a81f9b3c1"
  ["tmux-minimal/0.1.0"]="4bf7ec0f2330b749"
)

# Returns 0 if version is in the table, 1 otherwise.
gta_hash_known() {
  local key="$1"
  [ -n "${GTA_HASHES[$key]:-}" ]
}

# Returns the hash for a given key (empty if absent).
gta_hash_for() {
  local key="$1"
  printf '%s' "${GTA_HASHES[$key]:-}"
}
