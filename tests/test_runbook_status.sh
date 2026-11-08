#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATUS="$REPO_ROOT/spex/scripts/spex-runbook-status.sh"

PASS=0
FAIL=0
TMPDIR=""

cleanup() {
  if [ -n "$TMPDIR" ] && [ -d "$TMPDIR" ]; then
    rm -rf "$TMPDIR"
  fi
}
trap cleanup EXIT

setup_test_repo() {
  TMPDIR=$(mktemp -d)
  cd "$TMPDIR"
  git init -q test-repo
  cd test-repo
  git config user.email test@example.com
  git config user.name "Test User"
  git commit --allow-empty -m "initial" -q
  mkdir -p spex
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

assert_ne() {
  local desc="$1" a="$2" b="$3"
  if [ "$a" != "$b" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected '$a' to differ from '$b')"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected to contain '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

# ─── Test: fingerprint stable across commit and squash ───
echo "=== Test: fingerprint stable across commit and squash ==="
setup_test_repo
echo 'echo hi' > spex/foo.sh
FP1=$("$STATUS" fingerprint)
git add spex/foo.sh
git commit -q -m "add foo"
FP2=$("$STATUS" fingerprint)
assert_eq "fingerprint stable across commit of same content" "$FP1" "$FP2"
git reset --soft HEAD~1 -q
git commit -q -m "squashed"
FP3=$("$STATUS" fingerprint)
assert_eq "fingerprint stable across squash" "$FP1" "$FP3"
cleanup

# ─── Test: fingerprint ignores specs/ and brainstorm/, tracks spex/ ───
echo "=== Test: fingerprint scope ==="
setup_test_repo
echo 'echo hi' > spex/foo.sh
FP_BASE=$("$STATUS" fingerprint)
mkdir -p specs brainstorm
echo "a spec" > specs/thing.md
echo "an idea" > brainstorm/idea.md
FP_DOCS=$("$STATUS" fingerprint)
assert_eq "fingerprint ignores specs/ and brainstorm/" "$FP_BASE" "$FP_DOCS"
echo 'echo bye' > spex/foo.sh
FP_CODE=$("$STATUS" fingerprint)
assert_ne "fingerprint changes when spex/ file changes" "$FP_CODE" "$FP_BASE"
echo 'echo new' > spex/bar.sh
FP_NEW=$("$STATUS" fingerprint)
assert_ne "fingerprint changes when untracked file appears" "$FP_NEW" "$FP_CODE"
cleanup

# ─── Test: locate --create ───
echo "=== Test: locate --create ==="
setup_test_repo
mkdir -p specs/054-x
OUT=$("$STATUS" locate specs/054-x --create)
assert_eq "locate runbook path" "specs/054-x/RUNBOOK.md" "$(echo "$OUT" | jq -r .runbook)"
assert_eq "locate scratch path" "specs/054-x/.walkthrough" "$(echo "$OUT" | jq -r .scratch)"
assert_eq "scratch .gitignore exists" "yes" "$([ -f specs/054-x/.walkthrough/.gitignore ] && echo yes || echo no)"
assert_eq "scratch .gitignore is star" "*" "$(cat specs/054-x/.walkthrough/.gitignore)"
echo "junk" > specs/054-x/.walkthrough/run.log
assert_eq "scratch hidden from git status" "" "$(git status --porcelain specs/054-x/.walkthrough)"
cleanup

# ─── Test: init writes frontmatter ───
echo "=== Test: init frontmatter ==="
setup_test_repo
mkdir -p specs/054-x
printf '# Try it: Thing\n\nbody\n' > specs/054-x/RUNBOOK.md
"$STATUS" init specs/054-x/RUNBOOK.md --feature 054-x --mode light --steps 3
CONTENT=$(cat specs/054-x/RUNBOOK.md)
assert_eq "file starts with frontmatter" "---" "$(head -1 specs/054-x/RUNBOOK.md)"
assert_contains "runbook_version 1" "runbook_version: 1" "$CONTENT"
assert_contains "feature set" "feature: 054-x" "$CONTENT"
assert_contains "status drafted" "status: drafted" "$CONTENT"
assert_contains "mode light" "mode: light" "$CONTENT"
assert_contains "steps_total 3" "steps_total: 3" "$CONTENT"
assert_contains "all results pending" "step_results: pending,pending,pending" "$CONTENT"
assert_contains "status line marker" "<!-- runbook-status -->" "$CONTENT"
assert_contains "status line says drafted" "Status:** drafted" "$CONTENT"
cleanup

# ─── Test: step derivation ───
echo "=== Test: step derivation ==="
setup_test_repo
mkdir -p specs/054-x
printf '# Try it: Thing\n\nbody\n' > specs/054-x/RUNBOOK.md
"$STATUS" init specs/054-x/RUNBOOK.md --feature 054-x --mode light --steps 3
assert_eq "drafted when all pending and no step presented" "drafted" "$("$STATUS" show specs/054-x | jq -r .status)"
"$STATUS" step specs/054-x/RUNBOOK.md 1 passed >/dev/null
assert_eq "in_progress with a pending remaining" "in_progress" "$("$STATUS" show specs/054-x | jq -r .status)"
"$STATUS" step specs/054-x/RUNBOOK.md 2 failed >/dev/null
assert_eq "failed wins over pending" "failed" "$("$STATUS" show specs/054-x | jq -r .status)"
STEP_OUT=$("$STATUS" step specs/054-x/RUNBOOK.md 2 passed)
assert_eq "step prints status json" "in_progress" "$(echo "$STEP_OUT" | jq -r .status)"
"$STATUS" step specs/054-x/RUNBOOK.md 3 skipped >/dev/null
assert_eq "passed when all passed or skipped" "passed" "$("$STATUS" show specs/054-x | jq -r .status)"
cleanup

# ─── Test: steps extend and truncate ───
echo "=== Test: steps extend and truncate ==="
setup_test_repo
mkdir -p specs/054-x
printf '# Try it: Thing\n\nbody\n' > specs/054-x/RUNBOOK.md
"$STATUS" init specs/054-x/RUNBOOK.md --feature 054-x --mode light --steps 3
"$STATUS" steps specs/054-x/RUNBOOK.md 5 >/dev/null
assert_eq "extended steps_total" "5" "$("$STATUS" show specs/054-x | jq -r .steps.total)"
assert_contains "extended with pending" "step_results: pending,pending,pending,pending,pending" "$(cat specs/054-x/RUNBOOK.md)"
"$STATUS" steps specs/054-x/RUNBOOK.md 2 >/dev/null
assert_eq "truncated steps_total" "2" "$("$STATUS" show specs/054-x | jq -r .steps.total)"
assert_contains "truncated results" "step_results: pending,pending" "$(cat specs/054-x/RUNBOOK.md)"
cleanup

# ─── Test: mode downgrade rejected after a non-pending result ───
echo "=== Test: mode downgrade rejected ==="
setup_test_repo
mkdir -p specs/054-x
printf '# Try it: Thing\n\nbody\n' > specs/054-x/RUNBOOK.md
"$STATUS" init specs/054-x/RUNBOOK.md --feature 054-x --mode light --steps 2
"$STATUS" mode specs/054-x/RUNBOOK.md full >/dev/null
assert_eq "upgrade to full allowed" "full" "$("$STATUS" show specs/054-x | jq -r .mode)"
"$STATUS" step specs/054-x/RUNBOOK.md 1 passed >/dev/null
EXIT=0
"$STATUS" mode specs/054-x/RUNBOOK.md light >/dev/null 2>&1 || EXIT=$?
assert_eq "downgrade to light rejected (exit 1)" "1" "$EXIT"
cleanup

# ─── Test: show on missing runbook ───
echo "=== Test: show missing ==="
setup_test_repo
mkdir -p specs/054-x
assert_eq "exists false when no runbook" "false" "$("$STATUS" show specs/054-x | jq -r .exists)"
cleanup

# ─── Test: show current after specs-only vs code change ───
echo "=== Test: show current ==="
setup_test_repo
echo 'echo hi' > spex/foo.sh
git add spex/foo.sh
git commit -q -m "add foo"
mkdir -p specs/054-x
printf '# Try it: Thing\n\nbody\n' > specs/054-x/RUNBOOK.md
"$STATUS" init specs/054-x/RUNBOOK.md --feature 054-x --mode light --steps 1
"$STATUS" step specs/054-x/RUNBOOK.md 1 passed >/dev/null
echo "extra spec text" > specs/054-x/notes.md
assert_eq "current true after specs-only change" "true" "$("$STATUS" show specs/054-x | jq -r .current)"
echo 'echo changed' > spex/foo.sh
OUT=$("$STATUS" show specs/054-x)
assert_eq "current false after code change" "false" "$(echo "$OUT" | jq -r .current)"
assert_contains "changed_files lists code file" "spex/foo.sh" "$(echo "$OUT" | jq -r '.changed_files[]')"
cleanup

# ─── Test: changed_since_draft and squash note ───
echo "=== Test: changed_since_draft and squash note ==="
setup_test_repo
C0=$(git rev-parse HEAD)
echo 'echo hi' > spex/foo.sh
git add spex/foo.sh
git commit -q -m "add foo"
mkdir -p specs/054-x
printf '# Try it: Thing\n\nbody\n' > specs/054-x/RUNBOOK.md
"$STATUS" init specs/054-x/RUNBOOK.md --feature 054-x --mode light --steps 1
assert_eq "changed_since_draft false right after init" "false" "$("$STATUS" show specs/054-x | jq -r .changed_since_draft)"
echo 'echo changed' > spex/foo.sh
assert_eq "changed_since_draft true after code change before any step" "true" "$("$STATUS" show specs/054-x | jq -r .changed_since_draft)"
C1=$(git rev-parse HEAD)
git reset --soft "$C0" -q
git commit -q -m "squashed"
git reflog expire --expire=now --all >/dev/null 2>&1 || true
git gc --prune=now -q >/dev/null 2>&1 || true
assert_eq "drafted commit is gone" "gone" "$(git cat-file -e "$C1" 2>/dev/null && echo present || echo gone)"
OUT=$("$STATUS" show specs/054-x)
assert_eq "changed_since_draft still true via fingerprint" "true" "$(echo "$OUT" | jq -r .changed_since_draft)"
assert_eq "changed_files empty when commit gone" "0" "$(echo "$OUT" | jq -r '.changed_files | length')"
assert_ne "changed_files_note set when commit gone" "null" "$(echo "$OUT" | jq -r '.changed_files_note')"
cleanup

# ─── Test: show on broken frontmatter ───
echo "=== Test: show unreadable ==="
setup_test_repo
mkdir -p specs/054-x
printf -- '---\nthis is not parseable runbook frontmatter\n---\n# Try it\n' > specs/054-x/RUNBOOK.md
OUT=$("$STATUS" show specs/054-x)
assert_eq "readable false on broken frontmatter" "false" "$(echo "$OUT" | jq -r .readable)"
assert_eq "status unreadable on broken frontmatter" "unreadable" "$(echo "$OUT" | jq -r .status)"
cleanup

# ─── Test: show --no-git returns current null ───
echo "=== Test: show --no-git ==="
setup_test_repo
mkdir -p specs/054-x
printf '# Try it: Thing\n\nbody\n' > specs/054-x/RUNBOOK.md
"$STATUS" init specs/054-x/RUNBOOK.md --feature 054-x --mode light --steps 2
assert_eq "current null with --no-git" "null" "$("$STATUS" show specs/054-x --no-git | jq -r .current)"
assert_eq "status still derived with --no-git" "drafted" "$("$STATUS" show specs/054-x --no-git | jq -r .status)"
cleanup

# ─── Test: status line regenerated on every write ───
echo "=== Test: status line regenerated ==="
setup_test_repo
mkdir -p specs/054-x
printf '# Try it: Thing\n\nbody\n' > specs/054-x/RUNBOOK.md
"$STATUS" init specs/054-x/RUNBOOK.md --feature 054-x --mode light --steps 2
assert_contains "status line drafted after init" "Status:** drafted" "$(cat specs/054-x/RUNBOOK.md)"
"$STATUS" step specs/054-x/RUNBOOK.md 1 passed >/dev/null
"$STATUS" step specs/054-x/RUNBOOK.md 2 passed >/dev/null
CONTENT=$(cat specs/054-x/RUNBOOK.md)
assert_contains "status line passed after steps" "Status:** passed" "$CONTENT"
assert_eq "exactly one status line block" "1" "$(grep -c '<!-- runbook-status -->' specs/054-x/RUNBOOK.md)"
cleanup

# ─── Test: locate detach detection and relocation (US6) ───
echo "=== Test: locate detach ==="
setup_test_repo
mkdir -p specs/054-x .specify/extensions/spex-detach/scripts
cat > .specify/extensions/spex-detach/scripts/spex-detach.sh <<'EOF'
#!/bin/sh
if [ "$1" = "is-enabled" ]; then exit "${DETACH_RC:-1}"; fi
exit 0
EOF
chmod +x .specify/extensions/spex-detach/scripts/spex-detach.sh
OUT=$(DETACH_RC=1 "$STATUS" locate specs/054-x)
assert_eq "detach off -> detach false" "false" "$(echo "$OUT" | jq -r .detach)"
assert_eq "detach off -> relocated false" "false" "$(echo "$OUT" | jq -r .relocated)"
assert_eq "detach off -> normal path" "specs/054-x/RUNBOOK.md" "$(echo "$OUT" | jq -r .runbook)"
mkdir -p .git/info
echo "specs/" > .git/info/exclude
OUT=$(DETACH_RC=0 "$STATUS" locate specs/054-x)
assert_eq "detach on + excluded -> detach true" "true" "$(echo "$OUT" | jq -r .detach)"
assert_eq "detach on + excluded -> relocated false" "false" "$(echo "$OUT" | jq -r .relocated)"
assert_eq "detach on + excluded -> normal path" "specs/054-x/RUNBOOK.md" "$(echo "$OUT" | jq -r .runbook)"
: > .git/info/exclude
OUT=$(DETACH_RC=0 "$STATUS" locate specs/054-x)
assert_eq "detach on + not excluded -> relocated true" "true" "$(echo "$OUT" | jq -r .relocated)"
assert_eq "detach on + not excluded -> scratch path" "specs/054-x/.walkthrough/RUNBOOK.md" "$(echo "$OUT" | jq -r .runbook)"
rm -f .specify/extensions/spex-detach/scripts/spex-detach.sh
OUT=$(DETACH_RC=0 "$STATUS" locate specs/054-x)
assert_eq "detach dir without script -> detach false" "false" "$(echo "$OUT" | jq -r .detach)"
cleanup

# ─── Test: show and list find a relocated runbook (US6) ───
echo "=== Test: show/list relocated ==="
setup_test_repo
mkdir -p specs/056-z/.walkthrough
printf '# Try it: z\n\nx\n' > specs/056-z/.walkthrough/RUNBOOK.md
"$STATUS" init specs/056-z/.walkthrough/RUNBOOK.md --feature 056-z --mode light --steps 1
assert_eq "show finds relocated runbook" "true" "$("$STATUS" show specs/056-z | jq -r .exists)"
assert_contains "list finds relocated runbook" "056-z/.walkthrough/RUNBOOK.md" "$("$STATUS" list specs | jq -r '.[].path')"
cleanup

# ─── Test: list returns runbooks from both locations (US3) ───
echo "=== Test: list ==="
setup_test_repo
assert_eq "empty array when no runbooks" "0" "$("$STATUS" list specs | jq 'length')"
mkdir -p specs/054-a specs/055-b/.walkthrough
printf '# Try it: A\n\nx\n' > specs/054-a/RUNBOOK.md
"$STATUS" init specs/054-a/RUNBOOK.md --feature 054-a --mode light --steps 1
printf '# Try it: B\n\nx\n' > specs/055-b/.walkthrough/RUNBOOK.md
"$STATUS" init specs/055-b/.walkthrough/RUNBOOK.md --feature 055-b --mode light --steps 1
LIST_OUT=$("$STATUS" list specs)
assert_eq "list finds both runbooks" "2" "$(echo "$LIST_OUT" | jq 'length')"
assert_contains "list includes normal-location runbook" "054-a/RUNBOOK.md" "$(echo "$LIST_OUT" | jq -r '.[].path')"
assert_contains "list includes scratch-location runbook" "055-b/.walkthrough/RUNBOOK.md" "$(echo "$LIST_OUT" | jq -r '.[].path')"
assert_contains "list entries carry status" "drafted" "$(echo "$LIST_OUT" | jq -r '.[].status')"
cleanup

# ─── Test: not-testable records fingerprint; show reports not_testable (US2) ───
echo "=== Test: not-testable ==="
setup_test_repo
echo 'echo hi' > spex/foo.sh
git add spex/foo.sh
git commit -q -m "add foo"
mkdir -p .specify specs/054-x
echo '{"mode":"flow"}' > .specify/.spex-state
"$STATUS" not-testable specs/054-x
FP_NOW=$("$STATUS" fingerprint)
assert_eq "not-testable records current fingerprint" "$FP_NOW" "$(jq -r '.walkthrough_not_testable_fingerprint' .specify/.spex-state)"
assert_eq "show reports not_testable true" "true" "$("$STATUS" show specs/054-x | jq -r .not_testable)"
assert_eq "show status not_testable" "not_testable" "$("$STATUS" show specs/054-x | jq -r .status)"
assert_eq "show still exists false" "false" "$("$STATUS" show specs/054-x | jq -r .exists)"
echo 'echo bye' > spex/foo.sh
assert_eq "not_testable false after a code change" "false" "$("$STATUS" show specs/054-x | jq -r .not_testable)"
cleanup

# ─── Test: not-testable is a no-op without a state file (US2) ───
echo "=== Test: not-testable no-op ==="
setup_test_repo
mkdir -p specs/054-x
"$STATUS" not-testable specs/054-x
assert_eq "no state file created" "absent" "$([ -f .specify/.spex-state ] && echo present || echo absent)"
cleanup

# ─── Test: reset marks a passed runbook stale (059 FR-030) ───
echo "=== Test: reset marks a passed runbook stale ==="
setup_test_repo
mkdir -p specs/054-x
printf '# Try it: Thing\n\nbody\n' > specs/054-x/RUNBOOK.md
"$STATUS" init specs/054-x/RUNBOOK.md --feature 054-x --mode light --steps 3
DRAFTED_AT=$(grep '^drafted_at:' specs/054-x/RUNBOOK.md)
for n in 1 2 3; do "$STATUS" step specs/054-x/RUNBOOK.md "$n" passed >/dev/null; done
assert_eq "precondition: passed" "passed" "$("$STATUS" show specs/054-x | jq -r .status)"
assert_eq "never-reset runbook has no stale_reason key" "0" "$(grep -c '^stale_reason:' specs/054-x/RUNBOOK.md || true)"
RESET_OUT=$("$STATUS" reset specs/054-x --reason "spec evolved 2026-11-08:
  FR-004 → FR-029")
assert_eq "reset prints stale status" "stale" "$(echo "$RESET_OUT" | jq -r .status)"
SHOW=$("$STATUS" show specs/054-x)
assert_eq "status stale" "stale" "$(echo "$SHOW" | jq -r .status)"
assert_eq "all steps pending" "3" "$(echo "$SHOW" | jq -r .steps.pending)"
assert_eq "tested_at cleared" "null" "$(echo "$SHOW" | jq -r .tested_at)"
assert_eq "reason collapsed to one line" "spec evolved 2026-11-08: FR-004 → FR-029" "$(echo "$SHOW" | jq -r .stale_reason)"
assert_eq "draft stamp kept" "$DRAFTED_AT" "$(grep '^drafted_at:' specs/054-x/RUNBOOK.md)"
assert_contains "status block names the reset" "Reset: spec evolved 2026-11-08: FR-004 → FR-029; step results below predate it" "$(cat specs/054-x/RUNBOOK.md)"
"$STATUS" steps specs/054-x/RUNBOOK.md 4
assert_eq "steps keeps stale while all pending" "stale" "$("$STATUS" show specs/054-x | jq -r .status)"
"$STATUS" step specs/054-x/RUNBOOK.md 1 passed >/dev/null
SHOW=$("$STATUS" show specs/054-x)
assert_eq "step after reset leaves stale" "in_progress" "$(echo "$SHOW" | jq -r .status)"
assert_eq "step after reset clears stale_reason" "null" "$(echo "$SHOW" | jq -r .stale_reason)"
assert_eq "stale_reason key removed" "0" "$(grep -c '^stale_reason:' specs/054-x/RUNBOOK.md || true)"
cleanup

# ─── Test: init clears a stale reset ───
echo "=== Test: init clears a stale reset ==="
setup_test_repo
mkdir -p specs/054-x
printf '# Try it: Thing\n\nbody\n' > specs/054-x/RUNBOOK.md
"$STATUS" init specs/054-x/RUNBOOK.md --feature 054-x --mode light --steps 2
"$STATUS" reset specs/054-x --reason "spec evolved" >/dev/null
"$STATUS" init specs/054-x/RUNBOOK.md --feature 054-x --mode light --steps 2
assert_eq "init returns to drafted" "drafted" "$("$STATUS" show specs/054-x | jq -r .status)"
assert_eq "init drops stale_reason" "0" "$(grep -c '^stale_reason:' specs/054-x/RUNBOOK.md || true)"
cleanup

# ─── Test: reset without a runbook is a no-op ───
echo "=== Test: reset without a runbook ==="
setup_test_repo
mkdir -p specs/054-x
NO_OUT=$("$STATUS" reset specs/054-x --reason "spec evolved"); NO_RC=$?
assert_eq "exit 0" "0" "$NO_RC"
assert_eq "reports reset false" "false" "$(echo "$NO_OUT" | jq -r .reset)"
assert_eq "no runbook created" "absent" "$([ -f specs/054-x/RUNBOOK.md ] && echo present || echo absent)"
cleanup

# ─── Summary ───
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
