#!/usr/bin/env bash
# End-to-end worktree authority lifecycle contract (T030).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
STATE_TOOL="$REPO_ROOT/spex/scripts/spex-ship-state.sh"
CWD_TOOL="$REPO_ROOT/spex/scripts/spex-worktree-cwd.sh"

# T030 lands before the US2 implementation. Fail once, with the exact missing
# CLI boundary, rather than running 100 iterations that all fail identically.
transfer_help="$($STATE_TOOL transfer --help 2>&1)"
transfer_status=$?
resolve_help="$($STATE_TOOL resolve --help 2>&1)"
resolve_status=$?
resume_help="$($STATE_TOOL resume --help 2>&1)"
resume_status=$?
if [[ $transfer_status -ne 0 || $resolve_status -ne 0 || $resume_status -ne 0 ]] ||
   [[ "$transfer_help" != *"--source"* || "$transfer_help" != *"--destination"* ]] ||
   [[ "$resume_help" != *"--expected-revision"* ]]; then
  echo "FAIL: WorkflowState lifecycle CLI is not implemented." >&2
  echo "T030 requires T031-T035 support for transfer, resolve, and resume --expected-revision." >&2
  exit 1
fi

for dependency in git jq python3; do
  command -v "$dependency" >/dev/null 2>&1 || {
    echo "ERROR: required integration dependency is missing: $dependency" >&2
    exit 2
  }
done
[[ -x "$CWD_TOOL" ]] || {
  echo "ERROR: worktree CWD resolver is missing: $CWD_TOOL" >&2
  exit 2
}

# shellcheck source=../lib/test_helpers.sh
source "$REPO_ROOT/tests/lib/test_helpers.sh"
trap spex_test_cleanup EXIT HUP INT TERM

