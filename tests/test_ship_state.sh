#!/usr/bin/env bash
# Tests for spex-ship-state.py resume handling.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SHIP_STATE="$REPO_ROOT/spex/scripts/spex-ship-state.py"

PASS=0
FAIL=0
TMPDIR=""

cleanup() {
  if [ -n "$TMPDIR" ] && [ -d "$TMPDIR" ]; then
    rm -rf "$TMPDIR"
  fi
}
trap cleanup EXIT

setup() {
  TMPDIR=$(mktemp -d)
  export SHIP_STATE_FILE="$TMPDIR/.specify/.spex-state"
  (cd "$TMPDIR" && python3 "$SHIP_STATE" create brainstorm/01-x.md --ask smart --start-from review-spec >/dev/null)
  python3 "$SHIP_STATE" pause >/dev/null
  jq '.retries = 2' "$SHIP_STATE_FILE" > "$SHIP_STATE_FILE.tmp" && mv "$SHIP_STATE_FILE.tmp" "$SHIP_STATE_FILE"
}

field() {
  jq -r ".$1" "$SHIP_STATE_FILE"
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected '$expected', got '$actual')"; FAIL=$((FAIL + 1))
  fi
}

echo "Test: resume without --ask keeps the saved level"
setup
OUT=$(python3 "$SHIP_STATE" resume)
assert_eq "output" "RESUMED stage=review-spec index=2 ask=smart" "$OUT"
assert_eq "status running" "running" "$(field status)"
assert_eq "retries reset" "0" "$(field retries)"
assert_eq "ask kept" "smart" "$(field ask)"
cleanup

echo "Test: resume --ask overrides the saved level"
setup
OUT=$(python3 "$SHIP_STATE" resume --ask never)
assert_eq "output" "RESUMED stage=review-spec index=2 ask=never" "$OUT"
assert_eq "ask overridden" "never" "$(field ask)"
assert_eq "stage kept" "review-spec" "$(field stage)"
cleanup

echo "Test: resume rejects an invalid level and leaves state unchanged"
setup
RC=0; python3 "$SHIP_STATE" resume --ask sometimes >/dev/null 2>&1 || RC=$?
assert_eq "exit code" "2" "$RC"
assert_eq "ask unchanged" "smart" "$(field ask)"
assert_eq "status unchanged" "paused" "$(field status)"
cleanup

echo "Test: resume without a state file fails"
TMPDIR=$(mktemp -d)
export SHIP_STATE_FILE="$TMPDIR/.specify/.spex-state"
RC=0; python3 "$SHIP_STATE" resume >/dev/null 2>&1 || RC=$?
assert_eq "exit code" "1" "$RC"
cleanup

# --- progress: banner + eight-stage plan ---

STAGE_NAMES='["specify","clarify","review-spec","plan","tasks","review-plan","implement","review-code"]'

# progress_run: run progress, set P_OUT, P_ERR, P_RC, P_BANNER, P_PLAN
progress_run() {
  P_RC=0
  P_OUT=$(python3 "$SHIP_STATE" progress 2>"$TMPDIR/progress.err") || P_RC=$?
  P_ERR=$(cat "$TMPDIR/progress.err")
  P_BANNER=$(printf '%s\n' "$P_OUT" | sed -n 's/^BANNER //p')
  P_PLAN=$(printf '%s\n' "$P_OUT" | sed -n 's/^PLAN //p')
}

# statuses: space-separated plan statuses in order
statuses() {
  printf '%s' "$P_PLAN" | jq -r '[.[].status] | join(" ")'
}

progress_setup() {
  TMPDIR=$(mktemp -d)
  export SHIP_STATE_FILE="$TMPDIR/.specify/.spex-state"
}

write_fixture() {
  mkdir -p "$(dirname "$SHIP_STATE_FILE")"
  printf '%s\n' "$1" > "$SHIP_STATE_FILE"
}

echo "Test: progress after a fresh create"
progress_setup
(cd "$TMPDIR" && python3 "$SHIP_STATE" create brainstorm/01-x.md >/dev/null)
progress_run
assert_eq "exit 0" "0" "$P_RC"
assert_eq "banner" "🧬 ship 📝 specify ▓░░░░░░░░ 1/8 🧠" "$P_BANNER"
assert_eq "statuses" "in_progress pending pending pending pending pending pending pending" "$(statuses)"
assert_eq "two output lines" "2" "$(printf '%s\n' "$P_OUT" | wc -l | tr -d ' ')"
assert_eq "PLAN is single-line JSON with 8 entries" "8" "$(printf '%s' "$P_PLAN" | jq 'length')"
assert_eq "steps start with stage names in order" "true" \
  "$(printf '%s' "$P_PLAN" | jq --argjson names "$STAGE_NAMES" '[range(0;8) as $i | .[$i].step | startswith($names[$i])] | all')"
