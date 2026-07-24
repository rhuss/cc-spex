#!/usr/bin/env bash
# Codex Teams sequential-fallback integration contract (T056).
# No Codex client or network is required; the materialized adapter declaration
# is consumed as the executable fallback policy.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
COMMAND_MAP="$REPO_ROOT/spex/scripts/adapters/codex/command-map.json"
MATERIALIZER="$REPO_ROOT/spex/scripts/spex-materialize-plugin.sh"

for dependency in jq git find; do
  command -v "$dependency" >/dev/null 2>&1 || {
    echo "ERROR: required integration dependency is missing: $dependency" >&2
    exit 2
  }
done
[[ -x "$MATERIALIZER" ]] || {
  echo "ERROR: Codex materializer is unavailable: $MATERIALIZER" >&2
  exit 2
}

# T056 is test-first. Fail at the missing adapter boundary instead of reporting
# five copies of the same jq failure.
if ! jq -e '
  .teams_fallback.mode == "sequential" and
  .teams_fallback.outcome == "success" and
  .teams_fallback.preserve_completed_work == true and
  .teams_fallback.continue_remaining_work == true and
  .teams_fallback.order == "dependency_then_assignment" and
  (["disabled","unavailable","conflict","single_group","isolation_unavailable"] -
    (.teams_fallback.reasons | keys)) == []
' "$COMMAND_MAP" >/dev/null 2>&1; then
  echo "FAIL: Codex sequential-success Teams fallback is not implemented." >&2
  echo "T056 requires command-map.json teams_fallback policy for disabled, unavailable, conflict, single_group, and isolation_unavailable." >&2
  exit 1
fi

# shellcheck source=../lib/test_helpers.sh
source "$REPO_ROOT/tests/lib/test_helpers.sh"
trap spex_test_cleanup EXIT HUP INT TERM

PASSED=0
FAILED=0
pass() { printf 'PASS: %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=$((FAILED + 1)); }

assert_policy() {
  local reason="$1"
  local description="$2"
  if jq -e --arg reason "$reason" '
    .teams_fallback as $fallback |
    $fallback.mode == "sequential" and
    $fallback.outcome == "success" and
    $fallback.preserve_completed_work == true and
    $fallback.continue_remaining_work == true and
    $fallback.order == "dependency_then_assignment" and
    $fallback.reasons[$reason].mode == "sequential" and
    $fallback.reasons[$reason].outcome == "success" and
    ($fallback.reasons[$reason].message | type == "string" and length > 0)
  ' "$COMMAND_MAP" >/dev/null 2>&1; then
    pass "$description"
  else
    fail "$description"
  fi
}

echo "=== Materialized Codex fallback policy ==="
spex_test_make_temp_dir MATERIALIZED_PARENT
MATERIALIZED="$MATERIALIZED_PARENT/codex-plugin"
materialize_output="$("$MATERIALIZER" --harness codex --output "$MATERIALIZED" 2>&1)"
materialize_status=$?

if [[ "$materialize_status" -eq 0 ]]; then
  pass "Codex plugin materializes with the Teams fallback declaration"
else
  fail "Codex materialization failed: $materialize_output"
fi

ORCHESTRATE_COMMAND="$MATERIALIZED/extensions/spex-teams/commands/speckit.spex-teams.orchestrate.md"
if [[ -f "$ORCHESTRATE_COMMAND" ]] &&
   ! grep -q '{harness:' "$ORCHESTRATE_COMMAND" &&
   grep -qi 'sequential' "$ORCHESTRATE_COMMAND" &&
   grep -qi 'success' "$ORCHESTRATE_COMMAND"; then
  pass "materialized orchestration presents sequential fallback as successful execution"
else
  fail "materialized orchestration does not expose resolved sequential-success behavior"
fi

echo "=== Unavailable, unsafe, and not-beneficial reasons ==="
assert_policy disabled \
  "explicitly disabled Teams completes through the normal sequential path"
assert_policy unavailable \
  "unavailable Codex subagents degrade to sequential success"
assert_policy conflict \
  "file or contract conflicts make parallelism unsafe, not the work blocked"
assert_policy single_group \
  "a single independent group runs directly without team overhead"
assert_policy isolation_unavailable \
  "unavailable writer isolation prevents parallel dispatch but not completion"

echo "=== Sequential fallback preserves accepted and remaining work ==="
# This ledger represents a partially completed orchestration: T-A was accepted
# before parallel execution became unavailable; T-B and then dependent T-C
# still need execution. Every fallback reason must retain T-A exactly once and
# schedule all remaining work in dependency/assignment order.
LEDGER="$MATERIALIZED_PARENT/work-ledger.json"
jq -n '{
  expected:["T-A","T-B","T-C"],
  accepted:[{task:"T-A",result:"accepted",evidence:["unit-a"]}],
  remaining:[
    {task:"T-B",assignment_order:1,dependencies:[]},
    {task:"T-C",assignment_order:2,dependencies:["T-B"]}
  ]
}' >"$LEDGER"

for reason in disabled unavailable conflict single_group isolation_unavailable; do
  plan="$(jq -n \
    --arg reason "$reason" \
    --slurpfile policy "$COMMAND_MAP" \
    --slurpfile ledger "$LEDGER" '
      ($policy[0].teams_fallback) as $fallback |
      ($ledger[0]) as $work |
      {
        reason:$reason,
        mode:$fallback.reasons[$reason].mode,
        outcome:$fallback.reasons[$reason].outcome,
        accepted:(if $fallback.preserve_completed_work then $work.accepted else [] end),
        queue:(if $fallback.continue_remaining_work
          then ($work.remaining | sort_by(.assignment_order)) else [] end),
        completed_ids:(
          (if $fallback.preserve_completed_work
            then ($work.accepted | map(.task)) else [] end) +
          (if $fallback.continue_remaining_work
            then ($work.remaining | sort_by(.assignment_order) | map(.task)) else [] end)
        )
      }
    ')"

  if jq -e '
      .mode == "sequential" and .outcome == "success" and
      (.accepted | map(.task)) == ["T-A"] and
      (.accepted[0].evidence) == ["unit-a"] and
      (.queue | map(.task)) == ["T-B","T-C"] and
      .queue[1].dependencies == ["T-B"] and
      .completed_ids == ["T-A","T-B","T-C"] and
      ((.completed_ids | unique | length) == 3)
    ' <<<"$plan" >/dev/null 2>&1; then
    pass "$reason fallback preserves accepted work and completes every remaining task once"
  else
    fail "$reason fallback lost, duplicated, or reordered work: $plan"
  fi
done

printf '\nCodex Teams fallback: %d passed, %d failed\n' "$PASSED" "$FAILED"
[[ "$FAILED" -eq 0 ]]