PASSED=0
FAILED=0
pass() { printf 'PASS: %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=$((FAILED + 1)); }

run_state() {
  local cwd="$1"
  shift
  (
    cd "$cwd" || exit 1
    env -u SHIP_STATE_FILE "$STATE_TOOL" "$@"
  )
}

echo "=== Disposable feature worktree and state transfer ==="
spex_test_make_repo MAIN_CHECKOUT
spex_test_make_worktree "$MAIN_CHECKOUT" "047-lifecycle-test" FEATURE_WORKTREE

SPEC_DIR="$FEATURE_WORKTREE/specs/047-lifecycle-test"
MAIN_STATE="$MAIN_CHECKOUT/.specify/.spex-state"
FEATURE_STATE="$FEATURE_WORKTREE/.specify/.spex-state"
IDENTITY_FILE="$MAIN_CHECKOUT/.specify/worktree-identity.json"
mkdir -p "$MAIN_CHECKOUT/.specify" "$FEATURE_WORKTREE/.specify" "$SPEC_DIR"
printf '# Lifecycle fixture\n' > "$SPEC_DIR/spec.md"

GIT_COMMON_RAW="$(git -C "$FEATURE_WORKTREE" rev-parse --git-common-dir)"
if [[ "$GIT_COMMON_RAW" = /* ]]; then
  GIT_COMMON="$GIT_COMMON_RAW"
else
  GIT_COMMON="$(cd "$FEATURE_WORKTREE/$GIT_COMMON_RAW" && pwd -P)"
fi
HEAD_OID="$(git -C "$FEATURE_WORKTREE" rev-parse HEAD)"
TIMESTAMP="2026-07-24T12:00:00Z"

jq -n \
  --arg repository_root "$(cd "$MAIN_CHECKOUT" && pwd -P)" \
  --arg git_common_dir "$GIT_COMMON" \
  --arg active_worktree "$(cd "$FEATURE_WORKTREE" && pwd -P)" \
  --arg feature_branch "047-lifecycle-test" \
  --arg spec_dir "$(cd "$SPEC_DIR" && pwd -P)" \
  --arg state_file "$(cd "$FEATURE_WORKTREE/.specify" && pwd -P)/.spex-state" \
  --arg head_oid "$HEAD_OID" \
  --arg validated_at "$TIMESTAMP" \
  '{repository_root:$repository_root, git_common_dir:$git_common_dir,
    active_worktree:$active_worktree, feature_branch:$feature_branch,
    spec_dir:$spec_dir, state_file:$state_file, head_oid:$head_oid,
    validated_at:$validated_at}' > "$IDENTITY_FILE"

jq -n \
  --slurpfile context "$IDENTITY_FILE" \
  --arg timestamp "$TIMESTAMP" \
  '{schema_version:"2.0.0", workflow_id:"workflow-lifecycle-047",
    revision:1, mode:"ship", context:$context[0], stage:"review-plan",
    status:"paused_authority", completed_gates:["review-spec"], recovery:null,
    resume_point:{stage:"review-plan",action:"resume delegated review",artifact:"plan.md"},
    diagnostics:[], created_at:$timestamp, updated_at:$timestamp}' > "$MAIN_STATE"

transfer_output="$(run_state "$MAIN_CHECKOUT" transfer \
  --source "$MAIN_STATE" \
  --destination "$FEATURE_STATE" \
  --identity-file "$IDENTITY_FILE" \
  --transfer-id "lifecycle-transfer-001" 2>&1)"
transfer_status=$?
if [[ $transfer_status -eq 0 && ! -e "$MAIN_STATE" && -f "$FEATURE_STATE" ]] &&
   jq -e '.phase == "main_removed"' <<<"$transfer_output" >/dev/null 2>&1; then
  pass "feature worktree creation transfers state authority before removing the main copy"
else
  fail "feature worktree state transfer did not commit atomically: $transfer_output"
fi

echo "=== Delegated CWD reset and resume from both checkouts ==="
resolved_main="$(run_state "$MAIN_CHECKOUT" resolve 2>/dev/null)"
resolved_feature="$(run_state "$FEATURE_WORKTREE" resolve 2>/dev/null)"
if jq -e --arg worktree "$(cd "$FEATURE_WORKTREE" && pwd -P)" \
    '.context.active_worktree == $worktree' <<<"$resolved_main" >/dev/null 2>&1 &&
   jq -e --arg worktree "$(cd "$FEATURE_WORKTREE" && pwd -P)" \
    '.context.active_worktree == $worktree' <<<"$resolved_feature" >/dev/null 2>&1; then
  pass "main and feature checkout resolve the same worktree authority"
else
  fail "main and feature checkout resolved different workflow authority"
fi

reset_target="$(cd "$MAIN_CHECKOUT" && env -u SHIP_STATE_FILE "$CWD_TOOL")"
if [[ "$reset_target" == "$(cd "$FEATURE_WORKTREE" && pwd -P)" ]]; then
  pass "delegated CWD reset recovers the validated feature worktree without environment authority"
else
  fail "delegated CWD reset returned '${reset_target:-<empty>}'"
fi

echo "=== 100-run wrong-checkout isolation ==="
BASE_REVISION="$(jq -r '.revision' "$FEATURE_STATE")"
LIFECYCLE_FAILURE=""
for run in $(seq 1 100); do
  if ((run % 2 == 0)); then
    INVOCATION_CWD="$MAIN_CHECKOUT"
  else
    INVOCATION_CWD="$FEATURE_WORKTREE"
  fi
  PAUSED_REVISION=$((BASE_REVISION + (run * 2) - 1))
  RESUMED_REVISION=$((PAUSED_REVISION + 1))
  STATE_TEMP="$FEATURE_WORKTREE/.specify/.spex-state.lifecycle.tmp"
  jq \
    --argjson revision "$PAUSED_REVISION" \
    --arg run "$run" \
    '.revision=$revision | .status="paused_authority" |
     .stage="review-plan" |
     .resume_point={stage:"review-plan",action:("resume delegated run " + $run),artifact:"plan.md"} |
     .updated_at="2026-07-24T12:00:00Z"' \
    "$FEATURE_STATE" > "$STATE_TEMP" && mv "$STATE_TEMP" "$FEATURE_STATE"

  resume_output="$(run_state "$INVOCATION_CWD" resume \
    --expected-revision "$PAUSED_REVISION" 2>/dev/null)"
  resume_status=$?
  if [[ $resume_status -ne 0 ]] ||
     ! jq -e --argjson revision "$RESUMED_REVISION" \
       --arg worktree "$(cd "$FEATURE_WORKTREE" && pwd -P)" \
       '.revision == $revision and .status == "running" and
        .context.active_worktree == $worktree' \
       <<<"$resume_output" >/dev/null 2>&1; then
    LIFECYCLE_FAILURE="run $run failed to resume revision $PAUSED_REVISION from $INVOCATION_CWD"
    break
  fi

  resolved="$(run_state "$INVOCATION_CWD" resolve 2>/dev/null)"
  ACTIVE_WORKTREE="$(jq -r '.context.active_worktree // empty' <<<"$resolved")"
  if [[ "$ACTIVE_WORKTREE" != "$(cd "$FEATURE_WORKTREE" && pwd -P)" ]]; then
    LIFECYCLE_FAILURE="run $run resolved mutation target outside the feature worktree"
    break
  fi
  printf 'delegated run %03d\n' "$run" > "$ACTIVE_WORKTREE/specs/047-lifecycle-test/run-$run.txt"
done

FEATURE_MUTATIONS="$(find "$SPEC_DIR" -maxdepth 1 -name 'run-*.txt' | wc -l | tr -d '[:space:]')"
MAIN_MUTATIONS="$(find "$MAIN_CHECKOUT" -path '*/specs/047-lifecycle-test/run-*.txt' | wc -l | tr -d '[:space:]')"
FINAL_REVISION="$(jq -r '.revision // 0' "$FEATURE_STATE" 2>/dev/null || printf 0)"
EXPECTED_REVISION=$((BASE_REVISION + 200))
if [[ -z "$LIFECYCLE_FAILURE" && "$FEATURE_MUTATIONS" -eq 100 &&
      "$MAIN_MUTATIONS" -eq 0 && ! -e "$MAIN_STATE" &&
      "$FINAL_REVISION" -eq "$EXPECTED_REVISION" ]]; then
  pass "100 delegated interrupt/resume runs produce zero wrong-checkout mutations or state advances"
else
  fail "${LIFECYCLE_FAILURE:-100-run isolation mismatch: feature=$FEATURE_MUTATIONS main=$MAIN_MUTATIONS revision=$FINAL_REVISION expected=$EXPECTED_REVISION}"
fi

printf '\nWorktree lifecycle: %d passed, %d failed\n' "$PASSED" "$FAILED"
[[ "$FAILED" -eq 0 ]]
