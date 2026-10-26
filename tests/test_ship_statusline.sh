#!/usr/bin/env bash
# Tests for spex-ship-statusline.sh state file resolution with parallel
# pipelines (main checkout + worktrees under .claude/worktrees/).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATUSLINE="$REPO_ROOT/spex/scripts/spex-ship-statusline.sh"

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
  MAIN="$(cd "$TMPDIR" && pwd -P)/main"
  WT1="$MAIN/.claude/worktrees/001-first"
  WT2="$MAIN/.claude/worktrees/002-second"
  mkdir -p "$MAIN/.specify" "$WT1/.specify" "$WT2/.specify"
}

ship_state() {
  printf '{"mode":"ship","stage":"%s","stage_index":%s,"total_stages":8,"ask":"smart","status":"running"}\n' "$1" "$2"
}

# Run the statusline like Claude Code does: process CWD is the session's
# current directory, CLAUDE_PROJECT_DIR is the launch directory, and the
# JSON arrives on stdin slightly after the process starts.
run_statusline() {
  local cwd="$1" project="$2"
  local json
  json=$(printf '{"workspace":{"current_dir":"%s","project_dir":"%s"},"context_window":{"used_percentage":42}}' "$cwd" "$project")
  (cd "$cwd" && (sleep 0.1; echo "$json") | env -u SHIP_STATE_FILE CLAUDE_PROJECT_DIR="$project" bash "$STATUSLINE" 2>/dev/null || true) \
    | sed $'s/\033\\[[0-9;]*m//g'
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  PASS: $desc"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected '$needle' in '$haystack')"; FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "  PASS: $desc"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (did not expect '$needle' in '$haystack')"; FAIL=$((FAIL + 1))
  fi
}

echo "Test: finished worktree session ignores a new pipeline's state in main"
setup
ship_state specify 0 > "$MAIN/.specify/.spex-state"
OUT=$(run_statusline "$WT1" "$MAIN")
assert_not_contains "no ship status from main checkout" "ship" "$OUT"
cleanup

echo "Test: worktree session shows its own pipeline, not the other worktree's"
setup
ship_state implement 6 > "$WT1/.specify/.spex-state"
ship_state clarify 1 > "$WT2/.specify/.spex-state"
OUT=$(run_statusline "$WT1" "$MAIN")
assert_contains "own stage shown" "implement" "$OUT"
assert_not_contains "other stage not shown" "clarify" "$OUT"
cleanup

echo "Test: main session shows the pipeline running in main"
setup
ship_state specify 0 > "$MAIN/.specify/.spex-state"
OUT=$(run_statusline "$MAIN" "$MAIN")
assert_contains "main stage shown" "specify" "$OUT"
cleanup

echo "Test: subdirectory of a worktree resolves to that worktree's state"
setup
git -C "$WT1" init -q
mkdir -p "$WT1/src"
ship_state plan 3 > "$WT1/.specify/.spex-state"
ship_state specify 0 > "$MAIN/.specify/.spex-state"
OUT=$(run_statusline "$WT1/src" "$MAIN")
assert_contains "worktree stage shown" "plan" "$OUT"
cleanup

echo "Test: main session shows no progress for a pipeline moved into a worktree"
setup
# After spex-worktree.sh prepare, the ship state lives only in the worktree.
ship_state clarify 1 > "$WT1/.specify/.spex-state"
OUT=$(run_statusline "$MAIN" "$MAIN")
assert_not_contains "no ship status in main session" "ship" "$OUT"
assert_not_contains "worktree stage not shown in main session" "clarify" "$OUT"
cleanup

echo "Test: context percentage from delayed stdin JSON is rendered"
setup
ship_state plan 3 > "$WT1/.specify/.spex-state"
OUT=$(run_statusline "$WT1" "$MAIN")
assert_contains "context percentage shown" "42%" "$OUT"
cleanup

# --- Golden outputs: the rendered Claude status line must stay byte-identical ---
# Captured from the status line before the --banner mode was added. Each fixture
# runs in an empty temp dir (no extension registry, no chained status line),
# once without stdin JSON and once with a context percentage on stdin.

assert_equals() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "    expected: $(printf '%s' "$expected" | od -c | head -5)"
    echo "    actual:   $(printf '%s' "$actual" | od -c | head -5)"
    FAIL=$((FAIL + 1))
  fi
}

