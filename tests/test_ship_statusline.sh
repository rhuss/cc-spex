#!/usr/bin/env bash
# Tests for spex-ship-statusline.sh state file resolution with parallel
# pipelines (main checkout + worktrees under .claude/worktrees/).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATUSLINE="$REPO_ROOT/spex/scripts/spex-ship-statusline.sh"

PASS=0
FAIL=0
WORKDIR=""

cleanup() {
  if [ -n "$WORKDIR" ] && [ -d "$WORKDIR" ]; then
    rm -rf "$WORKDIR"
  fi
}
trap cleanup EXIT

setup() {
  WORKDIR=$(mktemp -d)
  MAIN="$(cd "$WORKDIR" && pwd -P)/main"
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

echo "Test: the chained status line runs whether it is a bare path or a command line (#54)"
# The previous status line echoes a marker, its arguments, and whether stdin reached it.
make_prev() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'PREV'
#!/usr/bin/env bash
input=$(cat)
case "$input" in *used_percentage*) got=stdin-ok ;; *) got=no-stdin ;; esac
echo "PREV[$*] $got"
PREV
  chmod +x "$path"
}
setup
make_prev "$WORKDIR/bin/prev.sh"
mkdir -p "$MAIN/.claude"
printf '%s\n' "$WORKDIR/bin/prev.sh" > "$MAIN/.claude/.spex-previous-statusline"
OUT=$(run_statusline "$MAIN" "$MAIN")
assert_contains "bare path: previous status line shown" "PREV[] stdin-ok" "$OUT"
printf '%s\n' "bash $WORKDIR/bin/prev.sh --compact" > "$MAIN/.claude/.spex-previous-statusline"
OUT=$(run_statusline "$MAIN" "$MAIN")
assert_contains "command line with bash and an argument: shown, argument passed" "PREV[--compact] stdin-ok" "$OUT"
make_prev "$WORKDIR/dir with space/prev.sh"
printf '%s\n' "$WORKDIR/dir with space/prev.sh" > "$MAIN/.claude/.spex-previous-statusline"
OUT=$(run_statusline "$MAIN" "$MAIN")
assert_contains "bare path containing a space: still shown" "PREV[] stdin-ok" "$OUT"
cleanup

echo "Test: init keeps a status line given as a command line (#54)"
# Run only the status-line step of spex-init.sh, against a project whose settings hold
# `bash <script> --compact`. Before #54 that failed `-f`, was not saved, and was overwritten.
setup
make_prev "$WORKDIR/bin/prev.sh"
mkdir -p "$MAIN/.claude"
printf '{"statusLine":{"type":"command","command":"bash %s --compact"}}\n' "$WORKDIR/bin/prev.sh" > "$MAIN/.claude/settings.local.json"
# From the function header to the `}` that follows its closing message (the function body
# holds a heredoc with its own `}` at column 0, so the first `}` is not the end).
STEP=$(awk '/^configure_statusline\(\) \{/{on=1} on{print} on && /Status line configured/{done=1} done && /^\}/{exit}' \
  "$REPO_ROOT/spex/scripts/spex-init.sh")
if [ -z "$STEP" ]; then
  echo "  FAIL: could not find configure_statusline() in spex-init.sh"; FAIL=$((FAIL + 1))
else
  # $0 must be spex-init.sh: the function finds the statusline script next to it.
  (cd "$MAIN" && bash -c "$STEP"$'\n'"configure_statusline" "$REPO_ROOT/spex/scripts/spex-init.sh" >/dev/null 2>&1) || true
  assert_contains "chain file holds the whole command line" "bash $WORKDIR/bin/prev.sh --compact" \
    "$(cat "$MAIN/.claude/.spex-previous-statusline" 2>/dev/null)"
  OUT=$(run_statusline "$MAIN" "$MAIN")
  assert_contains "and it still shows after init" "PREV[--compact] stdin-ok" "$OUT"
fi
cleanup

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