assert_eq "entries only have step and status" "true" \
  "$(printf '%s' "$P_PLAN" | jq 'all(.[]; keys == ["status","step"])')"
cleanup

echo "Test: progress after create --start-from implement"
progress_setup
(cd "$TMPDIR" && python3 "$SHIP_STATE" create brainstorm/01-x.md --start-from implement >/dev/null)
progress_run
assert_eq "banner" "🧬 ship 🔨 implement ▓▓▓▓▓▓▓░░ 7/8 🧠" "$P_BANNER"
assert_eq "statuses" "completed completed completed completed completed completed in_progress pending" "$(statuses)"
assert_eq "implement label" "implement" "$(printf '%s' "$P_PLAN" | jq -r '.[6].step')"
cleanup

echo "Test: progress for a completed pipeline"
progress_setup
write_fixture '{"mode":"ship","stage":"done","stage_index":8,"total_stages":8,"ask":"smart","status":"completed"}'
progress_run
assert_eq "done banner" "🧬 ship ✅ done ▓▓▓▓▓▓▓▓ 8/8" "$P_BANNER"
assert_eq "all completed" "completed completed completed completed completed completed completed completed" "$(statuses)"
cleanup

echo "Test: progress after advance from plan to tasks"
progress_setup
mkdir -p "$TMPDIR/specs/01-x" && touch "$TMPDIR/specs/01-x/spec.md" "$TMPDIR/specs/01-x/plan.md"
(cd "$TMPDIR" && python3 "$SHIP_STATE" create brainstorm/01-x.md --start-from plan >/dev/null)
ADV=$(cd "$TMPDIR" && python3 "$SHIP_STATE" advance)
assert_eq "advance output" "ADVANCED stage=tasks index=4" "$ADV"
progress_run
assert_eq "tasks banner" "🧬 ship 📋 tasks ▓▓▓▓▓░░░░ 5/8 🧠" "$P_BANNER"
assert_eq "plan done, tasks in progress" "completed completed completed completed in_progress pending pending pending" "$(statuses)"
cleanup

echo "Test: progress after the final advance (state file kept with stage done)"
progress_setup
(cd "$TMPDIR" && python3 "$SHIP_STATE" create brainstorm/01-x.md --start-from review-code >/dev/null)
ADV=$(cd "$TMPDIR" && python3 "$SHIP_STATE" advance)
assert_eq "advance prints PIPELINE_COMPLETE" "PIPELINE_COMPLETE" "$ADV"
assert_eq "state file still exists" "yes" "$([ -f "$SHIP_STATE_FILE" ] && echo yes || echo no)"
progress_run
assert_eq "done banner after advance" "🧬 ship ✅ done ▓▓▓▓▓▓▓▓ 8/8" "$P_BANNER"
assert_eq "all completed after advance" "completed completed completed completed completed completed completed completed" "$(statuses)"
cleanup

echo "Test: banner rejects unsafe state values (no command execution, no control codes)"
progress_setup
# Payloads have no whitespace: the status line splits fields on IFS, so a
# space would cut the payload off before it reaches the arithmetic.
write_fixture "{\"mode\":\"ship\",\"stage\":\"implement\",\"stage_index\":\"a[\$(id>$TMPDIR/PWNED)]\",\"total_stages\":8,\"ask\":\"smart\",\"status\":\"running\"}"
progress_run
assert_eq "injected index: exit 0" "0" "$P_RC"
assert_eq "injected index: no command run" "no" "$([ -e "$TMPDIR/PWNED" ] && echo yes || echo no)"
assert_eq "injected index: no banner" "" "$P_BANNER"
write_fixture "{\"mode\":\"ship\",\"stage\":\"implement\",\"stage_index\":6,\"total_stages\":\"a[\$(id>$TMPDIR/PWNED2)]\",\"ask\":\"smart\",\"status\":\"running\"}"
progress_run
assert_eq "injected total: no command run" "no" "$([ -e "$TMPDIR/PWNED2" ] && echo yes || echo no)"
write_fixture '{"mode":"ship","stage":"implement","stage_index":"08","total_stages":"08","ask":"smart","status":"running"}'
progress_run
assert_eq "leading-zero values: exit 0" "0" "$P_RC"
assert_eq "leading-zero values: no banner" "" "$P_BANNER"
write_fixture '{"mode":"ship","stage":"implement","stage_index":999999999,"total_stages":1,"ask":"smart","status":"running"}'
progress_run
assert_eq "huge index: exit 0" "0" "$P_RC"
assert_eq "huge index: no banner" "" "$P_BANNER"
write_fixture '{"mode":"ship","stage":"x\u001b[2J","stage_index":3,"total_stages":8,"ask":"smart","status":"running"}'
progress_run
assert_eq "control codes in stage: no banner" "" "$P_BANNER"
assert_eq "control codes in stage: plan still printed" "8" "$(printf '%s' "$P_PLAN" | jq 'length')"
cleanup