GOLDEN_DIR=""
golden_setup() {
  GOLDEN_DIR=$(mktemp -d)
  GOLDEN_DIR="$(cd "$GOLDEN_DIR" && pwd -P)"
  mkdir -p "$GOLDEN_DIR/specs/001-x"
  touch "$GOLDEN_DIR/specs/001-x/spec.md" "$GOLDEN_DIR/specs/001-x/plan.md"
}

# golden_run <state-json> [stdin-json]: raw output bytes (trailing newline kept)
golden_run() {
  local state="$1" stdin_json="${2:-}" out
  printf '%s' "$state" > "$GOLDEN_DIR/state"
  if [ -n "$stdin_json" ]; then
    out=$(cd "$GOLDEN_DIR" && printf '%s\n' "$stdin_json" \
      | env -u CLAUDE_PROJECT_DIR SHIP_STATE_FILE="$GOLDEN_DIR/state" bash "$STATUSLINE"; printf '.')
  else
    out=$(cd "$GOLDEN_DIR" && env -u CLAUDE_PROJECT_DIR SHIP_STATE_FILE="$GOLDEN_DIR/state" bash "$STATUSLINE" </dev/null; printf '.')
  fi
  printf '%s' "${out%.}"
}

CTX='{"context_window":{"used_percentage":42}}'

# golden_check <name> <state-json> <expected-no-stdin> <expected-with-stdin>
golden_check() {
  local name="$1" state="$2" exp_plain="$3" exp_ctx="$4"
  assert_equals "golden $name (no stdin)" "$exp_plain" "$(golden_run "$state"; printf '.')"
  assert_equals "golden $name (context on stdin)" "$exp_ctx" "$(golden_run "$state" "$CTX"; printf '.')"
}

echo "Test: golden Claude status line output is byte-identical"
golden_setup
golden_check "ship running smart" \
  '{"mode":"ship","stage":"implement","stage_index":6,"total_stages":8,"ask":"smart","status":"running"}' \
  $'\xf0\x9f\xa7\xac \033[33m\033[1mship\033[0m \xf0\x9f\x94\xa8 \033[33m\033[1mimplement\033[0m \033[2m\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x91\xe2\x96\x91\033[0m \033[2m7/8\033[0m \xf0\x9f\xa7\xa0.' \
  $'\xf0\x9f\xa7\xac \033[33m\033[1mship\033[0m \xf0\x9f\x94\xa8 \033[33m\033[1mimplement\033[0m \033[2m\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x91\xe2\x96\x91\033[0m \033[2m7/8\033[0m \xf0\x9f\xa7\xa0 \033[2m|\033[0m \033[32m42%\033[0m.'
golden_check "ship running always" \
  '{"mode":"ship","stage":"clarify","stage_index":1,"total_stages":8,"ask":"always","status":"running"}' \
  $'\xf0\x9f\xa7\xac \033[34m\033[1mship\033[0m \xf0\x9f\x94\x8d \033[34m\033[1mclarify\033[0m \033[2m\xe2\x96\x93\xe2\x96\x93\xe2\x96\x91\xe2\x96\x91\xe2\x96\x91\xe2\x96\x91\xe2\x96\x91\xe2\x96\x91\xe2\x96\x91\033[0m \033[2m2/8\033[0m \xf0\x9f\x91\x81\xef\xb8\x8f.' \
  $'\xf0\x9f\xa7\xac \033[34m\033[1mship\033[0m \xf0\x9f\x94\x8d \033[34m\033[1mclarify\033[0m \033[2m\xe2\x96\x93\xe2\x96\x93\xe2\x96\x91\xe2\x96\x91\xe2\x96\x91\xe2\x96\x91\xe2\x96\x91\xe2\x96\x91\xe2\x96\x91\033[0m \033[2m2/8\033[0m \xf0\x9f\x91\x81\xef\xb8\x8f \033[2m|\033[0m \033[32m42%\033[0m.'
golden_check "ship running never" \
  '{"mode":"ship","stage":"plan","stage_index":3,"total_stages":8,"ask":"never","status":"running"}' \
  $'\xf0\x9f\xa7\xac \033[32m\033[1mship\033[0m \xf0\x9f\x97\xba\xef\xb8\x8f \033[32m\033[1mplan\033[0m \033[2m\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x91\xe2\x96\x91\xe2\x96\x91\xe2\x96\x91\xe2\x96\x91\033[0m \033[2m4/8\033[0m \xf0\x9f\x9a\x80.' \
  $'\xf0\x9f\xa7\xac \033[32m\033[1mship\033[0m \xf0\x9f\x97\xba\xef\xb8\x8f \033[32m\033[1mplan\033[0m \033[2m\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x91\xe2\x96\x91\xe2\x96\x91\xe2\x96\x91\xe2\x96\x91\033[0m \033[2m4/8\033[0m \xf0\x9f\x9a\x80 \033[2m|\033[0m \033[32m42%\033[0m.'
