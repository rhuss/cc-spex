#!/usr/bin/env bash
# Codex progress presentation and durable resume contract (T049).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
PROGRESS="$REPO_ROOT/spex/scripts/adapters/codex/progress.py"
MATERIALIZE="$REPO_ROOT/spex/scripts/spex-materialize-plugin.sh"
CONFIGURE="$REPO_ROOT/spex/scripts/adapters/codex/configure-project.py"

for dependency in jq python3; do
  command -v "$dependency" >/dev/null 2>&1 || {
    echo "ERROR: required integration dependency is missing: $dependency" >&2
    exit 2
  }
done

# Fail once at the missing adapter boundary. Keeping scenarios behind this
# probe makes the test-first result precise until T051 provides the presenter.
if [[ ! -f "$PROGRESS" ]]; then
  echo "FAIL: Codex progress adapter is not implemented." >&2
  echo "T049 requires progress.py with --event, --state, --visible-sequence, --visible-stage, and --native." >&2
  exit 1
fi
help="$(python3 "$PROGRESS" --help 2>&1)"
help_status=$?
for option in --event --state --visible-sequence --visible-stage --native; do
  if [[ $help_status -ne 0 || "$help" != *"$option"* ]]; then
    echo "FAIL: Codex progress adapter is missing the T049 presentation contract ($option)." >&2
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

spex_test_make_temp_dir TEST_ROOT
EVENT="$TEST_ROOT/event.json"
STATE="$TEST_ROOT/state.json"

write_event() {
  local sequence="$1" stage="$2" kind="$3" status="$4" message="$5"
  jq -n \
    --argjson sequence "$sequence" \
    --arg stage "$stage" --arg kind "$kind" --arg status "$status" \
    --arg message "$message" \
    '{schema_version:"1.0.0", workflow_id:"workflow-progress-047",
      sequence:$sequence, timestamp:"2026-07-24T12:00:00Z", stage:$stage,
      kind:$kind, status:$status, message:$message,
      objective:"Finish the Codex progress fixture"}' >"$EVENT"
}

present() {
  local native="$1"
  shift
  python3 "$PROGRESS" --event "$EVENT" --native "$native" "$@"
}

echo "=== Codex native and transcript presentation ==="
kinds=(normal delegated recovery pause complete)
stages=(specify plan implement review-code complete)
statuses=(started delegated updated paused completed)
messages=(
  "Starting specification"
  "Delegated plan review"
  "Running recovery attempt 1 of 3"
  "Paused for repository credentials"
  "Workflow completed"
)

for index in "${!kinds[@]}"; do
  sequence=$((index + 1))
  write_event "$sequence" "${stages[index]}" "${kinds[index]}" \
    "${statuses[index]}" "${messages[index]}"
  output="$(present available 2>&1)"
  output_status=$?
  if [[ $output_status -eq 0 ]] && jq -e \
      --arg kind "${kinds[index]}" --arg message "${messages[index]}" \
      '.transcript | contains($message)' <<<"$output" >/dev/null 2>&1 &&
     jq -e --arg kind "${kinds[index]}" \
      '.native.kind == $kind and (.native.operation | length > 0)' \
      <<<"$output" >/dev/null 2>&1; then
    pass "${kinds[index]} transition has native and transcript presentation"
  else
    fail "${kinds[index]} transition presentation (exit=$output_status output=$output)"
  fi
  transcript_output="$(present unavailable 2>&1)"
  if jq -e --arg message "${messages[index]}" \
      '.native == null and (.transcript | contains($message))' \
      <<<"$transcript_output" >/dev/null 2>&1; then
    pass "${kinds[index]} transition is reported in the immediately following transcript event"
  else
    fail "${kinds[index]} transcript client missed the immediate transition"
  fi
done

write_event 6 implement recovery updated "Recovery evidence recorded"
fallback="$(present unavailable 2>&1)"
fallback_status=$?
if [[ $fallback_status -eq 0 ]] && jq -e \
    '.native == null and (.transcript | contains("Recovery evidence recorded")) and
     .degradation.reason and .degradation.fallback' <<<"$fallback" >/dev/null 2>&1; then
  pass "unavailable native progress degrades explicitly to transcript"
else
  fail "transcript fallback is not explicit (exit=$fallback_status output=$fallback)"
fi

echo "=== Durable interruption and stale-progress reconciliation ==="
jq -n \
  '{schema_version:"2.0.0", workflow_id:"workflow-progress-047", revision:9,
    stage:"review-code", status:"running",
    resume_point:{stage:"review-code",action:"run code review",artifact:null}}' >"$STATE"
write_event 7 implement normal updated "Implementation completed"

resumed="$(present unavailable --state "$STATE" --visible-sequence 7 \
  --visible-stage implement 2>&1)"
resumed_status=$?
if [[ $resumed_status -eq 0 ]] && jq -e \
    '.reconciliation.stale == true and
     .reconciliation.visible_sequence == 7 and
     .reconciliation.authoritative_sequence == 9 and
     .reconciliation.authoritative_stage == "review-code" and
     (.transcript | test("review-code"; "i"))' <<<"$resumed" >/dev/null 2>&1; then
  pass "restart reports stale visible progress and resumes from durable state"
else
  fail "restart did not reconcile to durable state (exit=$resumed_status output=$resumed)"
fi

current="$(present unavailable --state "$STATE" --visible-sequence 9 \
  --visible-stage review-code 2>&1)"
current_status=$?
if [[ $current_status -eq 0 ]] && jq -e \
    '.reconciliation.stale == false and
     .reconciliation.authoritative_stage == "review-code"' \
    <<<"$current" >/dev/null 2>&1; then
  pass "matching visible progress resumes without a false stale warning"
else
  fail "matching progress was mis-reconciled (exit=$current_status output=$current)"
fi

echo "=== Codex initialization and materialization exclude Claude statusline ==="
PROJECT="$TEST_ROOT/project"
mkdir -p "$PROJECT"
configured="$(python3 "$CONFIGURE" configure --root "$PROJECT" --security safe \
  --capabilities-json '{"codex_available":true,"native_task_progress":true}' 2>&1)"
configure_status=$?
if [[ $configure_status -eq 0 ]] && jq -e '.status == "configured"' \
    <<<"$configured" >/dev/null 2>&1 &&
   ! find "$PROJECT" -type f -print0 | xargs -0 grep -IlE \
      'statusline-command|spex-ship-statusline|CLAUDE_CONFIG_DIR' 2>/dev/null | grep -q .; then
  pass "Codex initialization does not install Claude statusline configuration"
else
  fail "Codex initialization leaked Claude statusline behavior"
fi

OUTPUT="$TEST_ROOT/materialized-codex"
materialized="$("$MATERIALIZE" --harness codex --output "$OUTPUT" 2>&1)"
materialize_status=$?
if [[ $materialize_status -eq 0 && -f "$OUTPUT/scripts/adapters/codex/progress.py" ]] &&
   ! find "$OUTPUT" -type f -name 'spex-ship-statusline.sh' -print | grep -q . &&
   ! grep -RIlE 'statusline-command|spex-ship-statusline' "$OUTPUT" >/dev/null 2>&1; then
  pass "Codex materialization includes its presenter and excludes Claude statusline"
else
  fail "Codex materialization progress specialization is invalid (exit=$materialize_status output=$materialized)"
fi

printf '\n%d passed, %d failed\n' "$PASSED" "$FAILED"
[[ $FAILED -eq 0 ]]
