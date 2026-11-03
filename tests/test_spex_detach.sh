#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DETACH_SCRIPT="$REPO_ROOT/spex/extensions/spex-detach/scripts/spex-detach.py"

PASS=0
FAIL=0
TMPDIR=""

# Isolate git from the developer's global configuration: a global excludes
# file would change what git reports as ignored.
GIT_ISOLATION_HOME=$(mktemp -d)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$GIT_ISOLATION_HOME"
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

cleanup() {
  if [ -n "$TMPDIR" ] && [ -d "$TMPDIR" ]; then
    rm -rf "$TMPDIR"
  fi
}
trap 'cleanup; rm -rf "$GIT_ISOLATION_HOME"' EXIT

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
  if printf "%s\n" "$haystack" | grep -qF -- "$needle"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected to contain '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if ! printf "%s\n" "$haystack" | grep -qF -- "$needle"; then
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

# ─── Test: is-enabled returns 0 when enabled in registry ───
echo "=== Test: is-enabled returns exit 0 when enabled in registry ==="
setup_test_repo
echo '{"extensions":{"spex-detach":{"enabled":true}}}' > .specify/extensions/.registry
EXIT_CODE=0
python3 "$DETACH_SCRIPT" is-enabled 2>/dev/null || EXIT_CODE=$?
assert_eq "is-enabled returns 0" "0" "$EXIT_CODE"
cleanup

# ─── Test: is-enabled returns 1 when installed but disabled ───
# The extension directory stays on disk when the extension is disabled.
echo "=== Test: is-enabled returns exit 1 when disabled in registry ==="
setup_test_repo
echo '{"extensions":{"spex-detach":{"enabled":false}}}' > .specify/extensions/.registry
EXIT_CODE=0
python3 "$DETACH_SCRIPT" is-enabled 2>/dev/null || EXIT_CODE=$?
assert_eq "is-enabled returns 1 when disabled" "1" "$EXIT_CODE"
cleanup

# ─── Test: is-enabled returns 1 without registry ───
echo "=== Test: is-enabled returns exit 1 without registry ==="
setup_test_repo
EXIT_CODE=0
python3 "$DETACH_SCRIPT" is-enabled 2>/dev/null || EXIT_CODE=$?
assert_eq "is-enabled returns 1 without registry" "1" "$EXIT_CODE"
cleanup

# ─── Test: is-enabled returns 1 when extension dir missing ───
echo "=== Test: is-enabled returns exit 1 when extension dir missing ==="
setup_test_repo
echo '{"extensions":{"spex-detach":{"enabled":true}}}' > .specify/extensions/.registry
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

# ─── verify / ensure ───

# write_config <yaml paths...>: custom exclude path list
write_config() {
  {
    echo "exclude:"
    echo "  paths:"
    for p in "$@"; do printf '    - "%s"\n' "$p"; done
  } > .specify/extensions/spex-detach/spex-detach-config.yml
}

echo "=== Test: verify with defaults all ignored ==="
setup_test_repo
python3 "$DETACH_SCRIPT" enable >/dev/null 2>&1
EXIT_CODE=0
STDERR=$(python3 "$DETACH_SCRIPT" verify 2>&1 >/dev/null) || EXIT_CODE=$?
RESULT=$(python3 "$DETACH_SCRIPT" verify 2>/dev/null || true)
assert_eq "verify exits 0" "0" "$EXIT_CODE"
assert_contains "active line" "Stealth mode: active (verified: .specify/ specs/ brainstorm/)" "$STDERR"
assert_eq "active true" "true" "$(echo "$RESULT" | jq -r '.active')"
assert_eq "3 verified" "3" "$(echo "$RESULT" | jq -r '.verified | length')"
cleanup

echo "=== Test: verify reports a directory entry that is not excluded ==="
setup_test_repo
python3 "$DETACH_SCRIPT" enable >/dev/null 2>&1
sed -i.bak '/^specs\/$/d' .git/info/exclude && rm -f .git/info/exclude.bak
EXIT_CODE=0
STDERR=$(python3 "$DETACH_SCRIPT" verify 2>&1 >/dev/null) || EXIT_CODE=$?
RESULT=$(python3 "$DETACH_SCRIPT" verify 2>/dev/null || true)
assert_eq "verify exits 1" "1" "$EXIT_CODE"
assert_contains "warning line" "WARNING: stealth mode is NOT fully active" "$STDERR"
assert_contains "warning names specs/" "specs/ (not-ignored)" "$STDERR"
assert_not_contains "no active line" "Stealth mode: active" "$STDERR"
assert_eq "visible entry is specs/" "specs/" "$(echo "$RESULT" | jq -r '.visible[0].entry')"
assert_eq "probe under specs/" "specs/spex-detach-probe" "$(echo "$RESULT" | jq -r '.visible[0].probe')"
cleanup

