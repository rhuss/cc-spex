#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DETACH_SCRIPT="$REPO_ROOT/spex/extensions/spex-detach/scripts/spex-detach.py"

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
  git commit --allow-empty -m "initial" -q
  mkdir -p .specify/extensions/spex-detach
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
  if echo "$haystack" | grep -q "$needle"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected to contain '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if ! echo "$haystack" | grep -q "$needle"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected NOT to contain '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

# ─── Test: enable writes exclude entries ───
echo "=== Test: enable writes exclude entries ==="
setup_test_repo
RESULT=$(python3 "$DETACH_SCRIPT" enable 2>/dev/null)
ADDED=$(echo "$RESULT" | jq -r '.paths_added | length')
assert_eq "3 paths added" "3" "$ADDED"

EXCLUDE_CONTENT=$(cat .git/info/exclude)
assert_contains "exclude has .specify/" ".specify/" "$EXCLUDE_CONTENT"
assert_contains "exclude has specs/" "specs/" "$EXCLUDE_CONTENT"
assert_contains "exclude has brainstorm/" "brainstorm/" "$EXCLUDE_CONTENT"
assert_contains "exclude has header comment" "spex-detach" "$EXCLUDE_CONTENT"
cleanup

# ─── Test: enable is idempotent ───
echo "=== Test: enable is idempotent ==="
setup_test_repo
python3 "$DETACH_SCRIPT" enable >/dev/null 2>&1
RESULT=$(python3 "$DETACH_SCRIPT" enable 2>/dev/null)
ADDED=$(echo "$RESULT" | jq -r '.paths_added | length')
ALREADY=$(echo "$RESULT" | jq -r '.already_present')
assert_eq "0 paths added on second run" "0" "$ADDED"
assert_eq "3 already present" "3" "$ALREADY"

LINE_COUNT=$(grep -c "specs/" .git/info/exclude)
assert_eq "no duplicate specs/ entry" "1" "$LINE_COUNT"
cleanup

# ─── Test: enable preserves existing entries ───
echo "=== Test: enable preserves existing entries ==="
setup_test_repo
mkdir -p .git/info
echo "*.log" > .git/info/exclude
echo "build/" >> .git/info/exclude
python3 "$DETACH_SCRIPT" enable >/dev/null 2>&1

EXCLUDE_CONTENT=$(cat .git/info/exclude)
assert_contains "preserves *.log" "*.log" "$EXCLUDE_CONTENT"
assert_contains "preserves build/" "build/" "$EXCLUDE_CONTENT"
assert_contains "adds .specify/" ".specify/" "$EXCLUDE_CONTENT"
cleanup

# ─── Test: enable warns on tracked files ───
echo "=== Test: enable warns on tracked files ==="
setup_test_repo
mkdir -p specs
echo "test" > specs/test.md
git add specs/test.md
git commit -q -m "add spec file"

STDERR=$(python3 "$DETACH_SCRIPT" enable 2>&1 >/dev/null || true)
assert_contains "warns about tracked files" "tracked by git" "$STDERR"

RESULT=$(python3 "$DETACH_SCRIPT" enable 2>/dev/null)
TRACKED=$(echo "$RESULT" | jq -r '.tracked_warning // [] | .[0]')
assert_eq "tracked warning includes specs" "specs" "$TRACKED"
cleanup

# ─── Test: enable creates .git/info/ directory ───
echo "=== Test: enable creates .git/info/ directory ==="
setup_test_repo
rm -rf .git/info
python3 "$DETACH_SCRIPT" enable >/dev/null 2>&1
assert_eq ".git/info/ directory created" "true" "$([ -d .git/info ] && echo true || echo false)"
assert_eq "exclude file created" "true" "$([ -f .git/info/exclude ] && echo true || echo false)"
cleanup

# ─── Test: enable hides files from git status ───
echo "=== Test: enable hides files from git status ==="
setup_test_repo
python3 "$DETACH_SCRIPT" enable >/dev/null 2>&1

mkdir -p .specify specs brainstorm
echo "spec content" > .specify/test.md
echo "spec content" > specs/test.md
echo "brainstorm content" > brainstorm/test.md

STATUS=$(git status --porcelain)
assert_not_contains "git status hides .specify/" ".specify/" "$STATUS"
assert_not_contains "git status hides specs/" "specs/" "$STATUS"
assert_not_contains "git status hides brainstorm/" "brainstorm/" "$STATUS"
cleanup

# ─── Test: enable does not hide from git add -f ───
echo "=== Test: enable does not hide from git add -f ==="
setup_test_repo
python3 "$DETACH_SCRIPT" enable >/dev/null 2>&1

mkdir -p .specify
echo "force add" > .specify/forced.md
git add -f .specify/forced.md
STAGED=$(git diff --cached --name-only)
assert_contains "git add -f stages excluded file" ".specify/forced.md" "$STAGED"
git reset HEAD .specify/forced.md -q
cleanup

# ─── Test: is-enabled returns 0 when extension dir exists ───
echo "=== Test: is-enabled returns exit 0 when extension dir exists ==="
setup_test_repo
EXIT_CODE=0
python3 "$DETACH_SCRIPT" is-enabled 2>/dev/null || EXIT_CODE=$?
assert_eq "is-enabled returns 0" "0" "$EXIT_CODE"
cleanup

# ─── Test: is-enabled returns 1 when extension dir missing ───
echo "=== Test: is-enabled returns exit 1 when extension dir missing ==="
setup_test_repo
rm -rf .specify/extensions/spex-detach
EXIT_CODE=0
python3 "$DETACH_SCRIPT" is-enabled 2>/dev/null || EXIT_CODE=$?
assert_eq "is-enabled returns 1" "1" "$EXIT_CODE"
cleanup

