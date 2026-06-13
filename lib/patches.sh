#!/usr/bin/env bash
# patches.sh — sentinel-block I/O helpers for ghostty-tmux-attach.
# Block format:
#   # >>> ghostty-tmux-attach@VERSION sha=HASH >>>
#   <body>
#   # <<< ghostty-tmux-attach <<<

# Hash a string. Returns first 16 hex chars of SHA-256.
# Prefers `shasum -a 256` (macOS, Perl-based) and falls back to `sha256sum`
# (GNU coreutils on Linux). Either is guaranteed present on the target OSes.
gta_patch_hash() {
  local input="$1"
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$input" | shasum -a 256 | cut -c1-16
  else
    printf '%s' "$input" | sha256sum | cut -c1-16
  fi
}

# Ensure file ends with newline; create if missing.
gta_patch_normalize() {
  local file="$1"
  if [ ! -e "$file" ]; then
    mkdir -p "$(dirname "$file")"
    touch "$file"
    return 0
  fi
  # Append newline if file is non-empty and doesn't end with one
  if [ -s "$file" ]; then
    # `tail -c 1 | wc -l` counts newlines in the last byte.
    # If the count is 0, the last byte is not a newline.
    local last_nl
    last_nl=$(tail -c 1 "$file" | wc -l | tr -d ' ')
    if [ "$last_nl" = "0" ]; then
      printf '\n' >> "$file"
    fi
  fi
}

# Strip our sentinel block from a file (idempotent).
gta_patch_remove() {
  local file="$1"
  [ -e "$file" ] || return 0
  local tmp
  tmp=$(mktemp)
  awk '
    /^# >>> ghostty-tmux-attach@/ { skip=1; next }
    skip && /^# <<< ghostty-tmux-attach <<<$/ { skip=0; next }
    !skip { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

# Write (or replace) a sentinel block at end of file.
gta_patch_write() {
  local file="$1" version="$2" body="$3"
  gta_patch_normalize "$file"
  gta_patch_remove "$file"
  local hash
  hash=$(gta_patch_hash "$body")
  {
    printf '# >>> ghostty-tmux-attach@%s sha=%s >>>\n' "$version" "$hash"
    printf '%s\n' "$body"
    printf '# <<< ghostty-tmux-attach <<<\n'
  } >> "$file"
}

# Read the body inside our sentinel (empty if absent).
gta_patch_read() {
  local file="$1"
  [ -e "$file" ] || return 0
  awk '
    /^# >>> ghostty-tmux-attach@/ { inside=1; next }
    /^# <<< ghostty-tmux-attach <<<$/ { inside=0; next }
    inside { print }
  ' "$file"
}

# Extract "VERSION HASH" from the sentinel header (empty if absent).
gta_patch_version_hash() {
  local file="$1"
  [ -e "$file" ] || return 0
  awk '/^# >>> ghostty-tmux-attach@/ {
    match($0, /@[^ ]+/); ver=substr($0, RSTART+1, RLENGTH-1)
    match($0, /sha=[^ ]+/); sha=substr($0, RSTART+4, RLENGTH-4)
    print ver " " sha; exit
  }' "$file"
}

# Union two comma-separated sets; dedupe; sort; trim per-token whitespace.
gta_set_union() {
  local a="$1" b="$2"
  printf '%s\n%s\n' "$a" "$b" |
    tr ',' '\n' |
    awk 'NF { gsub(/^[[:space:]]+|[[:space:]]+$/, ""); if (NF) print }' |
    awk 'NF && !seen[$0]++' |
    LC_ALL=C sort |
    paste -sd, -
}