golden_check "ship paused" \
  '{"mode":"ship","stage":"review-spec","stage_index":2,"total_stages":8,"ask":"smart","status":"paused"}' \
  $'\xf0\x9f\xa7\xac \033[35m\033[1mship\033[0m \xf0\x9f\x94\xac \033[35m\033[1mreview-spec\033[0m \033[2m\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x91\xe2\x96\x91\xe2\x96\x91\xe2\x96\x91\xe2\x96\x91\xe2\x96\x91\033[0m \033[2m3/8\033[0m \xf0\x9f\xa7\xa0 \033[31m\033[1m\xe2\x8f\xb8 paused\033[0m.' \
  $'\xf0\x9f\xa7\xac \033[35m\033[1mship\033[0m \xf0\x9f\x94\xac \033[35m\033[1mreview-spec\033[0m \033[2m\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x91\xe2\x96\x91\xe2\x96\x91\xe2\x96\x91\xe2\x96\x91\xe2\x96\x91\033[0m \033[2m3/8\033[0m \xf0\x9f\xa7\xa0 \033[31m\033[1m\xe2\x8f\xb8 paused\033[0m \033[2m|\033[0m \033[32m42%\033[0m.'
golden_check "ship failed" \
  '{"mode":"ship","stage":"implement","stage_index":6,"total_stages":8,"ask":"smart","status":"failed"}' \
  $'\xf0\x9f\xa7\xac \033[33m\033[1mship\033[0m \xf0\x9f\x94\xa8 \033[33m\033[1mimplement\033[0m \033[2m\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x91\xe2\x96\x91\033[0m \033[2m7/8\033[0m \xf0\x9f\xa7\xa0 \033[31m\033[1m\xe2\x9c\x97 failed\033[0m.' \
  $'\xf0\x9f\xa7\xac \033[33m\033[1mship\033[0m \xf0\x9f\x94\xa8 \033[33m\033[1mimplement\033[0m \033[2m\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x91\xe2\x96\x91\033[0m \033[2m7/8\033[0m \xf0\x9f\xa7\xa0 \033[31m\033[1m\xe2\x9c\x97 failed\033[0m \033[2m|\033[0m \033[32m42%\033[0m.'
golden_check "ship done" \
  '{"mode":"ship","stage":"done","stage_index":8,"total_stages":8,"ask":"smart","status":"completed"}' \
  $'\xf0\x9f\xa7\xac \033[32m\033[1mship\033[0m \xe2\x9c\x85 \033[32m\033[1mdone\033[0m \033[2m\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\033[0m \033[2m8/8\033[0m.' \
  $'\xf0\x9f\xa7\xac \033[32m\033[1mship\033[0m \xe2\x9c\x85 \033[32m\033[1mdone\033[0m \033[2m\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\033[0m \033[2m8/8\033[0m \033[2m|\033[0m \033[32m42%\033[0m.'
golden_check "legacy ship (no mode)" \
  '{"stage":"tasks","stage_index":4,"total_stages":8,"ask":"smart","status":"running"}' \
  $'\xf0\x9f\xa7\xac \033[32m\033[1mship\033[0m \xf0\x9f\x93\x8b \033[32m\033[1mtasks\033[0m \033[2m\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x91\xe2\x96\x91\xe2\x96\x91\xe2\x96\x91\033[0m \033[2m5/8\033[0m \xf0\x9f\xa7\xa0.' \
  $'\xf0\x9f\xa7\xac \033[32m\033[1mship\033[0m \xf0\x9f\x93\x8b \033[32m\033[1mtasks\033[0m \033[2m\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x93\xe2\x96\x91\xe2\x96\x91\xe2\x96\x91\xe2\x96\x91\033[0m \033[2m5/8\033[0m \xf0\x9f\xa7\xa0 \033[2m|\033[0m \033[32m42%\033[0m.'