# ─── Test: enable fails outside git repo ───
echo "=== Test: enable fails outside git repo ==="
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
EXIT_CODE=0
python3 "$DETACH_SCRIPT" enable 2>/dev/null || EXIT_CODE=$?
assert_eq "enable fails outside git repo" "1" "$EXIT_CODE"
cleanup

# ─── Test: archive with no path configured ───
echo "=== Test: archive skips when no path configured ==="
setup_test_repo
RESULT=$(python3 "$DETACH_SCRIPT" archive 2>/dev/null)
SKIPPED=$(echo "$RESULT" | jq -r '.skipped')
assert_eq "archive skipped" "true" "$SKIPPED"
cleanup

# ─── Test: archive copies to sibling repo ───
echo "=== Test: archive copies to sibling repo ==="
TMPDIR=$(mktemp -d)
cd "$TMPDIR"

git init -q test-repo
cd test-repo
git commit --allow-empty -m "initial" -q
git checkout -b test-feature -q
mkdir -p .specify/extensions/spex-detach specs/test-feature
echo "spec" > .specify/test.md
echo "spec" > specs/test-feature/spec.md

cd "$TMPDIR"
git init -q specs-archive
cd specs-archive
git commit --allow-empty -m "initial" -q

cd "$TMPDIR/test-repo"
RESULT=$(python3 "$DETACH_SCRIPT" archive --target "$TMPDIR/specs-archive" 2>/dev/null)
FILES=$(echo "$RESULT" | jq -r '.files_copied')
COMMITTED=$(echo "$RESULT" | jq -r '.committed')
assert_eq "files copied" "true" "$([ "$FILES" -gt 0 ] && echo true || echo false)"
assert_eq "auto-committed" "true" "$COMMITTED"

PROJECT_NAME=$(basename "$(git remote get-url origin 2>/dev/null || pwd)")
assert_eq "archive dir exists" "true" "$([ -d "$TMPDIR/specs-archive/$PROJECT_NAME/test-feature" ] && echo true || echo false)"
assert_eq ".specify/ archived" "true" "$([ -f "$TMPDIR/specs-archive/$PROJECT_NAME/test-feature/.specify/test.md" ] && echo true || echo false)"
assert_eq "specs/<feature>/ archived" "true" "$([ -f "$TMPDIR/specs-archive/$PROJECT_NAME/test-feature/specs/test-feature/spec.md" ] && echo true || echo false)"
cleanup

# ─── Test: archive includes brainstorm by default ───
echo "=== Test: archive includes brainstorm by default ==="
TMPDIR=$(mktemp -d)
cd "$TMPDIR"

git init -q test-repo
cd test-repo
git commit --allow-empty -m "initial" -q
git checkout -b test-feature -q
mkdir -p .specify/extensions/spex-detach brainstorm
echo "idea" > brainstorm/idea.md

cd "$TMPDIR"
git init -q specs-archive
cd specs-archive
git commit --allow-empty -m "initial" -q

cd "$TMPDIR/test-repo"
RESULT=$(python3 "$DETACH_SCRIPT" archive --target "$TMPDIR/specs-archive" 2>/dev/null)
FILES=$(echo "$RESULT" | jq -r '.files_copied')
assert_eq "brainstorm files copied" "true" "$([ "$FILES" -gt 0 ] && echo true || echo false)"

PROJECT_NAME=$(basename "$(git remote get-url origin 2>/dev/null || pwd)")
assert_eq "brainstorm/ archived" "true" "$([ -f "$TMPDIR/specs-archive/$PROJECT_NAME/test-feature/brainstorm/idea.md" ] && echo true || echo false)"
cleanup

# ─── Test: archive fails when target dir does not exist ───
echo "=== Test: archive fails when target dir does not exist ==="
setup_test_repo
EXIT_CODE=0
python3 "$DETACH_SCRIPT" archive --target "/nonexistent/path" 2>/dev/null || EXIT_CODE=$?
assert_eq "archive fails with bad target" "1" "$EXIT_CODE"
cleanup

# ─── Test: archive does not overwrite existing archives ───
echo "=== Test: archive does not overwrite existing archives ==="
TMPDIR=$(mktemp -d)
cd "$TMPDIR"

git init -q test-repo
cd test-repo
git commit --allow-empty -m "initial" -q
git checkout -b feature-one -q
mkdir -p .specify/extensions/spex-detach specs/feature-one
echo "first spec" > specs/feature-one/spec.md

cd "$TMPDIR"
git init -q specs-archive
cd specs-archive
git commit --allow-empty -m "initial" -q

cd "$TMPDIR/test-repo"
python3 "$DETACH_SCRIPT" archive --target "$TMPDIR/specs-archive" >/dev/null 2>&1

git checkout -b feature-two -q
mkdir -p specs/feature-two
echo "second spec" > specs/feature-two/spec.md
python3 "$DETACH_SCRIPT" archive --target "$TMPDIR/specs-archive" >/dev/null 2>&1

PROJECT_NAME=$(basename "$(git remote get-url origin 2>/dev/null || pwd)")
assert_eq "first archive preserved" "true" "$([ -f "$TMPDIR/specs-archive/$PROJECT_NAME/feature-one/specs/feature-one/spec.md" ] && echo true || echo false)"
assert_eq "second archive exists" "true" "$([ -f "$TMPDIR/specs-archive/$PROJECT_NAME/feature-two/specs/feature-two/spec.md" ] && echo true || echo false)"
cleanup

# ─── Summary ───
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