echo "=== Test: verify reports a tracked path ==="
setup_test_repo
mkdir -p specs && echo "x" > specs/tracked.md
git add specs/tracked.md && git commit -q -m "tracked spec"
python3 "$DETACH_SCRIPT" enable >/dev/null 2>&1
EXIT_CODE=0
STDERR=$(python3 "$DETACH_SCRIPT" verify 2>&1 >/dev/null) || EXIT_CODE=$?
RESULT=$(python3 "$DETACH_SCRIPT" verify 2>/dev/null || true)
assert_eq "verify exits 1" "1" "$EXIT_CODE"
assert_contains "names specs/ as tracked" "specs/ (tracked)" "$STDERR"
assert_contains "history hint" "removed from history separately" "$STDERR"
assert_eq "reason tracked" "tracked" "$(echo "$RESULT" | jq -r '.visible[] | select(.entry == "specs/") | .reason')"
cleanup

echo "=== Test: re-include files are not listed as checked when their entry is already visible ==="
setup_test_repo
mkdir -p .specify/memory && echo "{}" > .specify/spex.json && echo "x" > .specify/memory/constitution.md
git add -f .specify/spex.json && git commit -q -m "tracked declaration"
python3 "$DETACH_SCRIPT" enable >/dev/null 2>&1
RESULT=$(python3 "$DETACH_SCRIPT" verify 2>/dev/null || true)
assert_eq ".specify/ visible as tracked" "tracked" "$(echo "$RESULT" | jq -r '.visible[] | select(.entry == ".specify/") | .reason')"
assert_eq "no re-include file claimed as checked" "0" "$(echo "$RESULT" | jq -r '.reinclude_checked | length')"
cleanup

echo "=== Test: verify reports tracked files under a **/-prefixed entry ==="
setup_test_repo
mkdir -p specs docs/notes && echo "x" > specs/a.md && echo "y" > docs/notes/CLAUDE.md
git add specs/a.md docs/notes/CLAUDE.md && git commit -q -m "tracked files"
write_config "**/specs/" "**/CLAUDE.md"
python3 "$DETACH_SCRIPT" enable >/dev/null 2>&1
EXIT_CODE=0
RESULT=$(python3 "$DETACH_SCRIPT" verify 2>/dev/null) || EXIT_CODE=$?
assert_eq "verify exits 1" "1" "$EXIT_CODE"
assert_eq "**/specs/ tracked" "tracked" "$(echo "$RESULT" | jq -r '.visible[] | select(.entry == "**/specs/") | .reason')"
assert_eq "**/CLAUDE.md tracked at depth" "tracked" "$(echo "$RESULT" | jq -r '.visible[] | select(.entry == "**/CLAUDE.md") | .reason')"
cleanup

echo "=== Test: a glob with a slash only counts tracked files it matches ==="
setup_test_repo
mkdir -p docs/a && echo "x" > docs/a/b.md
git add docs/a/b.md && git commit -q -m "nested doc"
write_config "docs/*.md"
python3 "$DETACH_SCRIPT" enable >/dev/null 2>&1
EXIT_CODE=0
RESULT=$(python3 "$DETACH_SCRIPT" verify 2>/dev/null) || EXIT_CODE=$?
assert_eq "verify exits 0 (docs/a/b.md is not covered)" "0" "$EXIT_CODE"
echo "y" > docs/top.md && git add -f docs/top.md && git commit -q -m "top doc"
RESULT=$(python3 "$DETACH_SCRIPT" verify 2>/dev/null || true)
assert_eq "docs/top.md makes the entry tracked" "tracked" "$(echo "$RESULT" | jq -r '.visible[0].reason')"
cleanup