golden_check "flow" \
  '{"mode":"flow","spec_dir":"specs/001-x","clarified":true,"running":"tasks"}' \
  $'\xf0\x9f\xa7\xac \033[36m\033[1mspex\033[0m \033[32mspec \xe2\x9c\x93\033[0m \033[32mplan \xe2\x9c\x93\033[0m \033[36m\033[1mtasks \xe2\x96\xb6\033[0m \033[2mimpl \xe2\x97\x8b\033[0m \033[2m|\033[0m \033[32mC \xe2\x9c\x93\033[0m \033[2mS \xe2\x97\x8b\033[0m \033[2mP \xe2\x97\x8b\033[0m \033[2mR \xe2\x97\x8b\033[0m.' \
  $'\xf0\x9f\xa7\xac \033[36m\033[1mspex\033[0m \033[32mspec \xe2\x9c\x93\033[0m \033[32mplan \xe2\x9c\x93\033[0m \033[36m\033[1mtasks \xe2\x96\xb6\033[0m \033[2mimpl \xe2\x97\x8b\033[0m \033[2m|\033[0m \033[32mC \xe2\x9c\x93\033[0m \033[2mS \xe2\x97\x8b\033[0m \033[2mP \xe2\x97\x8b\033[0m \033[2mR \xe2\x97\x8b\033[0m \033[2m|\033[0m \033[32m42%\033[0m.'
# Watch elapsed time is computed from "now", so start the watch now (0m).
WATCH_NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
golden_check "watch" \
  '{"mode":"watch","pr_number":42,"last_ci_status":"passing","watch_started_at":"'"$WATCH_NOW"'","watch_timeout_minutes":30,"triage_count":2,"ci_fix_attempts":1}' \
  $'\xf0\x9f\x91\x80 \033[36m\033[1mPR #42\033[0m \033[2m|\033[0m \033[2m0m\033[0m \033[2m|\033[0m \033[32mCI \xe2\x9c\x93\033[0m \033[31mF:1\033[0m \033[2m|\033[0m \033[35mT:2\033[0m.' \
  $'\xf0\x9f\x91\x80 \033[36m\033[1mPR #42\033[0m \033[2m|\033[0m \033[2m0m\033[0m \033[2m|\033[0m \033[32mCI \xe2\x9c\x93\033[0m \033[31mF:1\033[0m \033[2m|\033[0m \033[35mT:2\033[0m \033[2m|\033[0m \033[32m42%\033[0m.'
rm -rf "$GOLDEN_DIR"

# --- Banner mode (--banner): plain-text ship line for Codex/OpenCode ---

BANNER_DIR=""
banner_setup() {
  BANNER_DIR=$(mktemp -d)
  BANNER_DIR="$(cd "$BANNER_DIR" && pwd -P)"
  # An enabled optional extension, so a leaked extension list would show up
  mkdir -p "$BANNER_DIR/.specify/extensions"
  printf '{"extensions":{"spex-gates":{"enabled":true}}}\n' > "$BANNER_DIR/.specify/extensions/.registry"
}

# banner_run <state-json|-> : runs --banner, sets BANNER_OUT (raw, trailing
# newline kept) and BANNER_RC. "-" means no state file at all.
BANNER_OUT=""
BANNER_RC=0
banner_run() {
  local state="$1"
  rm -f "$BANNER_DIR/state"
  [ "$state" != "-" ] && printf '%s' "$state" > "$BANNER_DIR/state"
  BANNER_RC=0
  (cd "$BANNER_DIR" && printf '%s\n' "$CTX" \
    | env -u CLAUDE_PROJECT_DIR SHIP_STATE_FILE="$BANNER_DIR/state" bash "$STATUSLINE" --banner \
    > "$BANNER_DIR/out" 2>/dev/null) || BANNER_RC=$?
  BANNER_OUT=$(cat "$BANNER_DIR/out"; printf '.')
  BANNER_OUT="${BANNER_OUT%.}"
}

ship_fixture() {
  printf '{"mode":"ship","stage":"%s","stage_index":%s,"total_stages":8,"ask":"%s","status":"%s"}' "$1" "$2" "${3:-smart}" "${4:-running}"
}

