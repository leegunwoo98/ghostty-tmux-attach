#!/usr/bin/env bats
# V5: install.sh + lib + libexec contain no outbound network calls beyond
# the documented curl-pipe download URL (referenced in README/install docs).

load '../helpers/common'

@test "no curl/wget/nc/http calls in install.sh or lib outside allowlist" {
  # Allowlist: github.com/<owner>/ghostty-tmux-attach in any string + the
  # `command -v curl` capability probe + comment lines.
  local violations
  violations=$(grep -rEn 'curl |wget |nc |https?://' \
    "$REPO_ROOT/install.sh" \
    "$REPO_ROOT/lib" \
    "$REPO_ROOT/libexec" \
    "$REPO_ROOT/bin" 2>/dev/null |
    grep -vE 'github\.com/[^/]+/ghostty-tmux-attach' |
    grep -vE 'command -v curl' |
    grep -vE 'ghostty\.org' |
    grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)
  if [ -n "$violations" ]; then
    echo "V5 telemetry-grep found unallowed network references:"
    echo "$violations"
    fail "telemetry-grep violations"
  fi
}
