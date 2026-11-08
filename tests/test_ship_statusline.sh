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


echo "Test: the chain also works without stdin, and with an active ship state"
setup
make_prev "$WORKDIR/bin/prev.sh"
mkdir -p "$MAIN/.claude"
printf '%s\n' "bash $WORKDIR/bin/prev.sh --compact" > "$MAIN/.claude/.spex-previous-statusline"
OUT=$(cd "$MAIN" && env -u SHIP_STATE_FILE CLAUDE_PROJECT_DIR="$MAIN" bash "$STATUSLINE" </dev/null 2>/dev/null)
assert_contains "no stdin: argument passed, no stdin seen" "PREV[--compact] no-stdin" "$OUT"
ship_state implement 6 > "$MAIN/.specify/.spex-state"
OUT=$(run_statusline "$MAIN" "$MAIN")
if [[ "$OUT" == "PREV[--compact] stdin-ok "* ]]; then
  echo "  PASS: chain output comes first, then one space, then the spex line"; PASS=$((PASS + 1))
else
  echo "  FAIL: expected output to start with 'PREV[--compact] stdin-ok ' (got '$OUT')"; FAIL=$((FAIL + 1))
fi
assert_contains "spex line shown after the chain output" "implement" "$OUT"
cleanup

echo "Test: a chained wrapper that calls the spex script again does not loop"
setup
mkdir -p "$MAIN/.claude" "$WORKDIR/bin"
cat > "$WORKDIR/bin/wrapper.sh" <<WRAP
#!/usr/bin/env bash
printf 'W['
bash "$STATUSLINE" </dev/null
printf ']'
WRAP
chmod +x "$WORKDIR/bin/wrapper.sh"
printf '%s\n' "bash $WORKDIR/bin/wrapper.sh" > "$MAIN/.claude/.spex-previous-statusline"
# timeout turns an endless loop into a failed assertion instead of a hung test run.
OUT=$(cd "$MAIN" && echo '{}' | timeout 15 env -u SHIP_STATE_FILE -u SPEX_STATUSLINE_CHAINING CLAUDE_PROJECT_DIR="$MAIN" bash "$STATUSLINE" 2>/dev/null || echo "TIMEOUT-OR-ERROR")
assert_contains "wrapper output appears once, inner spex stays silent" "W[]" "$OUT"
assert_not_contains "no timeout" "TIMEOUT" "$OUT"
cleanup

# --- The status-line step exists twice: configure_statusline() in spex-init.sh and the
# claude-statusline step in setup.yml. Both are extracted from the real files and run against
# the same cases, so neither copy can drift unnoticed. ---

# From the function header to the `}` that follows its closing message (the function body
# holds a heredoc with its own `}` at column 0, so the first `}` is not the end).
INIT_STEP=$(awk '/^configure_statusline\(\) \{/{on=1} on{print} on && /Status line configured/{done=1} done && /^\}/{exit}' \
  "$REPO_ROOT/spex/scripts/spex-init.sh")
# From the step's `run: |` line to the next case (`codex:`), minus its 12-space indent.
SETUP_STEP=$(awk '/- id: claude-statusline/{f=1; next} f && /^ *run: \|/{r=1; next} r && /^      codex:/{exit} r{sub(/^ {12}/, ""); print}' \
  "$REPO_ROOT/spex/setup.yml")

# An extract that did not end where expected would run far more than the step (for init, the
# whole script's main dispatch), so refuse to run anything that does not look right.
INIT_LAST_LINE=$(printf '%s\n' "$INIT_STEP" | tail -n 1)
case "$INIT_STEP" in
  "configure_statusline() {"*) INIT_OK=yes ;;
  *) INIT_OK=no ;;
esac
if [ "$INIT_LAST_LINE" != "}" ] || [[ "$INIT_STEP" == *do_init* ]]; then INIT_OK=no; fi
case "$SETUP_STEP" in
  'SOURCE="${SPEX_SOURCE:-$SPECKIT_WORKFLOW_DIR}"'*) SETUP_OK=yes ;;
  *) SETUP_OK=no ;;
esac
if [ "$SETUP_OK" = "yes" ] && [[ "$SETUP_STEP" == *"id: codex"* ]]; then SETUP_OK=no; fi

# Run one copy of the step inside $MAIN. $1 = init | setup. stderr goes to $WORKDIR/step.err.
run_step() {
  if [ "$1" = "init" ]; then
    # $0 must be spex-init.sh: the function finds the statusline script next to it.
    (cd "$MAIN" && bash -c "$INIT_STEP"$'\n'"configure_statusline" "$REPO_ROOT/spex/scripts/spex-init.sh" >/dev/null 2>"$WORKDIR/step.err") || true
  else
    (cd "$MAIN" && SPEX_SOURCE="$REPO_ROOT/spex" bash -c "$SETUP_STEP" >/dev/null 2>"$WORKDIR/step.err") || true
  fi
}