echo "=== Test: verify probes file and glob entries, skips negations ==="
setup_test_repo
write_config "CLAUDE.md" "*.local.md" "!keep.md"
python3 "$DETACH_SCRIPT" enable >/dev/null 2>&1
EXIT_CODE=0
RESULT=$(python3 "$DETACH_SCRIPT" verify 2>/dev/null) || EXIT_CODE=$?
assert_eq "verify exits 0" "0" "$EXIT_CODE"
assert_eq "verified file and glob" "CLAUDE.md,*.local.md" "$(echo "$RESULT" | jq -r '.verified | join(",")')"
assert_eq "no re-include probes" "0" "$(echo "$RESULT" | jq -r '.reinclude_checked | length')"
# Remove the glob entry: its synthetic probe must now be visible.
grep -vxF '*.local.md' .git/info/exclude > .git/info/exclude.new && mv .git/info/exclude.new .git/info/exclude
RESULT=$(python3 "$DETACH_SCRIPT" verify 2>/dev/null || true)
assert_eq "glob probe name" "spex-probe.local.md" "$(echo "$RESULT" | jq -r '.visible[0].probe')"
grep -vxF 'CLAUDE.md' .git/info/exclude > .git/info/exclude.new && mv .git/info/exclude.new .git/info/exclude
RESULT=$(python3 "$DETACH_SCRIPT" verify 2>/dev/null || true)
assert_eq "file probe is the path" "CLAUDE.md" "$(echo "$RESULT" | jq -r '.visible[] | select(.entry == "CLAUDE.md") | .probe')"
cleanup

echo "=== Test: declaration and constitution ignored despite spex re-include rules ==="
setup_test_repo
mkdir -p .git/info
printf '%s\n' '# spex: generated/local files (only constitution is committed)' '**/.claude/' '**/.agents/' '**/.codex/' \
  '**/.specify/**' '!**/.specify/spex.json' '!**/.specify/memory/' '!**/.specify/memory/constitution.md' > .git/info/exclude
mkdir -p .specify/memory && echo '{}' > .specify/spex.json && echo "c" > .specify/memory/constitution.md
python3 "$DETACH_SCRIPT" enable >/dev/null 2>&1
EXIT_CODE=0
RESULT=$(python3 "$DETACH_SCRIPT" verify 2>/dev/null) || EXIT_CODE=$?
assert_eq "verify exits 0" "0" "$EXIT_CODE"
assert_eq "re-include files checked" ".specify/spex.json,.specify/memory/constitution.md" "$(echo "$RESULT" | jq -r '.reinclude_checked | join(",")')"
assert_eq "git ignores spex.json" "0" "$(git check-ignore -q .specify/spex.json; echo $?)"
assert_eq "git ignores constitution" "0" "$(git check-ignore -q .specify/memory/constitution.md; echo $?)"
cleanup

echo "=== Test: verify reports a re-included constitution ==="
setup_test_repo
write_config ".specify/**"
mkdir -p .git/info
printf '%s\n' '.specify/**' '!.specify/memory/' '!.specify/memory/constitution.md' > .git/info/exclude
EXIT_CODE=0
STDERR=$(python3 "$DETACH_SCRIPT" verify 2>&1 >/dev/null) || EXIT_CODE=$?
assert_eq "verify exits 1" "1" "$EXIT_CODE"
assert_contains "names the constitution" ".specify/memory/constitution.md (not-ignored, re-included under .specify/**)" "$STDERR"
cleanup

echo "=== Test: verify creates no files ==="
setup_test_repo
python3 "$DETACH_SCRIPT" enable >/dev/null 2>&1
BEFORE=$(git status --porcelain --ignored)
python3 "$DETACH_SCRIPT" verify >/dev/null 2>&1 || true
assert_eq "git status unchanged" "$BEFORE" "$(git status --porcelain --ignored)"
assert_eq "no probe file" "false" "$([ -e specs/spex-detach-probe ] && echo true || echo false)"
cleanup

echo "=== Test: ensure writes entries and verifies ==="
setup_test_repo
EXIT_CODE=0
STDERR=$(python3 "$DETACH_SCRIPT" ensure 2>&1 >/dev/null) || EXIT_CODE=$?
assert_eq "ensure exits 0" "0" "$EXIT_CODE"
assert_contains "written line" "Stealth mode: exclude entries written: .specify/ specs/ brainstorm/" "$STDERR"
assert_contains "active line" "Stealth mode: active" "$STDERR"
assert_not_contains "no repair line" "Repaired" "$STDERR"
cleanup

echo "=== Test: ensure --was-enabled repairs a missing entry, idempotent ==="
setup_test_repo
python3 "$DETACH_SCRIPT" ensure >/dev/null 2>&1
sed -i.bak '/^specs\/$/d' .git/info/exclude && rm -f .git/info/exclude.bak
STDERR=$(python3 "$DETACH_SCRIPT" ensure --was-enabled 2>&1 >/dev/null || true)
assert_contains "repair names specs/" "Repaired stealth mode: added specs/" "$STDERR"
assert_not_contains "repair names only specs/" "added specs/ " "$STDERR"
RESULT=""
STDERR=$(python3 "$DETACH_SCRIPT" ensure --was-enabled 2>&1 >/dev/null || true)
assert_not_contains "second ensure repairs nothing" "Repaired" "$STDERR"
assert_contains "second ensure still verifies" "Stealth mode: active" "$STDERR"
for e in .specify/ specs/ brainstorm/; do
  assert_eq "$e appears once" "1" "$(grep -cxF "$e" .git/info/exclude)"
