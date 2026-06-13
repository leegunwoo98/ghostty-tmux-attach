#!/usr/bin/env bash
# allocator.sh — race-free per-cwd tmux session-name allocator.
# Exports: GTA_CHOSEN (the chosen session name) after gta_choose_session().
#
# Design: each candidate session name is "locked" by atomically creating
# its claim FILE via `set -C` (noclobber) — the redirection fails if the
# file already exists, so only one concurrent writer wins. The owner tuple
# (PID:start_time) is written into the file by the winner. Concurrent
# losers move to the next candidate name. This removes the central-lock
# stale-tuple race that an earlier mkdir-lock design suffered from.

# Internal helper: emit "PID:start_epoch" for current shell.
# LC_ALL=C pins month/day abbreviations to English so `date -j -f` round-trips
# the BSD `ps -o lstart=` output (otherwise LC_TIME=de_DE yields "Sa"/"Mai",
# the parse fails, and the tuple is born "PID:0" — fine in isolation but
# breaks tuple equality against verifier output that also depends on locale).
gta_self_owner() {
  local start=""
  if [ "$(uname -s)" = "Linux" ] && [ -r "/proc/$$/stat" ]; then
    # field 22 of /proc/PID/stat is starttime in clock ticks since boot
    start=$(awk '{print $22}' "/proc/$$/stat" 2>/dev/null)
  elif command -v ps >/dev/null 2>&1; then
    # macOS: lstart is a date string; epoch via date -j -f
    start=$(LC_ALL=C ps -o lstart= -p $$ 2>/dev/null | LC_ALL=C xargs -I{} date -j -f "%a %b %d %T %Y" "{}" +%s 2>/dev/null)
  fi
  : "${start:=0}"
  printf '%s:%s' "$$" "$start"
}

# Check whether a claim owner tuple is alive. Tuple = "PID:start".
# Returns 0 if alive (matching tuple), 1 if dead or impostor.
#
# Fail-closed policy: if `kill -0 "$pid"` succeeds (PID is live) but the
# start-time probe returns empty — transient ps/xargs/date glitch, locale
# mismatch, signal interruption — we return 0 ("alive"). The start-time
# check is only a PID-reuse impostor defense; when we can't verify, treat
# the owner as alive so we DON'T `rm -f` a peer's just-written claim. Worst
# case: a stale-but-unverifiable claim stays sticky until its real holder
# or the next acquirer cleans it up. That preserves the no-collision
# invariant at the cost of slightly slower stale-GC under adversity.
gta_owner_alive() {
  local tuple="$1" pid start cur
  pid="${tuple%%:*}"
  start="${tuple#*:}"
  [ -n "$pid" ] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  # Verify start time matches (PID-reuse defense)
  if [ "$(uname -s)" = "Linux" ] && [ -r "/proc/$pid/stat" ]; then
    cur=$(awk '{print $22}' "/proc/$pid/stat" 2>/dev/null)
  else
    cur=$(LC_ALL=C ps -o lstart= -p "$pid" 2>/dev/null | LC_ALL=C xargs -I{} date -j -f "%a %b %d %T %Y" "{}" +%s 2>/dev/null)
  fi
  # Empty cur → probe failed; default to alive (fail closed).
  [ -z "$cur" ] && return 0
  [ "$cur" = "$start" ]
}

# Try to atomically acquire a single candidate name. Returns 0 on success
# (and writes the owner tuple into the claim file). Returns 1 if the name
# is busy (held by an attached tmux client or a live claim owner).
#
# Atomic primitive: prepare a temp file containing the owner tuple, then
# `ln` it to the claim path. POSIX `ln` is atomic and fails if the target
# already exists, so the claim file is born with content already filled.
# This closes the open-then-write window that `( set -C; ... > $cf )`
# left, in which a concurrent reader could see an empty claim file and
# mistake it for a stale claim.
gta_try_claim() {
  local name="$1"
  local cf="$GTA_CLAIMS/$name"

  # tmux session attached → busy
  if [ -n "$(tmux list-clients -t "=$name" 2>/dev/null)" ]; then
    return 1
  fi

  # Prepare an owner-laden temp file; we'll hardlink it into place.
  local tmp owner
  owner=$(gta_self_owner)
  tmp="$GTA_CLAIMS/.tmp.$$.$RANDOM"
  printf '%s' "$owner" > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }

  if ln "$tmp" "$cf" 2>/dev/null; then
    rm -f "$tmp"
    return 0
  fi

  # ln failed → claim file exists. Inspect; GC if stale, then retry once.
  if [ -r "$cf" ]; then
    local existing
    existing=$(cat "$cf" 2>/dev/null)
    if [ -n "$existing" ] && gta_owner_alive "$existing"; then
      rm -f "$tmp"
      return 1
    fi
    rm -f "$cf"
  else
    rm -f "$tmp"
    return 1
  fi

  if ln "$tmp" "$cf" 2>/dev/null; then
    rm -f "$tmp"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

gta_choose_session() {
  GTA_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/ghostty-tmux-attach"
  GTA_CLAIMS="$GTA_ROOT/claims"

  # Sanitize basename: LC_ALL=C so non-ASCII bytes fold to underscores rather
  # than tripping "Illegal byte sequence" on BSD tr.
  GTA_BASE=$(LC_ALL=C printf '%s' "${PWD##*/}" | LC_ALL=C tr -c 'A-Za-z0-9_-' '_')
  [ -n "$GTA_BASE" ] || GTA_BASE="root"

  # Try TMPDIR fallback if cache dir not writable
  if ! mkdir -p "$GTA_CLAIMS" 2>/dev/null; then
    GTA_ROOT="${TMPDIR:-/tmp}/ghostty-tmux-attach-$(id -u)"
    GTA_CLAIMS="$GTA_ROOT/claims"
    mkdir -p "$GTA_CLAIMS" 2>/dev/null || return 1
  fi

  # Walk candidate names; first atomic acquisition wins.
  local i=1
  GTA_CHOSEN="$GTA_BASE"
  while ! gta_try_claim "$GTA_CHOSEN"; do
    i=$((i + 1))
    GTA_CHOSEN="$GTA_BASE-$i"
    # Sanity cap to prevent runaway loops; 256 distinct surfaces per cwd is
    # absurd in practice and indicates a bug.
    if [ "$i" -gt 256 ]; then
      return 1
    fi
  done
  return 0
}
