#!/usr/bin/env bash
# Tests for the pre-commit verification reminder hooks (spec 055):
# spex/scripts/hooks/shared/verify-gate.sh and spex/scripts/hooks/pretool-gate.py
# both read the shared verification record (spex-verify-record.sh) and must
# agree on when the reminder is relevant (active feature, code in the commit,
# once per session per feature).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GATE="$REPO_ROOT/spex/scripts/hooks/shared/verify-gate.sh"
PRETOOL="$REPO_ROOT/spex/scripts/hooks/pretool-gate.py"
RECORD="$REPO_ROOT/spex/scripts/spex-verify-record.sh"

REMINDER="spex verify reminder: Feature 056-demo has code changes with no recorded verification."

# Isolate from the developer's git config (global ignores, signing, hooks)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

PASS=0
FAIL=0
WORKDIR=""
SID_COUNTER=0

cleanup() {
  cd "$REPO_ROOT" || true
  if [ -n "$WORKDIR" ] && [ -d "$WORKDIR" ]; then
    rm -rf "$WORKDIR"
  fi
  WORKDIR=""
}
trap cleanup EXIT

# Repo on feature branch 056-demo with tasks.md and a staged code change.
setup_test_repo() {
  WORKDIR=$(mktemp -d)
  cd "$WORKDIR" || exit 1
  git init -q -b main test-repo
  cd test-repo || exit 1
  git config user.email test@example.com
  git config user.name "Test User"
  git commit --allow-empty -m "initial" -q
  git checkout -q -b 056-demo
  mkdir -p .specify src specs/056-demo docs
  echo '- [ ] T001 demo' > specs/056-demo/tasks.md
  echo 'echo hi' > src/app.sh
  git add src/app.sh
  REPO="$(pwd -P)"
  HOOK_TMP="$WORKDIR/tmp"
  mkdir -p "$HOOK_TMP"
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

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if printf '%s\n' "$haystack" | grep -qF -- "$needle"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected to contain '$needle', got '$haystack')"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if printf '%s\n' "$haystack" | grep -qF -- "$needle"; then
    echo "  FAIL: $desc (did not expect '$needle', got '$haystack')"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  fi
}

# new_sid: set SID to a fresh session id (no subshell, so the counter advances)
new_sid() {
  SID_COUNTER=$((SID_COUNTER + 1))
  SID="sid$SID_COUNTER"
}

# run_impl <gate|pretool> <command> <sid>: set OUT (empty when silent) and ELAPSED
run_impl() {
  local impl="$1" cmd="$2" sid="$3" start
  start=$(date +%s)
  if [ "$impl" = gate ]; then
    OUT=$(TMPDIR="$HOOK_TMP" sh "$GATE" Bash "$cmd" "$sid" "$REPO" 2>&1)
    [ "$OUT" = "allow" ] && OUT=""
  else
    OUT=$(jq -nc --arg c "$cmd" --arg s "$sid" --arg d "$REPO" \
      '{tool_name:"Bash",tool_input:{command:$c},session_id:$s,cwd:$d}' \
      | TMPDIR="$HOOK_TMP" python3 "$PRETOOL" 2>&1)
  fi
  ELAPSED=$(( $(date +%s) - start ))
}

# expect <shown|silent> <desc> [command] [sid]: check both implementations.
# A fresh session id per implementation unless one is given.
expect() {
  local want="$1" desc="$2" cmd="${3:-git commit -m x}" sid="${4:-}" impl s
  for impl in gate pretool; do
    new_sid
    s="${sid:-$SID}"
    run_impl "$impl" "$cmd" "$s"
    if [ "$want" = shown ]; then
      assert_contains "[$impl] $desc" "$REMINDER" "$OUT"
    else
      assert_eq "[$impl] $desc" "" "$OUT"
    fi
  done
}

echo "=== Test: reminder content and verification record ==="
setup_test_repo
for impl in gate pretool; do
  new_sid
  run_impl "$impl" "git commit -m x" "$SID"
  assert_contains "[$impl] no record: reminder names the feature" "$REMINDER" "$OUT"
  assert_contains "[$impl] reminder names /speckit-spex-gates-verify" "/speckit-spex-gates-verify" "$OUT"
  assert_contains "[$impl] reminder names /speckit-spex-finish" "/speckit-spex-finish" "$OUT"
  assert_not_contains "[$impl] reminder does not mention stamp" "stamp" "$OUT"
  assert_eq "[$impl] no record: completes in under 5s" "true" "$([ "$ELAPSED" -lt 5 ] && echo true || echo false)"
done
new_sid
run_impl gate "git commit -m x" "$SID"
assert_contains "[gate] output has context: prefix" "context:spex verify reminder:" "$OUT"
touch "$HOOK_TMP/.claude-spex-verified-legacy"
expect shown "legacy session marker is ignored" "git commit -m x" ""
"$RECORD" record >/dev/null
expect silent "with record: silent"
echo 'echo changed' >> src/app.sh
git add src/app.sh
expect shown "after code edit: reminder again"
cleanup