done
RESULT=$(python3 "$DETACH_SCRIPT" ensure 2>/dev/null || true)
assert_eq "stdout has enable and verify" "true" "$(echo "$RESULT" | jq -r 'has("enable") and has("verify")')"
cleanup

echo "=== Test: ensure prints the tracked hint once ==="
setup_test_repo
mkdir -p specs && echo "x" > specs/tracked.md
git add specs/tracked.md && git commit -q -m "tracked spec"
EXIT_CODE=0
STDERR=$(python3 "$DETACH_SCRIPT" ensure 2>&1 >/dev/null) || EXIT_CODE=$?
assert_eq "ensure exits 1" "1" "$EXIT_CODE"
assert_eq "tracked hint once" "1" "$(printf '%s\n' "$STDERR" | grep -c "removed from history separately")"
assert_contains "warning names specs/" "specs/ (tracked)" "$STDERR"
cleanup

echo "=== Test: ensure outside a git repository is silent ==="
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
EXIT_CODE=0
STDERR=$(python3 "$DETACH_SCRIPT" ensure 2>&1 >/dev/null) || EXIT_CODE=$?
assert_eq "ensure exits 2" "2" "$EXIT_CODE"
assert_eq "empty stderr" "" "$STDERR"
assert_eq "nothing written" "" "$(ls -A "$TMPDIR")"
cleanup

echo "=== Test: invalid config falls back to defaults for ensure and verify ==="
setup_test_repo
printf 'exclude: [unclosed\n  paths: {\n' > .specify/extensions/spex-detach/spex-detach-config.yml
RESULT=$(python3 "$DETACH_SCRIPT" ensure 2>/dev/null || true)
assert_eq "written list is defaults" ".specify/,specs/,brainstorm/" "$(echo "$RESULT" | jq -r '.enable.paths_added | join(",")')"
assert_eq "verified list is defaults" ".specify/,specs/,brainstorm/" "$(echo "$RESULT" | jq -r '.verify.verified | join(",")')"
cleanup

echo "=== Test: invalid config warns that the defaults are used ==="
setup_test_repo
printf 'exclude: [unclosed\n  paths: {\n' > .specify/extensions/spex-detach/spex-detach-config.yml
STDERR=$(python3 "$DETACH_SCRIPT" ensure 2>&1 >/dev/null || true)
assert_contains "ensure names the unreadable config" "Stealth mode: cannot read .specify/extensions/spex-detach/spex-detach-config.yml" "$STDERR"
assert_eq "ensure warns once" "1" "$(printf '%s\n' "$STDERR" | grep -c "cannot read")"
STDERR=$(python3 "$DETACH_SCRIPT" verify 2>&1 >/dev/null || true)
assert_contains "verify names the unreadable config" "Stealth mode: cannot read" "$STDERR"
cleanup

echo "=== Test: a global dotfile ignore rule does not fake a verified directory ==="
setup_test_repo
printf '.*\n' > "$GIT_ISOLATION_HOME/dotfiles-ignore"
EXIT_CODE=0
STDERR=$(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.excludesFile GIT_CONFIG_VALUE_0="$GIT_ISOLATION_HOME/dotfiles-ignore" \
  python3 "$DETACH_SCRIPT" verify 2>&1 >/dev/null) || EXIT_CODE=$?
assert_eq "verify exits 1 without entries" "1" "$EXIT_CODE"
assert_contains "names specs/" "specs/ (not-ignored)" "$STDERR"
assert_not_contains "no active line" "Stealth mode: active" "$STDERR"
cleanup

echo "=== Test: glob probes satisfy negated, ranged and POSIX bracket classes ==="
setup_test_repo
printf 'exclude:\n  paths:\n    - "[!a-z].md"\n    - "x[!xyzq0]"\n    - "docs/[[:alpha:]]x"\n    - "notes/[^0-9]*.txt"\n    - "p[[:punct:]z]"\n    - "g[![:graph:]]q"\n    - "notes/[.]draft"\n    - "notes/[]]draft"\n' \
  > .specify/extensions/spex-detach/spex-detach-config.yml
EXIT_CODE=0
STDERR=$(python3 "$DETACH_SCRIPT" ensure 2>&1 >/dev/null) || EXIT_CODE=$?
if command -v yq >/dev/null 2>&1; then
  assert_eq "ensure exits 0" "0" "$EXIT_CODE"
  assert_contains "all globs verified" 'Stealth mode: active (verified: [!a-z].md x[!xyzq0] docs/[[:alpha:]]x notes/[^0-9]*.txt p[[:punct:]z] g[![:graph:]]q notes/[.]draft notes/[]]draft)' "$STDERR"
  assert_not_contains "no traceback" "Traceback" "$STDERR"
