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
#     summary), the legacy spex-detach migration note, and the notice when an
#     interactive reply was not captured
#   - for a failed run, the stderr of the failed step (for example the
#     spex-worktrees / git extension guidance)
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

jq -r '
  . as $state
  | ["snapshot-registry", "selected-extensions", "selected-security", "apply-extensions", "claude-statusline"] as $report
  | ( $report[] | ($state.step_results[.].output.stderr // empty) ),
    ( if ($state.status == "failed" or $state.status == "aborted")
         and (($report | index($state.current_step_id)) == null)
      then ($state.step_results[$state.current_step_id].output.stderr // empty)
      else empty end )
' "$STATE" 2>/dev/null | sed '/^[[:space:]]*$/d' >&2
exit 0
