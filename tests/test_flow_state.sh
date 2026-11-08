#!/usr/bin/env bash
# Tests for spex-flow-state.sh invalidate (spec 059 FR-029).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FLOW="$REPO_ROOT/spex/scripts/spex-flow-state.sh"

PASS=0
FAIL=0
TMPDIR=""

cleanup() {
  if [ -n "$TMPDIR" ] && [ -d "$TMPDIR" ]; then
    rm -rf "$TMPDIR"
  fi
  TMPDIR=""
}
trap cleanup EXIT

setup_project() {
  TMPDIR=$(mktemp -d)
  cd "$TMPDIR"
  mkdir -p .specify
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

field() { jq -r ".$1" .specify/.spex-state; }

# ─── Test: invalidate resets clarify and review gates in flow mode ───
echo "=== Test: invalidate in flow mode ==="
setup_project
cat > .specify/.spex-state <<'EOF'
{
  "mode": "flow",
  "feature_branch": "001-x",
  "spec_dir": "specs/001-x",
  "implemented": true,
  "clarified": true,
  "review_spec_passed": true,
  "review_plan_passed": true,
  "review_code_passed": true,
  "triage_spec_passed": true,
  "triage_impl_passed": true
}
EOF
OUT=$("$FLOW" invalidate)
assert_eq "prints confirmation" "gates invalidated" "$OUT"
assert_eq "clarified reset" "false" "$(field clarified)"
assert_eq "review_spec_passed reset" "false" "$(field review_spec_passed)"
assert_eq "review_plan_passed reset" "false" "$(field review_plan_passed)"
assert_eq "review_code_passed reset" "false" "$(field review_code_passed)"
assert_eq "implemented unchanged" "true" "$(field implemented)"
assert_eq "triage_spec_passed unchanged" "true" "$(field triage_spec_passed)"
assert_eq "triage_impl_passed unchanged" "true" "$(field triage_impl_passed)"
assert_eq "spec_dir unchanged" "specs/001-x" "$(field spec_dir)"
cleanup

# ─── Test: invalidate adds false gates that were never set ───
echo "=== Test: invalidate on a fresh flow state ==="
setup_project
printf '{"mode":"flow","spec_dir":"specs/001-x","implemented":false,"clarified":true}\n' > .specify/.spex-state
"$FLOW" invalidate >/dev/null
assert_eq "review_code_passed present and false" "false" "$(field review_code_passed)"
assert_eq "clarified reset" "false" "$(field clarified)"
cleanup

# ─── Test: no state file stays absent ───
echo "=== Test: invalidate without a state file ==="
setup_project
RC=0; OUT=$("$FLOW" invalidate) || RC=$?
assert_eq "exit 0" "0" "$RC"
assert_eq "no output" "" "$OUT"
assert_eq "state file still absent" "absent" "$([ -f .specify/.spex-state ] && echo present || echo absent)"
cleanup

# ─── Test: ship state is left untouched ───
echo "=== Test: invalidate in ship mode ==="
setup_project
printf '{"mode":"ship","stage":"review-code","stage_index":7,"status":"running","ask":"smart"}\n' > .specify/.spex-state
BEFORE=$(shasum .specify/.spex-state | cut -d' ' -f1)
RC=0; OUT=$("$FLOW" invalidate) || RC=$?
assert_eq "exit 0" "0" "$RC"
assert_eq "no output" "" "$OUT"
assert_eq "ship state byte-identical" "$BEFORE" "$(shasum .specify/.spex-state | cut -d' ' -f1)"
cleanup

# ─── Test: SHIP_STATE_FILE override is honored ───
echo "=== Test: invalidate honors SHIP_STATE_FILE ==="
setup_project
printf '{"mode":"flow","review_spec_passed":true}\n' > "$TMPDIR/custom-state"
SHIP_STATE_FILE="$TMPDIR/custom-state" "$FLOW" invalidate >/dev/null
assert_eq "custom state file updated" "false" "$(jq -r .review_spec_passed "$TMPDIR/custom-state")"
cleanup

# ─── Summary ───
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
