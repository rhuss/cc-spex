#!/bin/sh
# spex-setup-report.sh - Print what the spex setup workflow reported (FR-018).
#
# Usage (from the project root):
#   spex-setup-report.sh [<run-id>]
#
# `specify workflow run` captures the stderr of every shell step into the run
# state (.specify/workflows/runs/<run-id>/state.json) instead of printing it.
# This prints, on stderr, the messages users need to see:
#   - the extension selection changes (`Enabled:` / `Disabled:` lines and the
#     summary), the spex-detach stealth-mode lines (written, repaired,
#     verified or still visible), the legacy spex-detach migration note, and
#     the notice when an interactive reply was not captured
#   - the Claude permission messages: `Permissions configured in ...` from
#     claude-permissions, and the `Migrated: ...` and `WARNING: ...` lines
#     from both claude-permissions and migrate-permissions (spec 061)
#   - for a failed run, the stdout and stderr of the failed step, so the
#     underlying tool error is visible even when the tool writes it to
#     stdout rather than stderr (for example `specify init` prints its
#     `Error:` lines to stdout; without this the run JSON only carries the
#     generic "Shell command exited with code 1.")
#   - a hint when a failed step reported "Operation not permitted" (EPERM),
#     which is typically a sandbox (for example Codex) denying a write to the
#     project's .agents/ directory where spec-kit installs its Codex skills
# Without a run id, the most recent run is used. Prints nothing when there
# is no run state or jq is missing. Always exits 0.

command -v jq >/dev/null 2>&1 || exit 0
RUNS=".specify/workflows/runs"

if [ -n "${1:-}" ]; then
  STATE="$RUNS/$1/state.json"
else
  # shellcheck disable=SC2012
  STATE=$(ls -t "$RUNS"/*/state.json 2>/dev/null | head -n 1)
fi
[ -n "$STATE" ] && [ -f "$STATE" ] || exit 0

STATUS=$(jq -r '.status // empty' "$STATE" 2>/dev/null)
REPORT=$(jq -r '
  . as $state
  | ["snapshot-registry", "selected-extensions", "selected-security", "apply-extensions", "claude-permissions", "migrate-permissions", "claude-statusline"] as $report
  | ( $report[] | ($state.step_results[.].output.stderr // empty) ),
    ( if ($state.status == "failed" or $state.status == "aborted")
      then
        ($state.current_step_id) as $cur
        | ( if (($report | index($cur)) == null)
            then ($state.step_results[$cur].output.stderr // empty)
            else empty end ),
          ($state.step_results[$cur].output.stdout // empty)
      else empty end )
' "$STATE" 2>/dev/null | sed '/^[[:space:]]*$/d')

[ -z "$REPORT" ] || printf '%s\n' "$REPORT" >&2

# "Operation not permitted" (EPERM) on a failed run is almost always a sandbox
# denying a write, not a real permission problem. Codex's workspace sandbox
# guards the project's .agents/ directory, where spec-kit installs its Codex
# skills, so `specify init` stops there. Point the user at the resolution.
case "$STATUS" in
  failed|aborted)
    if printf '%s' "$REPORT" | grep -q "Operation not permitted"; then
      printf '%s\n' \
        "" \
        "HINT: \"Operation not permitted\" above is usually a sandbox denying a write." \
        "With Codex this commonly blocks the project's .agents/ directory, where" \
        "spec-kit installs its Codex skills. Re-run \$cc-spex-init and approve the" \
        "filesystem escalation when prompted, or grant this project write access to" \
        "the blocked directory, then run setup again." >&2
    fi
    ;;
esac
exit 0
