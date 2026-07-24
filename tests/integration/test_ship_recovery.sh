#!/usr/bin/env bash
# End-to-end bounded ship recovery contract (T041).
# Uses only disposable Git repositories; no harness client or network required.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
STATE_TOOL="$REPO_ROOT/spex/scripts/spex-ship-state.sh"

for dependency in git jq python3; do
  command -v "$dependency" >/dev/null 2>&1 || {
    echo "ERROR: required integration dependency is missing: $dependency" >&2
    exit 2
  }
done

# Fail once at the missing public boundary. The scenarios below become active
# when T042 exposes the recovery lifecycle rather than producing misleading
# fixture or jq failures for every assertion.
for command in recovery-start recovery-record recovery-complete; do
  help="$("$STATE_TOOL" "$command" --help 2>&1)"
  status=$?
  if [[ $status -ne 0 || "$help" != *"--expected-revision"* ]]; then
    echo "FAIL: ship recovery lifecycle CLI is not implemented." >&2
    echo "T041 requires $command with JSON stdout and --expected-revision CAS." >&2
    exit 1
  fi
done

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

assert_json_success() {
  local description="$1"
  local status="$2"
  local output="$3"
  local expression="$4"
  if [[ "$status" -eq 0 ]] && jq -e "$expression" <<<"$output" >/dev/null 2>&1; then
    pass "$description"
  else
    fail "$description (exit=$status output=$output)"
  fi
}

echo "=== Disposable recovery workflow ==="
spex_test_make_repo MAIN_CHECKOUT
spex_test_make_worktree "$MAIN_CHECKOUT" "047-recovery-test" FEATURE_WORKTREE

SPEC_DIR="$FEATURE_WORKTREE/specs/047-recovery-test"
STATE_FILE="$FEATURE_WORKTREE/.specify/.spex-state"
mkdir -p "$FEATURE_WORKTREE/.specify" "$SPEC_DIR"
printf '# Recovery fixture\n' >"$SPEC_DIR/spec.md"
printf '# Plan fixture\n' >"$SPEC_DIR/plan.md"
printf '# Tasks fixture\n' >"$SPEC_DIR/tasks.md"