settings_command() {
  jq -r '.statusLine.command // empty' "$MAIN/.claude/settings.local.json" 2>/dev/null
}

CHAIN_REL=".claude/.spex-previous-statusline"

for KIND in init setup; do
  OK_VAR="${KIND^^}_OK"
  if [ "${!OK_VAR}" != "yes" ]; then
    echo "  FAIL: could not extract the $KIND status-line step cleanly"; FAIL=$((FAIL + 1))
    continue
  fi

  echo "Test [$KIND]: a status line given as a command line is chained and spex is installed (#54)"
  setup
  make_prev "$WORKDIR/bin/prev.sh"
  mkdir -p "$MAIN/.claude"
  printf '{"statusLine":{"type":"command","command":"bash %s --compact"}}\n' "$WORKDIR/bin/prev.sh" > "$MAIN/.claude/settings.local.json"
  run_step "$KIND"
  assert_contains "chain file holds the whole command line" "bash $WORKDIR/bin/prev.sh --compact" \
    "$(cat "$MAIN/$CHAIN_REL" 2>/dev/null)"
  assert_contains "settings now point at the spex script" "spex-ship-statusline.sh" "$(settings_command)"
  # Run the command that settings now hold (not $STATUSLINE directly): this is what Claude Code runs.
  OUT=$(cd "$MAIN" && printf '{"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":42}}' "$MAIN" \
    | env -u SHIP_STATE_FILE CLAUDE_PROJECT_DIR="$MAIN" bash -c "$(settings_command)" 2>/dev/null | sed $'s/\033\\[[0-9;]*m//g')
  assert_contains "the old status line still shows after setup" "PREV[--compact] stdin-ok" "$OUT"

  echo "Test [$KIND]: running it twice changes nothing (idempotent)"
  CHAIN_BEFORE=$(cat "$MAIN/$CHAIN_REL")
  SETTINGS_BEFORE=$(cat "$MAIN/.claude/settings.local.json")
  run_step "$KIND"
  assert_contains "chain file unchanged" "$CHAIN_BEFORE" "$(cat "$MAIN/$CHAIN_REL")"
  assert_contains "settings unchanged" "$SETTINGS_BEFORE" "$(cat "$MAIN/.claude/settings.local.json")"
  cleanup

  echo "Test [$KIND]: a dead spex path is refreshed, not kept and not chained"
  for DEAD in "/nonexistent/spex-ship-statusline.sh" "bash /nonexistent/spex-ship-statusline.sh"; do
    setup
    mkdir -p "$MAIN/.claude"
    printf '{"statusLine":{"type":"command","command":"%s"}}\n' "$DEAD" > "$MAIN/.claude/settings.local.json"
    run_step "$KIND"
    assert_not_contains "'$DEAD' replaced in settings" "nonexistent" "$(settings_command)"
    assert_contains "'$DEAD': settings point at the real script" "/spex/scripts/spex-ship-statusline.sh" "$(settings_command)"
    if [ -f "$MAIN/$CHAIN_REL" ]; then
      echo "  FAIL: '$DEAD' was saved as a chain target"; FAIL=$((FAIL + 1))
    else
      echo "  PASS: '$DEAD' was not saved as a chain target"; PASS=$((PASS + 1))
    fi
    cleanup
  done

  echo "Test [$KIND]: a wrapper that only mentions the spex script as an argument is chained"
  setup
  mkdir -p "$MAIN/.claude"
  printf '{"statusLine":{"type":"command","command":"bash /x/wrapper.sh /y/spex-ship-statusline.sh --compact"}}\n' > "$MAIN/.claude/settings.local.json"
  run_step "$KIND"
  assert_contains "wrapper saved as the chain target" "bash /x/wrapper.sh /y/spex-ship-statusline.sh --compact" \
    "$(cat "$MAIN/$CHAIN_REL" 2>/dev/null)"
  cleanup

  echo "Test [$KIND]: when the old command cannot be saved, the old status line is left alone"
  setup
  mkdir -p "$MAIN/.claude"
  printf '{"statusLine":{"type":"command","command":"bash /x/prev.sh --compact"}}\n' > "$MAIN/.claude/settings.local.json"
  # A directory where the chain file should go makes the write fail on every platform and for
  # root alike (a read-only folder would not).
  mkdir -p "$MAIN/$CHAIN_REL"
  SETTINGS_BEFORE=$(cat "$MAIN/.claude/settings.local.json")
  run_step "$KIND"
  assert_contains "a warning says it could not save" "could not save the existing status line" "$(cat "$WORKDIR/step.err")"
  assert_not_contains "no raw shell error as well" "Is a directory" "$(cat "$WORKDIR/step.err")"
  assert_contains "settings.local.json is untouched" "$SETTINGS_BEFORE" "$(cat "$MAIN/.claude/settings.local.json")"
  cleanup
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