echo "Test: --banner renders the plain ship line"
banner_setup
banner_run "$(ship_fixture specify 0)"
assert_equals "running specify" $'🧬 ship 📝 specify ▓░░░░░░░░ 1/8 🧠\n' "$BANNER_OUT"
assert_equals "exit 0" "0" "$BANNER_RC"
banner_run "$(ship_fixture implement 6)"
assert_equals "running implement" $'🧬 ship 🔨 implement ▓▓▓▓▓▓▓░░ 7/8 🧠\n' "$BANNER_OUT"
assert_not_contains "no ESC byte" $'\033' "$BANNER_OUT"
assert_not_contains "no extension list" "[" "$BANNER_OUT"
assert_not_contains "no context percentage" "%" "$BANNER_OUT"
banner_run '{"mode":"ship","stage":"done","stage_index":8,"total_stages":8,"ask":"smart","status":"completed"}'
assert_equals "done" $'🧬 ship ✅ done ▓▓▓▓▓▓▓▓ 8/8\n' "$BANNER_OUT"
banner_run "$(ship_fixture review-spec 2 smart paused)"
assert_equals "paused" $'🧬 ship 🔬 review-spec ▓▓▓░░░░░░ 3/8 🧠 ⏸ paused\n' "$BANNER_OUT"
banner_run "$(ship_fixture implement 6 smart failed)"
assert_equals "failed" $'🧬 ship 🔨 implement ▓▓▓▓▓▓▓░░ 7/8 🧠 ✗ failed\n' "$BANNER_OUT"
banner_run "$(ship_fixture clarify 1 always)"
assert_equals "oversight always" $'🧬 ship 🔍 clarify ▓▓░░░░░░░ 2/8 👁️\n' "$BANNER_OUT"
banner_run "$(ship_fixture plan 3 never)"
assert_equals "oversight never" $'🧬 ship 🗺️ plan ▓▓▓▓░░░░░ 4/8 🚀\n' "$BANNER_OUT"
banner_run '{"stage":"tasks","stage_index":4,"total_stages":8,"ask":"smart","status":"running"}'
assert_equals "legacy ship (no mode)" $'🧬 ship 📋 tasks ▓▓▓▓▓░░░░ 5/8 🧠\n' "$BANNER_OUT"
banner_run "$(ship_fixture mystery 3)"
assert_contains "unknown stage uses generic icon" "⚙️ mystery" "$BANNER_OUT"
assert_equals "unknown stage exit 0" "0" "$BANNER_RC"

echo "Test: --banner prints nothing without a ship state"
banner_run "-"
assert_equals "missing state: empty" "" "$BANNER_OUT"
assert_equals "missing state: exit 0" "0" "$BANNER_RC"
banner_run "{not json"
assert_equals "invalid JSON: empty" "" "$BANNER_OUT"
assert_equals "invalid JSON: exit 0" "0" "$BANNER_RC"
banner_run '{"mode":"flow","spec_dir":"specs/001-x","running":"tasks"}'
assert_equals "flow state: empty" "" "$BANNER_OUT"
assert_equals "flow state: exit 0" "0" "$BANNER_RC"
assert_equals "flow state file kept" "yes" "$([ -f "$BANNER_DIR/state" ] && echo yes || echo no)"
banner_run '{"mode":"watch","pr_number":42,"watch_started_at":"2026-01-01T00:00:00Z"}'
assert_equals "watch state: empty" "" "$BANNER_OUT"
assert_equals "watch state: exit 0" "0" "$BANNER_RC"

echo "Test: --banner does not block on an open stdin pipe"
ship_fixture implement 6 > "$BANNER_DIR/state"
# stdin is a FIFO whose writer (sleep) keeps it open for 5 s without writing.
mkfifo "$BANNER_DIR/stdin.fifo"
sleep 5 > "$BANNER_DIR/stdin.fifo" &
WRITER_PID=$!
(cd "$BANNER_DIR" && exec env -u CLAUDE_PROJECT_DIR SHIP_STATE_FILE="$BANNER_DIR/state" \
  bash "$STATUSLINE" --banner < "$BANNER_DIR/stdin.fifo" > "$BANNER_DIR/out" 2>/dev/null) &
BANNER_PID=$!
waited=0
while kill -0 "$BANNER_PID" 2>/dev/null && [ "$waited" -lt 20 ]; do
  sleep 0.1
  waited=$((waited + 1))
done
if kill -0 "$BANNER_PID" 2>/dev/null; then
  echo "  FAIL: --banner returns without waiting for stdin (still running after 2s)"; FAIL=$((FAIL + 1))
  kill "$BANNER_PID" 2>/dev/null || true
else
  echo "  PASS: --banner returns without waiting for stdin"; PASS=$((PASS + 1))
  assert_contains "banner printed with open stdin" "implement" "$(cat "$BANNER_DIR/out")"
fi
kill "$WRITER_PID" 2>/dev/null || true
wait 2>/dev/null || true
rm -rf "$BANNER_DIR"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