echo "=== Test: relevance (only for a feature in progress) ==="
setup_test_repo
git checkout -q main
expect silent "main branch: silent"
git checkout -q -b fix-typo
expect silent "non-feature branch: silent"
git checkout -q 056-demo
rm specs/056-demo/tasks.md
expect silent "feature before tasks.md: silent"
echo '- [ ] T001' > specs/056-demo/tasks.md
git checkout -q -b 056-demo-rework
expect shown "branch with unique number prefix match: shown"
git checkout -q main
git checkout -q -b custom-name
printf '{"feature_branch":"custom-name","spec_dir":"specs/056-demo"}' > .specify/.spex-state
expect shown ".spex-state maps custom branch to feature: shown"
git checkout -q 056-demo
printf '{"mode":"flow","implemented":false,"feature_branch":"056-demo"}' > .specify/.spex-state
expect silent "flow mode before implement: silent"
printf '{"mode":"flow","implemented":false,"feature_branch":"099-other"}' > .specify/.spex-state
expect shown "stale flow state of another feature is ignored"
printf '{"mode":"flow","implemented":true,"feature_branch":"056-demo"}' > .specify/.spex-state
expect shown "flow mode after implement: shown"
rm .specify/.spex-state
rm -rf .specify
expect silent "no .specify: silent"
cleanup

echo "=== Test: what the commit carries ==="
setup_test_repo
git reset -q
expect silent "nothing staged: silent"
expect shown "git add + commit in one call: shown" "git add src/app.sh && git commit -m x"
expect shown "git commit -am: shown" "git commit -am x"
expect shown "git commit --all: shown" "git commit --all -m x"
expect silent "git commit --amend with nothing staged: silent" "git commit --amend --no-edit"
rm src/app.sh
echo 'notes' > docs/guide.md
echo 'more' >> specs/056-demo/tasks.md
expect silent "git add of docs only in one call: silent" "git add docs specs && git commit -m x"
expect silent "git commit -am with docs only: silent" "git commit -am x"
git add docs
expect silent "staged docs only: silent"
cleanup

echo "=== Test: once per session per feature ==="
setup_test_repo
for impl in gate pretool; do
  run_impl "$impl" "git commit -m x" "same-$impl"
  assert_contains "[$impl] first commit in session: shown" "$REMINDER" "$OUT"
  run_impl "$impl" "git commit -m y" "same-$impl"
  assert_eq "[$impl] second commit in same session: silent" "" "$OUT"
  run_impl "$impl" "git commit -m z" "other-$impl"
  assert_contains "[$impl] new session: shown again" "$REMINDER" "$OUT"
  run_impl "$impl" "git commit -m x" "unknown"
  run_impl "$impl" "git commit -m x" "unknown"
  assert_contains "[$impl] unknown session id: never deduplicated" "$REMINDER" "$OUT"
done
cleanup

echo "=== Test: pretool-gate.py timeout kills the record check ==="
setup_test_repo
# Copy the hook next to a stub record script that hangs, as in a huge repo.
mkdir -p "$WORKDIR/plugin/scripts/hooks"
cp "$PRETOOL" "$WORKDIR/plugin/scripts/hooks/pretool-gate.py"
HANG="29.$(( $$ % 1000 + 100 ))"   # unique sleep argument to find leftovers
printf '#!/bin/sh\nsleep %s\n' "$HANG" > "$WORKDIR/plugin/scripts/spex-verify-record.sh"
START=$(date +%s)
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"session_id":"sid","cwd":"%s"}' "$REPO" \
  | TMPDIR="$HOOK_TMP" python3 "$WORKDIR/plugin/scripts/hooks/pretool-gate.py" 2>&1)
ELAPSED=$(( $(date +%s) - START ))
assert_contains "timeout: reminder shown" "$REMINDER" "$OUT"
assert_eq "timeout: returns within 9s" "true" "$([ "$ELAPSED" -lt 9 ] && echo true || echo false)"
LEFT=$(ps -eo args | grep -F "sleep $HANG" | grep -v grep | wc -l | tr -d ' ')
assert_eq "timeout: no child process left running" "0" "$LEFT"
cleanup

echo "=== Test: pretool-gate.py timeout leaves no temp index behind ==="
setup_test_repo
mkdir -p "$WORKDIR/plugin/scripts/hooks" "$WORKDIR/bin"
cp "$PRETOOL" "$WORKDIR/plugin/scripts/hooks/pretool-gate.py"
cp "$RECORD" "$REPO_ROOT/spex/scripts/spex-runbook-status.sh" "$REPO_ROOT/spex/scripts/spex-runbook-status.py" "$WORKDIR/plugin/scripts/"
REAL_GIT=$(command -v git)
# git shim: `git add` (the fingerprint's temp-index build) hangs past the timeout
cat > "$WORKDIR/bin/git" <<SHIM
#!/bin/sh
[ "\$1" = add ] && sleep 20
exec "$REAL_GIT" "\$@"
SHIM
chmod +x "$WORKDIR/bin/git"
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"session_id":"sid","cwd":"%s"}' "$REPO" \
  | PATH="$WORKDIR/bin:$PATH" TMPDIR="$HOOK_TMP" python3 "$WORKDIR/plugin/scripts/hooks/pretool-gate.py" 2>&1)
assert_contains "slow fingerprint: reminder shown" "$REMINDER" "$OUT"
sleep 1
LEFT=$(find "$HOOK_TMP" -mindepth 1 -maxdepth 1 -name 'tmp*' | wc -l | tr -d ' ')
assert_eq "slow fingerprint: temp index directory removed" "0" "$LEFT"
cleanup

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