GIT_COMMON_RAW="$(git -C "$FEATURE_WORKTREE" rev-parse --git-common-dir)"
if [[ "$GIT_COMMON_RAW" = /* ]]; then
  GIT_COMMON="$GIT_COMMON_RAW"
else
  GIT_COMMON="$(cd "$FEATURE_WORKTREE/$GIT_COMMON_RAW" && pwd -P)"
fi
FEATURE_REAL="$(cd "$FEATURE_WORKTREE" && pwd -P)"
MAIN_REAL="$(cd "$MAIN_CHECKOUT" && pwd -P)"
SPEC_REAL="$(cd "$SPEC_DIR" && pwd -P)"
HEAD_OID="$(git -C "$FEATURE_WORKTREE" rev-parse HEAD)"
TIMESTAMP="2026-07-24T12:00:00Z"

jq -n \
  --arg repository_root "$MAIN_REAL" \
  --arg git_common_dir "$GIT_COMMON" \
  --arg active_worktree "$FEATURE_REAL" \
  --arg feature_branch "047-recovery-test" \
  --arg spec_dir "$SPEC_REAL" \
  --arg state_file "$STATE_FILE" \
  --arg head_oid "$HEAD_OID" \
  --arg timestamp "$TIMESTAMP" \
  '{schema_version:"2.0.0", workflow_id:"workflow-recovery-047",
    revision:1, mode:"ship",
    context:{repository_root:$repository_root, git_common_dir:$git_common_dir,
      active_worktree:$active_worktree, feature_branch:$feature_branch,
      spec_dir:$spec_dir, state_file:$state_file, head_oid:$head_oid,
      validated_at:$timestamp},
    stage:"implement", status:"running",
    completed_gates:["review-spec","review-plan"], recovery:null,
    resume_point:{stage:"implement",action:"continue implementation",artifact:"tasks.md"},
    diagnostics:[], created_at:$timestamp, updated_at:$timestamp}' >"$STATE_FILE"

echo "=== Accepted recovery cascades to the earliest affected stage ==="
start_output="$(run_state "$MAIN_CHECKOUT" recovery-start \
  --expected-revision 1 \
  --objective "Resolve a specification feasibility finding" \
  --origin-stage implement \
  --finding "The plan assumes an unavailable runtime capability" \
  --affected-artifact spec.md \
  --affected-artifact plan.md \
  --affected-artifact tasks.md \
  --affected-gate review-spec \
  --affected-gate review-plan 2>&1)"
start_status=$?
assert_json_success \
  "recoverable finding starts bounded autonomous recovery without changing worktree authority" \
  "$start_status" "$start_output" \
  '.revision == 2 and .status == "recovering" and
   .context.feature_branch == "047-recovery-test" and
   .recovery.max_attempts == 3 and .recovery.max_elapsed_seconds == 1800'

record_output="$(run_state "$FEATURE_WORKTREE" recovery-record \
  --expected-revision 2 \
  --remedy "Revise the requirement and dependent plan" \
  --input-hash "spec.md=sha256:spec-before" \
  --input-hash "plan.md=sha256:plan-before" \
  --result "The revised artifacts pass the feasibility check" \
  --evidence "Focused feasibility fixture passes" \
  --outcome accepted 2>&1)"
record_status=$?
assert_json_success \
  "accepted recovery evidence is persisted before continuation" \
  "$record_status" "$record_output" \
  '.revision == 3 and .status == "recovering" and
   (.recovery.attempts | length) == 1 and
   .recovery.attempts[0].outcome == "accepted"'

complete_output="$(run_state "$MAIN_CHECKOUT" recovery-complete \
  --expected-revision 3 \
  --outcome accepted \
  --rewind-stage specify \
  --resume-action "rerun specification review and rebuild downstream artifacts" \
  --resume-artifact spec.md 2>&1)"
complete_status=$?
assert_json_success \
  "accepted recovery invalidates downstream gates and rewinds to the earliest affected stage" \
  "$complete_status" "$complete_output" \
  '.revision == 4 and .status == "running" and .stage == "specify" and
   .completed_gates == [] and .recovery.outcome == "accepted" and
   .recovery.affected_artifacts == ["spec.md","plan.md","tasks.md"] and
   .recovery.affected_gates == ["review-spec","review-plan"] and
   .resume_point == {stage:"specify",
     action:"rerun specification review and rebuild downstream artifacts",
     artifact:"spec.md"} and
   (.confirmation_required // false) == false'

if [[ "$complete_output" != *"Should I continue"* &&
      "$complete_output" != *"ask the user"* ]]; then
  pass "safe in-scope recovery continues without a routine confirmation prompt"
else
  fail "safe recovery emitted a routine continuation prompt: $complete_output"
fi

echo "=== Real authority boundary pauses with a precise resume point ==="
authority_start="$(run_state "$FEATURE_WORKTREE" recovery-start \
  --expected-revision 4 \
  --objective "Choose between incompatible public API guarantees" \
  --origin-stage specify \
  --finding "The requested guarantees require a product decision" \
  --affected-artifact spec.md \
  --affected-gate review-spec 2>&1)"
authority_start_status=$?
assert_json_success "authority-boundary episode starts normally" \
  "$authority_start_status" "$authority_start" \
  '.revision == 5 and .status == "recovering"'

authority_complete="$(run_state "$MAIN_CHECKOUT" recovery-complete \
  --expected-revision 5 \
  --outcome authority_required \
  --resume-stage specify \
  --resume-action "choose strict compatibility or the revised API" \
  --resume-artifact spec.md \
  --residual-risk "Proceeding without this choice changes the public contract" 2>&1)"
authority_status=$?
assert_json_success \
  "only an evidenced authority boundary pauses ship and preserves exact continuation" \
  "$authority_status" "$authority_complete" \
  '.revision == 6 and .status == "paused_authority" and
   .recovery.outcome == "authority_required" and
   .resume_point == {stage:"specify",
     action:"choose strict compatibility or the revised API",
     artifact:"spec.md"}'

resume_output="$(run_state "$FEATURE_WORKTREE" resume --expected-revision 6 2>&1)"
resume_status=$?
assert_json_success "authority pause resumes through the durable CAS boundary" \
  "$resume_status" "$resume_output" \
  '.revision == 7 and .status == "running" and .stage == "specify"'

echo "=== Bounded non-success produces a durable terminal resume report ==="
budget_start="$(run_state "$MAIN_CHECKOUT" recovery-start \
  --expected-revision 7 \
  --objective "Find a viable implementation for the retained requirement" \
  --origin-stage specify \
  --finding "All known adapters violate the retained constraint" \
  --affected-artifact spec.md \
  --affected-artifact plan.md \
  --affected-gate review-spec \
  --affected-gate review-plan 2>&1)"
budget_start_status=$?
assert_json_success "terminal fixture starts with finite default bounds" \
  "$budget_start_status" "$budget_start" \
  '.revision == 8 and .recovery.max_attempts == 3 and
   .recovery.max_elapsed_seconds == 1800'

revision=8
for attempt in 1 2 3; do
  record="$(run_state "$FEATURE_WORKTREE" recovery-record \
    --expected-revision "$revision" \
    --remedy "bounded alternative $attempt" \
    --input-hash "spec.md=sha256:spec-$attempt" \
    --result "alternative $attempt remains infeasible" \
    --evidence "fixture $attempt reproduces the blocker" \
    --outcome rejected 2>&1)"
  record_status=$?
  revision=$((revision + 1))
  if [[ "$record_status" -ne 0 ]] ||
     ! jq -e --argjson revision "$revision" --argjson attempts "$attempt" \
       '.revision == $revision and (.recovery.attempts | length) == $attempts' \
       <<<"$record" >/dev/null 2>&1; then
    fail "recovery attempt $attempt was not durably bounded: $record"
    break
  fi
done

terminal_output="$(run_state "$MAIN_CHECKOUT" recovery-complete \
  --expected-revision 11 \
  --outcome budget_exhausted \
  --resume-stage specify \
  --resume-action "revise the retained constraint, then restart feasibility recovery" \
  --resume-artifact spec.md \
  --residual-risk "No tested adapter satisfies the retained constraint" 2>&1)"
terminal_status=$?
assert_json_success \
  "three attempts terminate with evidence, residual risk, affected inputs, and exact resume point" \
  "$terminal_status" "$terminal_output" \
  '.revision == 12 and .status == "failed_budget" and
   .recovery.outcome == "budget_exhausted" and
   (.recovery.attempts | length) == 3 and
   .resume_point == {stage:"specify",
     action:"revise the retained constraint, then restart feasibility recovery",
     artifact:"spec.md"} and
   any(.diagnostics[];
     .kind == "terminal_recovery_report" and
     (.attempted_actions | length) == 3 and
     (.evidence | length) == 3 and
     .residual_risk == "No tested adapter satisfies the retained constraint" and
     .affected_artifacts == ["spec.md","plan.md"] and
     .resume_point.stage == "specify")'

resolved_terminal="$(run_state "$FEATURE_WORKTREE" resolve 2>/dev/null)"
if jq -e '.revision == 12 and .status == "failed_budget" and
    .resume_point.stage == "specify"' <<<"$resolved_terminal" >/dev/null 2>&1; then
  pass "terminal report remains resolvable for restart after interruption"
else
  fail "terminal recovery report was not durable: $resolved_terminal"
fi

printf '\nShip recovery: %d passed, %d failed\n' "$PASSED" "$FAILED"
[[ "$FAILED" -eq 0 ]]