echo "Test: progress prints nothing without a ship state"
progress_setup
progress_run
assert_eq "missing file: no output" "" "$P_OUT"
assert_eq "missing file: exit 0" "0" "$P_RC"
write_fixture '{not json'
progress_run
assert_eq "invalid JSON: no output" "" "$P_OUT"
assert_eq "invalid JSON: exit 0" "0" "$P_RC"
write_fixture '{"mode":"flow","spec_dir":"specs/001-x"}'
progress_run
assert_eq "flow mode: no output" "" "$P_OUT"
assert_eq "flow mode: exit 0" "0" "$P_RC"
write_fixture '{"mode":"watch","pr_number":42}'
progress_run
assert_eq "watch mode: no output" "" "$P_OUT"
assert_eq "watch mode: exit 0" "0" "$P_RC"
cleanup

echo "Test: progress tolerates odd stage data"
progress_setup
write_fixture '{"mode":"ship","stage":"mystery","stage_index":3,"total_stages":8,"ask":"smart","status":"running"}'
progress_run
assert_eq "unknown stage: exit 0" "0" "$P_RC"
assert_eq "unknown stage: no traceback" "0" "$(printf '%s' "$P_ERR" | grep -c Traceback || true)"
write_fixture '{"mode":"ship","stage":"plan","stage_index":42,"total_stages":8,"ask":"smart","status":"running"}'
progress_run
assert_eq "out-of-range index: exit 0" "0" "$P_RC"
assert_eq "out-of-range index: no traceback" "0" "$(printf '%s' "$P_ERR" | grep -c Traceback || true)"
write_fixture '{"mode":"ship","stage":"plan","stage_index":"three","total_stages":8,"ask":"smart","status":"running"}'
progress_run
assert_eq "non-numeric index: exit 0" "0" "$P_RC"
assert_eq "non-numeric index: no traceback" "0" "$(printf '%s' "$P_ERR" | grep -c Traceback || true)"
write_fixture '{"mode":"ship","stage":"plan","stage_index":"3","total_stages":8,"ask":"smart","status":"running"}'
progress_run
assert_eq "quoted numeric index read like the banner" "completed completed completed in_progress pending pending pending pending" "$(statuses)"
assert_eq "quoted numeric index banner" "🧬 ship 🗺️ plan ▓▓▓▓░░░░░ 4/8 🧠" "$P_BANNER"
write_fixture '{"stage":"tasks","stage_index":4,"total_stages":8,"ask":"smart","status":"running"}'
progress_run
assert_eq "legacy (no mode) counts as ship" "completed completed completed completed in_progress pending pending pending" "$(statuses)"
cleanup

echo "Test: progress after pause, fail and resume"
progress_setup
(cd "$TMPDIR" && python3 "$SHIP_STATE" create brainstorm/01-x.md --start-from review-spec >/dev/null)
python3 "$SHIP_STATE" pause >/dev/null
progress_run
assert_eq "paused banner" "🧬 ship 🔬 review-spec ▓▓▓░░░░░░ 3/8 🧠 ⏸ paused" "$P_BANNER"
assert_eq "paused step label" "review-spec (paused)" "$(printf '%s' "$P_PLAN" | jq -r '.[2].step')"
assert_eq "paused step status" "in_progress" "$(printf '%s' "$P_PLAN" | jq -r '.[2].status')"
python3 "$SHIP_STATE" resume >/dev/null
progress_run
assert_eq "resumed banner" "🧬 ship 🔬 review-spec ▓▓▓░░░░░░ 3/8 🧠" "$P_BANNER"
assert_eq "resumed step label" "review-spec" "$(printf '%s' "$P_PLAN" | jq -r '.[2].step')"
python3 "$SHIP_STATE" fail >/dev/null
progress_run
assert_eq "failed banner" "🧬 ship 🔬 review-spec ▓▓▓░░░░░░ 3/8 🧠 ✗ failed" "$P_BANNER"
assert_eq "failed step label" "review-spec (failed)" "$(printf '%s' "$P_PLAN" | jq -r '.[2].step')"
python3 "$SHIP_STATE" resume >/dev/null
progress_run
assert_eq "resumed after fail: no suffix in banner" "🧬 ship 🔬 review-spec ▓▓▓░░░░░░ 3/8 🧠" "$P_BANNER"
assert_eq "resumed after fail: no suffix in plan" "0" "$(printf '%s' "$P_PLAN" | grep -c '(paused)\|(failed)' || true)"
cleanup

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