else
  echo "  SKIP: yq not installed"
fi
cleanup

echo "=== Test: ensure and verify from a linked worktree protect the main checkout ==="
setup_test_repo
MAIN="$PWD"
git worktree add -q "$TMPDIR/wt" -b wt-branch
cd "$TMPDIR/wt"
EXIT_CODE=0
STDERR=$(python3 "$DETACH_SCRIPT" ensure 2>&1 >/dev/null) || EXIT_CODE=$?
assert_eq "ensure from the worktree exits 0" "0" "$EXIT_CODE"
assert_contains "active from the worktree" "Stealth mode: active" "$STDERR"
for e in .specify/ specs/ brainstorm/; do
  assert_eq "$e in the shared exclude file" "1" "$(grep -cxF "$e" "$MAIN/.git/info/exclude")"
done
assert_eq "no per-worktree exclude file" "false" "$([ -e "$MAIN/.git/worktrees/wt/info/exclude" ] && echo true || echo false)"
assert_eq "main checkout ignores specs/" "0" "$(git -C "$MAIN" check-ignore -q -- specs/x.md; echo $?)"
cd "$MAIN"
EXIT_CODE=0
python3 "$DETACH_SCRIPT" verify >/dev/null 2>&1 || EXIT_CODE=$?
assert_eq "verify in the main checkout exits 0" "0" "$EXIT_CODE"
cleanup

echo "=== Test: configured entries are normalized the same for enable, verify and disable ==="
setup_test_repo
if command -v yq >/dev/null 2>&1; then
  printf 'exclude:\n  paths:\n    - " specs/ "\n    - "# a comment"\n    - "specs/"\n    - "brainstorm/"\n' \
    > .specify/extensions/spex-detach/spex-detach-config.yml
  RESULT=$(python3 "$DETACH_SCRIPT" enable 2>/dev/null)
  assert_eq "written once, comment dropped" "specs/,brainstorm/" "$(echo "$RESULT" | jq -r '.paths_added | join(",")')"
  assert_eq "specs/ once in the file" "1" "$(grep -cxF "specs/" .git/info/exclude)"
  assert_eq "no comment entry written" "0" "$(grep -cxF "# a comment" .git/info/exclude || true)"
  RESULT=$(python3 "$DETACH_SCRIPT" verify 2>/dev/null || true)
  assert_eq "verify checks the same list" "specs/,brainstorm/" "$(echo "$RESULT" | jq -r '.verified | join(",")')"
  printf 'specs/   \n' > .git/info/exclude
  RESULT=$(python3 "$DETACH_SCRIPT" enable 2>/dev/null)
  assert_eq "trailing whitespace counts as present" "brainstorm/" "$(echo "$RESULT" | jq -r '.paths_added | join(",")')"
  python3 "$DETACH_SCRIPT" disable >/dev/null 2>&1
  assert_eq "disable removes the padded line" "0" "$(grep -c "specs/" .git/info/exclude || true)"
  printf ' specs/\n' > .git/info/exclude
  RESULT=$(python3 "$DETACH_SCRIPT" enable 2>/dev/null)
  assert_eq "leading whitespace is a different pattern" "specs/,brainstorm/" "$(echo "$RESULT" | jq -r '.paths_added | join(",")')"
  python3 "$DETACH_SCRIPT" disable >/dev/null 2>&1
  assert_eq "disable keeps the user's leading-space line" "1" "$(grep -cxF " specs/" .git/info/exclude)"
else
  echo "  SKIP: yq not installed"
fi
cleanup

echo "=== Test: enable warns only about tracked files at the configured root path ==="
setup_test_repo
mkdir -p sub/specs && echo x > sub/specs/f.md
git add sub/specs/f.md && git commit -q -m "nested specs"
RESULT=$(python3 "$DETACH_SCRIPT" enable 2>/dev/null)
assert_eq "no tracked warning for nested specs/" "null" "$(echo "$RESULT" | jq -r '.tracked_warning')"
mkdir -p specs && echo x > specs/f.md
git add -f specs/f.md && git commit -q -m "root specs"
RESULT=$(python3 "$DETACH_SCRIPT" enable 2>/dev/null)
assert_eq "tracked warning for root specs/" "specs" "$(echo "$RESULT" | jq -r '.tracked_warning | join(",")')"
cleanup

# ─── Summary ───
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
