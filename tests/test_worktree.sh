#!/usr/bin/env bash
# Tests for spex-worktree.sh (prepare, finalize, adopt).
#
# Every case builds a throwaway repository under a mktemp directory, so the
# real checkout is never touched. All git commands use `git -C <tmp-repo>`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WT_SCRIPT="$REPO_ROOT/spex/scripts/spex-worktree.sh"

# Keep the environment of the calling session (for example a ship pipeline)
# out of the fixtures.
unset SHIP_STATE_FILE GIT_BRANCH_NAME GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE SPECIFY_FEATURE || true

PASS=0
FAIL=0
TMPROOT=""
BGPID=""

cleanup() {
  if [ -n "$BGPID" ]; then
    kill "$BGPID" 2>/dev/null || true
    wait "$BGPID" 2>/dev/null || true
    BGPID=""
  fi
  if [ -n "$TMPROOT" ] && [ -d "$TMPROOT" ]; then
    rm -rf "$TMPROOT"
  fi
  TMPROOT=""
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected '$expected', got '$actual')"; FAIL=$((FAIL + 1))
  fi
}

assert_ne() {
  local desc="$1" unexpected="$2" actual="$3"
  if [ "$unexpected" != "$actual" ]; then
    echo "  PASS: $desc"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (did not expect '$actual')"; FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    echo "  PASS: $desc"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (missing '$needle' in output:"; printf '%s\n' "$haystack" | sed 's/^/      /'; echo "    )"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if ! printf '%s' "$haystack" | grep -qF -- "$needle"; then
    echo "  PASS: $desc"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (unexpected '$needle' in output)"; FAIL=$((FAIL + 1))
  fi
}

assert_file() {
  local desc="$1" path="$2"
  if [ -e "$path" ]; then
    echo "  PASS: $desc"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (missing: $path)"; FAIL=$((FAIL + 1))
  fi
}

assert_no_file() {
  local desc="$1" path="$2"
  if [ ! -e "$path" ]; then
    echo "  PASS: $desc"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (unexpected: $path)"; FAIL=$((FAIL + 1))
  fi
}

# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------

# make_repo: build a fresh temp repository and set REPO to its real path.
# The repo has a `main` branch with one commit, spex-worktrees and git enabled
# in the registry, git extension config (no scripts: prepare must never need
# them) and a .claude/ directory.
make_repo() {
  cleanup
  TMPROOT=$(cd "$(mktemp -d)" && pwd -P)
  REPO="$TMPROOT/proj"
  mkdir -p "$REPO"
  git -C "$REPO" init -q -b main
  git -C "$REPO" config user.name "Test"
  git -C "$REPO" config user.email "test@example.com"
  git -C "$REPO" config commit.gpgsign false
  # Keep the user's global ignore rules out of the fixture.
  git -C "$REPO" config core.excludesFile /dev/null

  cat > "$REPO/.gitignore" <<'EOF'
.claude/
.specify/
EOF
  echo "hello" > "$REPO/README.md"
  mkdir -p "$REPO/specs/001-first"
  echo "# first" > "$REPO/specs/001-first/spec.md"
  git -C "$REPO" add .gitignore README.md specs
  git -C "$REPO" commit -qm "initial"

  mkdir -p "$REPO/.specify/extensions/spex-worktrees" \
           "$REPO/.specify/extensions/git" \
           "$REPO/.specify/memory" \
           "$REPO/.claude"
  cat > "$REPO/.specify/extensions/.registry" <<'EOF'
{
  "schema_version": "1.0",
  "extensions": {
    "git": {"enabled": true, "priority": 10},
    "spex-worktrees": {"enabled": true, "priority": 10}
  }
}
EOF
  cat > "$REPO/.specify/extensions/spex-worktrees/worktree-config.yml" <<'EOF'
worktrees:
  base_path: ".claude/worktrees"
EOF
  echo "# constitution" > "$REPO/.specify/memory/constitution.md"
  echo '{"feature_directory": "specs/001-first"}' > "$REPO/.specify/feature.json"
  printf 'branch_numbering: sequential\n' > "$REPO/.specify/extensions/git/git-config.yml"
  echo '{"permissions": {}}' > "$REPO/.claude/settings.json"
}

# Run the script under test from a directory. Sets OUT (stdout+stderr) and RC.
run_wt() {
  local dir="$1"; shift
  RC=0
  OUT=$(cd "$dir" && bash "$WT_SCRIPT" "$@" 2>&1) || RC=$?
}

# First stdout line of the last run.
status_line() {
  printf '%s\n' "$OUT" | grep -E '^WORKTREE_[A-Z]+' | head -1
}

# Value of key=<value> on the status line.
status_field() {
  status_line | tr ' ' '\n' | sed -n "s/^$1=//p"
}

# Last line of the last run.
last_line() {
  printf '%s\n' "$OUT" | tail -1
}

main_head() {
  git -C "${1:-$REPO}" symbolic-ref -q --short HEAD 2>/dev/null || echo "DETACHED@$(git -C "${1:-$REPO}" rev-parse HEAD)"
}

main_reflog_top() {
  git -C "${1:-$REPO}" reflog -1 --format='%H %gs' HEAD 2>/dev/null || true
}

main_status() {
  git -C "${1:-$REPO}" status --porcelain
}

wt_head() {
  git -C "$1" symbolic-ref -q --short HEAD 2>/dev/null || echo "DETACHED"
}

flow_state() {
  # flow_state <dir> <branch> [<running>]
  # Without <running>, the file has the shape of `spex-flow-state.sh create`.
  mkdir -p "$1/.specify"
  jq -n --arg b "$2" --arg r "${3:-}" \
    '{mode: "flow", started_at: "2026-10-16T00:00:00Z", feature_branch: $b, spec_dir: ("specs/" + $b), implemented: false, clarified: false}
     + (if $r == "" then {} else {running: $r} end)' \
    > "$1/.specify/.spex-state"
}

# Number of worktrees registered in the repo.
wt_count() {
  git -C "$REPO" worktree list --porcelain | grep -c '^worktree '
}

branch_exists() {
  git -C "$REPO" show-ref --verify --quiet "refs/heads/$1"
}

# simulate_git_feature <dir> <short> [<prefix>]: what speckit.git.feature
# does in <dir>: create and check out `<prefix>-<short>` (prefix 057 by
# default). Only used to stand in for the git extension after prepare;
# prepare itself never runs anything of the git extension.
simulate_git_feature() {
  local dir="$1" short="$2" prefix="${3:-057}"
  git -C "$dir" checkout -q -b "$prefix-$short"
}

# Provisional worktree path pattern for a short name (inside the project).
pending_glob() {
  printf '%s\n' "$REPO/.claude/worktrees/.pending-$1-"
}

# True when <path> is `<prefix><6 hex>`.
is_pending_for() {
  local path="$1" prefix="$2" rest
  case "$path" in
    "$prefix"*) rest="${path#"$prefix"}" ;;
    *) return 1 ;;
  esac
  [[ "$rest" =~ ^[0-9a-f]{6}$ ]]
}

# Number of local branches.
branch_count() {
  git -C "$REPO" for-each-ref refs/heads | wc -l | tr -d ' '
}

# Content of the prepared marker of a worktree.
prepared_marker() {
  cat "$(git -C "$1" rev-parse --absolute-git-dir)/spex-prepared" 2>/dev/null || echo "NO-MARKER"
}

# Commit something on main so the default tip differs from older commits.
second_commit() {
  echo "two" > "$REPO/two.txt"
  git -C "$REPO" add two.txt
  git -C "$REPO" commit -qm "second"
}

ship_state() {
  # ship_state <dir> <stage>
  mkdir -p "$1/.specify"
  jq -n --arg s "$2" \
    '{mode: "ship", stage: $s, stage_index: 0, total_stages: 8, ask: "smart", status: "running", feature_branch: ""}' \
    > "$1/.specify/.spex-state"
}

# ===========================================================================
# Test cases: prepare
# ===========================================================================

echo "Test: prepare early mode from a clean main"
make_repo
HEAD_BEFORE=$(main_head); REFLOG_BEFORE=$(main_reflog_top); STATUS_BEFORE=$(main_status)
MAIN_TIP=$(git -C "$REPO" rev-parse main)
START=$SECONDS
run_wt "$REPO" prepare --short-name x --description "Add x"
ELAPSED=$((SECONDS - START))
WT=$(status_field path)
assert_eq "exit code" "0" "$RC"
assert_eq "provisional path .pending-x-<6 hex>" "yes" "$(is_pending_for "$WT" "$(pending_glob x)" && echo yes || echo no)"
assert_eq "status line without branch" "WORKTREE_PREPARED path=$WT base=main mode=early" "$(status_line)"
assert_contains "says the name is provisional" "The directory name is provisional" "$OUT"
assert_contains "says finalize renames it" "finalize renames the directory after the branch" "$OUT"
assert_eq "last line is cd" "cd $WT" "$(last_line)"
assert_eq "main branch unchanged" "$HEAD_BEFORE" "$(main_head)"
assert_eq "main reflog unchanged" "$REFLOG_BEFORE" "$(main_reflog_top)"
assert_eq "main status unchanged" "$STATUS_BEFORE" "$(main_status)"
assert_eq "worktree detached" "DETACHED" "$(wt_head "$WT")"
assert_eq "worktree at main tip" "$MAIN_TIP" "$(git -C "$WT" rev-parse HEAD)"
assert_file "registry copied" "$WT/.specify/extensions/.registry"
assert_file "git extension config copied" "$WT/.specify/extensions/git/git-config.yml"
assert_file ".claude copied" "$WT/.claude/settings.json"
assert_no_file "no nested worktrees dir" "$WT/.claude/worktrees"
assert_no_file "no state in worktree" "$WT/.specify/.spex-state"
assert_eq "no branch created" "1" "$(branch_count)"
assert_eq "marker: branch unknown, short name recorded" "branch=
short_name=x" "$(prepared_marker "$WT")"
assert_not_contains "no NOTICE on default branch" "NOTICE" "$OUT"
if [ "$ELAPSED" -lt 5 ]; then
  echo "  PASS: prepare finished in under 5 seconds (${ELAPSED}s)"; PASS=$((PASS + 1))
else
  echo "  FAIL: prepare took ${ELAPSED}s (limit 5s)"; FAIL=$((FAIL + 1))
fi

echo "Test: prepare normalizes the short name for the provisional path"
make_repo
run_wt "$REPO" prepare --short-name 'User Auth!'
WT=$(status_field path)
assert_eq "exit code" "0" "$RC"
assert_eq "normalized provisional name" "yes" "$(is_pending_for "$WT" "$(pending_glob user-auth)" && echo yes || echo no)"
assert_contains "marker records the normalized short name" "short_name=user-auth" "$(prepared_marker "$WT")"

echo "Test: two prepares with the same short name get different provisional paths"
make_repo
run_wt "$REPO" prepare --short-name x
WT1=$(status_field path)
run_wt "$REPO" prepare --short-name x
WT2=$(status_field path)
assert_eq "second prepare exit code" "0" "$RC"
assert_ne "different paths" "$WT1" "$WT2"
assert_eq "three worktrees" "3" "$(wt_count)"

echo "Test: prepare without --short-name and --branch is a usage error"
make_repo
run_wt "$REPO" prepare --short-name '!!!'
assert_eq "exit code" "2" "$RC"
assert_eq "only the main worktree" "1" "$(wt_count)"

echo "Test: prepare works without any git extension script or directory"
make_repo
rm -rf "$REPO/.specify/extensions/git"
run_wt "$REPO" prepare --short-name x
WT=$(status_field path)
assert_eq "exit code" "0" "$RC"
assert_eq "status PREPARED" "WORKTREE_PREPARED" "$(status_line | cut -d' ' -f1)"
assert_eq "worktree detached" "DETACHED" "$(wt_head "$WT")"

echo "Test: prepare never runs a script of the git extension"
make_repo
mkdir -p "$REPO/.specify/extensions/git/scripts/bash"
for s in create-new-feature-branch.sh create-new-feature.sh; do
  printf '#!/bin/sh\necho "%s $*" >> "%s/git-script-ran"\nexit 1\n' "$s" "$TMPROOT" > "$REPO/.specify/extensions/git/scripts/bash/$s"
  chmod +x "$REPO/.specify/extensions/git/scripts/bash/$s"
done
run_wt "$REPO" prepare --short-name x --description "Add x"
assert_eq "exit code" "0" "$RC"
assert_no_file "no git extension script was invoked" "$TMPROOT/git-script-ran"

echo "Test: prepare with uncommitted changes in main"
make_repo
echo "changed" >> "$REPO/README.md"
echo "scratch" > "$REPO/notes.txt"
git -C "$REPO" add notes.txt
echo "untracked" > "$REPO/untracked.txt"
STATUS_BEFORE=$(main_status); REFLOG_BEFORE=$(main_reflog_top)
run_wt "$REPO" prepare --short-name x --description "Add x"
WT=$(status_field path)
assert_eq "exit code" "0" "$RC"
assert_eq "main status unchanged" "$STATUS_BEFORE" "$(main_status)"
assert_eq "main reflog unchanged" "$REFLOG_BEFORE" "$(main_reflog_top)"
assert_eq "worktree README is clean" "hello" "$(cat "$WT/README.md")"
assert_no_file "staged file absent from worktree" "$WT/notes.txt"
assert_no_file "untracked file absent from worktree" "$WT/untracked.txt"
assert_eq "worktree clean" "" "$(git -C "$WT" status --porcelain)"

echo "Test: prepare while main is on another branch"
make_repo
git -C "$REPO" checkout -q -b other
echo "other" > "$REPO/other.txt"; git -C "$REPO" add other.txt; git -C "$REPO" commit -qm "other"
MAIN_TIP=$(git -C "$REPO" rev-parse main)
REFLOG_BEFORE=$(main_reflog_top)
run_wt "$REPO" prepare --short-name x --description "Add x"
WT=$(status_field path)
assert_eq "exit code" "0" "$RC"
assert_eq "mode early" "early" "$(status_field mode)"
assert_contains "FR-017 notice" "NOTICE: main checkout is on 'other', new branch starts from 'main'" "$OUT"
assert_eq "worktree at main tip" "$MAIN_TIP" "$(git -C "$WT" rev-parse HEAD)"
assert_eq "main stays on other" "other" "$(main_head)"
assert_eq "main reflog unchanged" "$REFLOG_BEFORE" "$(main_reflog_top)"

echo "Test: prepare while main is detached"
make_repo
second_commit
git -C "$REPO" checkout -q --detach HEAD~1
DETACHED_AT=$(main_head)
MAIN_TIP=$(git -C "$REPO" rev-parse main)
run_wt "$REPO" prepare --short-name x --description "Add x"
WT=$(status_field path)
assert_eq "exit code" "0" "$RC"
assert_contains "FR-017 notice" "NOTICE: main checkout is on 'detached HEAD at" "$OUT"
assert_eq "worktree at main tip" "$MAIN_TIP" "$(git -C "$WT" rev-parse HEAD)"
assert_eq "main stays detached" "$DETACHED_AT" "$(main_head)"

echo "Test: prepare late mode after git.feature ran in main"
make_repo
flow_state "$REPO" "057-x"
echo "changed" >> "$REPO/README.md"
echo "scratch" > "$REPO/notes.txt"; git -C "$REPO" add notes.txt
echo "untracked" > "$REPO/untracked.txt"
STATUS_BEFORE=$(main_status)
git -C "$REPO" checkout -q -b 057-x
run_wt "$REPO" prepare --short-name x --description "Add x"
WT="$REPO/.claude/worktrees/057-x"
assert_eq "exit code" "0" "$RC"
assert_eq "status line" "WORKTREE_PREPARED path=$WT branch=057-x base=main mode=late" "$(status_line)"
assert_contains "hook order notice" "NOTICE: hook order: git.feature ran before the worktree step; main checkout was restored to 'main'" "$OUT"
assert_eq "main back on main" "main" "$(main_head)"
assert_eq "worktree on feature branch" "057-x" "$(wt_head "$WT")"
assert_eq "last line is cd" "cd $WT" "$(last_line)"
assert_file "flow create state moved into worktree" "$WT/.specify/.spex-state"
assert_no_file "main has no state" "$REPO/.specify/.spex-state"
assert_eq "uncommitted changes kept in main" "$STATUS_BEFORE" "$(main_status)"
assert_eq "restore is the last main reflog entry" "checkout: moving from 057-x to main" "$(git -C "$REPO" reflog -1 --format=%gs HEAD)"
assert_eq "worktree README is clean" "hello" "$(cat "$WT/README.md")"
assert_eq "marker records the branch" "branch=057-x
short_name=x" "$(prepared_marker "$WT")"

echo "Test: prepare late mode while main was on another branch"
make_repo
git -C "$REPO" checkout -q -b other
echo "other" > "$REPO/other.txt"; git -C "$REPO" add other.txt; git -C "$REPO" commit -qm "other"
MAIN_TIP=$(git -C "$REPO" rev-parse main)
git -C "$REPO" checkout -q -b 057-x
run_wt "$REPO" prepare --short-name x --description "Add x"
WT="$REPO/.claude/worktrees/057-x"
assert_eq "exit code" "0" "$RC"
assert_eq "mode late" "late" "$(status_field mode)"
assert_eq "main back on other" "other" "$(main_head)"
assert_contains "FR-017 notice" "NOTICE: main checkout is on 'other', new branch starts from 'main'" "$OUT"
assert_eq "branch reset to main tip" "$MAIN_TIP" "$(git -C "$REPO" rev-parse 057-x)"
assert_eq "worktree on feature branch" "057-x" "$(wt_head "$WT")"
assert_no_file "other's file absent from worktree" "$WT/other.txt"

echo "Test: prepare while main is on an old-flow feature branch"
make_repo
git -C "$REPO" checkout -q -b 055-foo
mkdir -p "$REPO/specs/055-foo"; echo "# foo" > "$REPO/specs/055-foo/spec.md"
STATUS_BEFORE=$(main_status)
MAIN_TIP=$(git -C "$REPO" rev-parse main)
run_wt "$REPO" prepare --short-name x --description "Add x"
WT=$(status_field path)
assert_eq "exit code" "0" "$RC"
assert_eq "status line" "WORKTREE_PREPARED path=$WT base=main mode=early" "$(status_line)"
assert_contains "FR-017 notice" "NOTICE: main checkout is on '055-foo', new branch starts from 'main'" "$OUT"
assert_eq "worktree at main tip" "$MAIN_TIP" "$(git -C "$WT" rev-parse HEAD)"
assert_eq "main stays on 055-foo" "055-foo" "$(main_head)"
assert_eq "uncommitted spec untouched" "$STATUS_BEFORE" "$(main_status)"
assert_file "old spec still in main" "$REPO/specs/055-foo/spec.md"

echo "Test: prepare late-mode failure with the target path present"
make_repo
mkdir -p "$REPO/.claude/worktrees/057-x"; echo "x" > "$REPO/.claude/worktrees/057-x/keep.txt"
git -C "$REPO" checkout -q -b 057-x
run_wt "$REPO" prepare --short-name x --description "Add x"
assert_eq "exit code" "1" "$RC"
assert_contains "error reported" "ERROR:" "$OUT"
assert_eq "main on previous ref" "main" "$(main_head)"
assert_eq "commit-less branch deleted" "no" "$(branch_exists 057-x && echo yes || echo no)"
assert_eq "only the main worktree" "1" "$(wt_count)"
assert_file "existing path untouched" "$REPO/.claude/worktrees/057-x/keep.txt"

echo "Test: prepare --branch naming an existing branch"
make_repo
git -C "$REPO" branch 057-dup
run_wt "$REPO" prepare --short-name dup --description "Dup" --branch 057-dup
assert_eq "exit code" "1" "$RC"
assert_contains "error names the branch" "ERROR: branch '057-dup' already exists" "$OUT"
assert_no_file "no worktree dir" "$REPO/.claude/worktrees/057-dup"
assert_eq "only the main worktree" "1" "$(wt_count)"

echo "Test: prepare --branch names the worktree after the branch"
make_repo
run_wt "$REPO" prepare --short-name x --branch 20261016-120000-x
WT="$REPO/.claude/worktrees/20261016-120000-x"
assert_eq "exit code" "0" "$RC"
assert_eq "status line with branch" "WORKTREE_PREPARED path=$WT branch=20261016-120000-x base=main mode=early" "$(status_line)"
assert_not_contains "no provisional wording" "provisional" "$OUT"
assert_eq "marker records the branch" "branch=20261016-120000-x
short_name=x" "$(prepared_marker "$WT")"
assert_eq "branch not created yet" "no" "$(branch_exists 20261016-120000-x && echo yes || echo no)"

echo "Test: prepare GIT_BRANCH_NAME override"
make_repo
RC=0; OUT=$(cd "$REPO" && GIT_BRANCH_NAME=057-custom bash "$WT_SCRIPT" prepare --short-name x --description "X" 2>&1) || RC=$?
assert_eq "exit code" "0" "$RC"
assert_eq "branch from env" "057-custom" "$(status_field branch)"
assert_eq "path from env" "$REPO/.claude/worktrees/057-custom" "$(status_field path)"

echo "Test: prepare inside a worktree on a non-feature branch"
make_repo
git -C "$REPO" worktree add -q -b scratch "$TMPROOT/wt-scratch"
COUNT_BEFORE=$(wt_count)
run_wt "$TMPROOT/wt-scratch" prepare --short-name x --description "Add x"
assert_eq "exit code" "0" "$RC"
assert_eq "status line" "WORKTREE_READY path=$TMPROOT/wt-scratch" "$(status_line)"
assert_contains "nesting warning" "WARNING: already inside a worktree, nesting is not supported; using the current worktree" "$OUT"
assert_eq "no worktree added" "$COUNT_BEFORE" "$(wt_count)"
assert_eq "no branch created" "no" "$(branch_exists 057-x && echo yes || echo no)"

echo "Test: prepare inside a worktree on a feature branch with its own commit"
make_repo
git -C "$REPO" worktree add -q -b 058-done "$TMPROOT/wt58"
echo "done" > "$TMPROOT/wt58/done.txt"; git -C "$TMPROOT/wt58" add done.txt; git -C "$TMPROOT/wt58" commit -qm "done"
run_wt "$TMPROOT/wt58" prepare --short-name x --description "Add x"
assert_eq "exit code" "0" "$RC"
assert_eq "status READY" "WORKTREE_READY" "$(status_line | cut -d' ' -f1)"
assert_contains "nesting warning" "WARNING: already inside a worktree" "$OUT"

echo "Test: prepare inside a freshly prepared detached worktree"
make_repo
run_wt "$REPO" prepare --short-name x --description "Add x"
WT=$(status_field path)
COUNT_BEFORE=$(wt_count)
run_wt "$WT" prepare --short-name x --description "Add x"
assert_eq "exit code" "0" "$RC"
assert_eq "status line" "WORKTREE_READY path=$WT" "$(status_line)"
assert_not_contains "no nesting warning" "WARNING" "$OUT"
assert_eq "no worktree added" "$COUNT_BEFORE" "$(wt_count)"

echo "Test: prepare inside a prepared worktree after git.feature ran in it"
make_repo
run_wt "$REPO" prepare --short-name x --description "Add x"
WT=$(status_field path)
simulate_git_feature "$WT" x
run_wt "$WT" prepare --short-name x --description "Add x"
assert_eq "exit code" "0" "$RC"
assert_eq "status line" "WORKTREE_READY path=$WT" "$(status_line)"
assert_not_contains "no nesting warning" "WARNING" "$OUT"
assert_eq "worktree still on feature branch" "057-x" "$(wt_head "$WT")"

echo "Test: prepare with the target path already present"
make_repo
mkdir -p "$REPO/.claude/worktrees/057-x"
HEAD_BEFORE=$(main_head); REFLOG_BEFORE=$(main_reflog_top); STATUS_BEFORE=$(main_status)
run_wt "$REPO" prepare --short-name x --branch 057-x
assert_eq "exit code" "1" "$RC"
assert_contains "error reported" "ERROR: target path already exists" "$OUT"
assert_eq "only the main worktree" "1" "$(wt_count)"
assert_eq "no branch created" "no" "$(branch_exists 057-x && echo yes || echo no)"
assert_eq "main branch unchanged" "$HEAD_BEFORE" "$(main_head)"
assert_eq "main reflog unchanged" "$REFLOG_BEFORE" "$(main_reflog_top)"
assert_eq "main status unchanged" "$STATUS_BEFORE" "$(main_status)"

echo "Test: prepare with no resolvable default branch"
make_repo
git -C "$REPO" branch -q -m main trunk
run_wt "$REPO" prepare --short-name x --description "Add x"
assert_eq "exit code" "1" "$RC"
assert_contains "error" "ERROR: cannot determine the default branch" "$OUT"
assert_contains "set-head hint" "git remote set-head origin --auto" "$OUT"
assert_eq "only the main worktree" "1" "$(wt_count)"

echo "Test: prepare with the extension disabled"
make_repo
jq '.extensions["spex-worktrees"].enabled = false' "$REPO/.specify/extensions/.registry" > "$TMPROOT/reg" && mv "$TMPROOT/reg" "$REPO/.specify/extensions/.registry"
run_wt "$REPO" prepare --short-name x --description "Add x"
assert_eq "exit code" "0" "$RC"
assert_eq "status SKIPPED" "WORKTREE_SKIPPED" "$(status_line | cut -d' ' -f1)"
assert_eq "only the main worktree" "1" "$(wt_count)"

echo "Test: prepare and finalize with an external base_path"
make_repo
mkdir -p "$TMPROOT/ext"
printf 'worktrees:\n  base_path: "../ext"\n' > "$REPO/.specify/extensions/spex-worktrees/worktree-config.yml"
run_wt "$REPO" prepare --short-name x --description "Add x"
WT=$(status_field path)
assert_eq "exit code" "0" "$RC"
assert_eq "external provisional path" "yes" "$(is_pending_for "$WT" "$TMPROOT/ext/proj@.pending-x-" && echo yes || echo no)"
assert_file "worktree exists" "$WT/README.md"
simulate_git_feature "$WT" x
mkdir -p "$WT/specs/057-x"; echo "# spec" > "$WT/specs/057-x/spec.md"
run_wt "$WT" finalize
assert_eq "finalize exit code" "0" "$RC"
assert_eq "renamed to <repo>@<branch>" "WORKTREE_FINALIZED path=$TMPROOT/ext/proj@057-x branch=057-x" "$(status_line)"
assert_eq "last line is cd to the new path" "cd $TMPROOT/ext/proj@057-x" "$(last_line)"
assert_no_file "provisional directory gone" "$WT"

echo "Test: prepare moves a flow state with running=specify"
make_repo
flow_state "$REPO" "" "specify"
run_wt "$REPO" prepare --short-name x --description "Add x"
WT=$(status_field path)
assert_eq "exit code" "0" "$RC"
assert_file "state moved into worktree" "$WT/.specify/.spex-state"
assert_no_file "main has no state" "$REPO/.specify/.spex-state"
assert_eq "state content kept" "specify" "$(jq -r .running "$WT/.specify/.spex-state")"

echo "Test: prepare moves a ship state with stage=specify"
make_repo
ship_state "$REPO" "specify"
run_wt "$REPO" prepare --short-name x --description "Add x"
WT=$(status_field path)
assert_eq "exit code" "0" "$RC"
assert_file "ship state moved into worktree" "$WT/.specify/.spex-state"
assert_no_file "main has no state" "$REPO/.specify/.spex-state"
assert_eq "ship state content kept" "ship specify running" "$(jq -r '"\(.mode) \(.stage) \(.status)"' "$WT/.specify/.spex-state")"

echo "Test: prepare leaves a ship state with stage=plan alone"
make_repo
ship_state "$REPO" "plan"
run_wt "$REPO" prepare --short-name x --description "Add x"
WT=$(status_field path)
assert_eq "exit code" "0" "$RC"
assert_file "main keeps its state" "$REPO/.specify/.spex-state"
assert_no_file "worktree has no state" "$WT/.specify/.spex-state"

echo "Test: prepare leaves an unrelated flow state alone"
make_repo
flow_state "$REPO" "042-old"
run_wt "$REPO" prepare --short-name x --description "Add x"
WT=$(status_field path)
assert_file "main keeps its state" "$REPO/.specify/.spex-state"
assert_no_file "worktree has no state" "$WT/.specify/.spex-state"

# ===========================================================================
# Test cases: finalize and adopt
# ===========================================================================

echo "Test: finalize renames the provisional worktree after the branch"
make_repo
flow_state "$REPO" "" "specify"
run_wt "$REPO" prepare --short-name x
PENDING=$(status_field path)
simulate_git_feature "$PENDING" x
mkdir -p "$PENDING/specs/057-x"; echo "# spec" > "$PENDING/specs/057-x/spec.md"
run_wt "$PENDING" finalize
WT="$REPO/.claude/worktrees/057-x"
assert_eq "exit code" "0" "$RC"
assert_eq "status line names the new path" "WORKTREE_FINALIZED path=$WT branch=057-x" "$(status_line)"
assert_contains "explains the rename" "Worktree renamed from the provisional .claude/worktrees/.pending-x-" "$OUT"
assert_eq "last line is cd to the new path" "cd $WT" "$(last_line)"
assert_no_file "provisional directory gone" "$PENDING"
assert_eq "worktree registered at new path" "057-x" "$(wt_head "$WT")"
assert_eq "two worktrees" "2" "$(wt_count)"
assert_file "spec moved along" "$WT/specs/057-x/spec.md"
assert_eq "state feature_branch" "057-x" "$(jq -r .feature_branch "$WT/.specify/.spex-state")"
assert_eq "marker finalized" "NO-MARKER" "$(prepared_marker "$WT")"
assert_file "finalized marker" "$(git -C "$WT" rev-parse --absolute-git-dir)/spex-finalized"
assert_eq "main untouched" "main" "$(main_head)"

echo "Test: finalize keeps an existing valid feature.json"
make_repo
run_wt "$REPO" prepare --short-name x --description "Add x"
PENDING=$(status_field path)
simulate_git_feature "$PENDING" x
mkdir -p "$PENDING/specs/057-custom"; echo "# spec" > "$PENDING/specs/057-custom/spec.md"
printf '{\n  "feature_directory": "specs/057-custom"\n}\n' > "$PENDING/.specify/feature.json"
FJ_BEFORE=$(cat "$PENDING/.specify/feature.json")
run_wt "$PENDING" finalize
WT="$REPO/.claude/worktrees/057-x"
assert_eq "exit code" "0" "$RC"
assert_eq "status line" "WORKTREE_FINALIZED path=$WT branch=057-x" "$(status_line)"
assert_eq "feature.json unchanged" "$FJ_BEFORE" "$(cat "$WT/.specify/feature.json")"
assert_eq "last line is cd" "cd $WT" "$(last_line)"

echo "Test: finalize with a timestamp-numbered spec directory"
make_repo
run_wt "$REPO" prepare --short-name ts --description "TS" --branch 20261016-120000-ts
WT="$REPO/.claude/worktrees/20261016-120000-ts"
assert_eq "prepare exit code" "0" "$RC"
git -C "$WT" checkout -q -b 20261016-120000-ts
touch -t 202001010000 "$WT/specs/001-first/spec.md"
mkdir -p "$WT/specs/20261016-120000-other"; echo "# ts" > "$WT/specs/20261016-120000-other/spec.md"
rm -f "$WT/.specify/feature.json"
run_wt "$WT" finalize
assert_eq "exit code" "0" "$RC"
assert_eq "feature.json resolved" "specs/20261016-120000-other" "$(jq -r .feature_directory "$WT/.specify/feature.json")"

echo "Test: finalize with a matching spec directory, run twice"
make_repo
run_wt "$REPO" prepare --short-name x --description "Add x"
PENDING=$(status_field path)
simulate_git_feature "$PENDING" x
mkdir -p "$PENDING/specs/057-x"; echo "# spec" > "$PENDING/specs/057-x/spec.md"
rm -f "$PENDING/.specify/feature.json"
flow_state "$PENDING" "" "specify"
run_wt "$PENDING" finalize
WT="$REPO/.claude/worktrees/057-x"
assert_eq "exit code" "0" "$RC"
assert_eq "feature.json set" "specs/057-x" "$(jq -r .feature_directory "$WT/.specify/feature.json")"
assert_eq "state feature_branch" "057-x" "$(jq -r .feature_branch "$WT/.specify/.spex-state")"
assert_eq "state spec_dir" "specs/057-x" "$(jq -r .spec_dir "$WT/.specify/.spex-state")"
assert_eq "main untouched" "main" "$(main_head)"
COUNT_BEFORE=$(wt_count); WT_HEAD_BEFORE=$(git -C "$WT" rev-parse HEAD); WT_STATUS_BEFORE=$(git -C "$WT" status --porcelain)
REFLOG_BEFORE=$(main_reflog_top); FJ_BEFORE=$(cat "$WT/.specify/feature.json"); ST_BEFORE=$(cat "$WT/.specify/.spex-state")
FIRST_STATUS=$(status_line)
run_wt "$WT" finalize
assert_eq "second finalize exit code" "0" "$RC"
assert_eq "second finalize same status" "$FIRST_STATUS" "$(status_line)"
assert_not_contains "second finalize moves nothing" "renamed" "$OUT"
assert_eq "no worktree added" "$COUNT_BEFORE" "$(wt_count)"
assert_eq "no commit in worktree" "$WT_HEAD_BEFORE" "$(git -C "$WT" rev-parse HEAD)"
assert_eq "worktree branch unchanged" "057-x" "$(wt_head "$WT")"
assert_eq "worktree status unchanged" "$WT_STATUS_BEFORE" "$(git -C "$WT" status --porcelain)"
assert_eq "main reflog unchanged" "$REFLOG_BEFORE" "$(main_reflog_top)"
assert_eq "feature.json unchanged" "$FJ_BEFORE" "$(cat "$WT/.specify/feature.json")"
assert_eq "state unchanged" "$ST_BEFORE" "$(cat "$WT/.specify/.spex-state")"

echo "Test: finalize moves a --branch worktree when git.feature used another name"
make_repo
run_wt "$REPO" prepare --short-name x --branch 057-x
OLD_WT="$REPO/.claude/worktrees/057-x"
simulate_git_feature "$OLD_WT" y
mkdir -p "$OLD_WT/specs/057-y"; echo "# spec" > "$OLD_WT/specs/057-y/spec.md"
run_wt "$OLD_WT" finalize
NEW_WT="$REPO/.claude/worktrees/057-y"
assert_eq "exit code" "0" "$RC"
assert_eq "status line" "WORKTREE_FINALIZED path=$NEW_WT branch=057-y" "$(status_line)"
assert_contains "explains the move" "Worktree moved from .claude/worktrees/057-x to .claude/worktrees/057-y" "$OUT"
assert_eq "last line is cd to new path" "cd $NEW_WT" "$(last_line)"
assert_no_file "old directory gone" "$OLD_WT"
assert_eq "worktree registered at new path" "057-y" "$(wt_head "$NEW_WT")"

echo "Test: finalize in a prepared worktree without a branch changes nothing"
make_repo
ship_state "$REPO" "specify"
run_wt "$REPO" prepare --short-name x
WT=$(status_field path)
COUNT_BEFORE=$(wt_count); MARKER_BEFORE=$(prepared_marker "$WT"); ST_BEFORE=$(cat "$WT/.specify/.spex-state")
run_wt "$WT" finalize
assert_eq "exit code" "0" "$RC"
assert_eq "status line" "WORKTREE_SKIPPED reason=branch-not-created" "$(status_line)"
assert_contains "explains git.feature" "no feature branch was created in it" "$OUT"
assert_contains "guidance to run git.feature" "Run speckit.git.feature inside $WT" "$OUT"
assert_not_contains "no cd line" "cd $WT" "$(last_line)"
assert_file "worktree kept at the provisional path" "$WT/README.md"
assert_eq "still detached" "DETACHED" "$(wt_head "$WT")"
assert_eq "marker unchanged" "$MARKER_BEFORE" "$(prepared_marker "$WT")"
assert_eq "state unchanged" "$ST_BEFORE" "$(cat "$WT/.specify/.spex-state")"
assert_eq "no worktree added or removed" "$COUNT_BEFORE" "$(wt_count)"
assert_eq "no branch created" "1" "$(branch_count)"

echo "Test: finalize never deletes an existing target path"
make_repo
run_wt "$REPO" prepare --short-name x
PENDING=$(status_field path)
mkdir -p "$REPO/.claude/worktrees/057-x"; echo "mine" > "$REPO/.claude/worktrees/057-x/keep.txt"
simulate_git_feature "$PENDING" x
mkdir -p "$PENDING/specs/057-x"; echo "# spec" > "$PENDING/specs/057-x/spec.md"
run_wt "$PENDING" finalize
assert_eq "exit code" "0" "$RC"
assert_eq "status keeps the provisional path" "WORKTREE_FINALIZED path=$PENDING branch=057-x" "$(status_line)"
assert_contains "warns about the existing path" "WARNING: cannot move the worktree to $REPO/.claude/worktrees/057-x (path exists)" "$OUT"
assert_contains "warns about the provisional name" "still has its provisional name" "$OUT"
assert_eq "last line is cd to the provisional path" "cd $PENDING" "$(last_line)"
assert_eq "existing path untouched" "mine" "$(cat "$REPO/.claude/worktrees/057-x/keep.txt")"
assert_eq "existing path holds nothing else" "keep.txt" "$(ls "$REPO/.claude/worktrees/057-x")"
assert_file "worktree kept" "$PENDING/specs/057-x/spec.md"
rm -rf "$REPO/.claude/worktrees/057-x"
run_wt "$PENDING" finalize
assert_eq "second finalize renames once the path is free" "WORKTREE_FINALIZED path=$REPO/.claude/worktrees/057-x branch=057-x" "$(status_line)"
assert_no_file "provisional directory gone" "$PENDING"

echo "Test: finalize in main on a feature branch delegates to adopt"
make_repo
git -C "$REPO" checkout -q -b 057-z
mkdir -p "$REPO/specs/057-z"; echo "# z" > "$REPO/specs/057-z/spec.md"
echo '{"feature_directory": "specs/057-z"}' > "$REPO/.specify/feature.json"
run_wt "$REPO" finalize
WT="$REPO/.claude/worktrees/057-z"
assert_eq "exit code" "0" "$RC"
assert_eq "status line" "WORKTREE_ADOPTED path=$WT branch=057-z" "$(status_line)"
assert_eq "main back on main" "main" "$(main_head)"
assert_eq "worktree on feature branch" "057-z" "$(wt_head "$WT")"
assert_file "spec in worktree" "$WT/specs/057-z/spec.md"

echo "Test: finalize in main never adopts while a prepared worktree exists"
make_repo
git -C "$REPO" checkout -q -b 055-foo
mkdir -p "$REPO/specs/055-foo"; echo "# foo" > "$REPO/specs/055-foo/spec.md"
run_wt "$REPO" prepare --short-name x --description "Add x"
WT=$(status_field path)
simulate_git_feature "$WT" x
STATUS_BEFORE=$(main_status)
run_wt "$REPO" finalize
assert_eq "exit code" "0" "$RC"
assert_eq "status line" "WORKTREE_SKIPPED reason=prepared-worktree-exists" "$(status_line)"
assert_contains "names the prepared worktree" "$WT" "$OUT"
assert_eq "main stays on 055-foo" "055-foo" "$(main_head)"
assert_eq "main status unchanged" "$STATUS_BEFORE" "$(main_status)"
assert_eq "055-foo has no new commit" "0" "$(git -C "$REPO" rev-list --count main..055-foo)"

echo "Test: adopt resets a tracked feature.json pointer in main"
make_repo
git -C "$REPO" checkout -q -b 057-t
mkdir -p "$REPO/specs/057-t"; echo "# t" > "$REPO/specs/057-t/spec.md"
# Track feature.json (some projects do) on main first.
git -C "$REPO" checkout -q main
git -C "$REPO" add -f .specify/feature.json
git -C "$REPO" commit -qm "track feature.json"
git -C "$REPO" branch -q -f 057-t main
git -C "$REPO" checkout -q 057-t
echo '{"feature_directory": "specs/057-t"}' > "$REPO/.specify/feature.json"
run_wt "$REPO" adopt
WT="$REPO/.claude/worktrees/057-t"
assert_eq "exit code" "0" "$RC"
assert_eq "main back on main" "main" "$(main_head)"
assert_eq "tracked feature.json clean in main" "" "$(git -C "$REPO" status --porcelain -- .specify/feature.json)"
assert_eq "feature.json in worktree" "specs/057-t" "$(jq -r .feature_directory "$WT/.specify/feature.json")"

echo "Test: finalize in main on the default branch is skipped"
make_repo
run_wt "$REPO" finalize
assert_eq "exit code" "0" "$RC"
assert_eq "status SKIPPED" "WORKTREE_SKIPPED" "$(status_line | cut -d' ' -f1)"

echo "Test: adopt commits only the spec directory"
make_repo
git -C "$REPO" checkout -q -b 057-a
mkdir -p "$REPO/specs/057-a"; echo "# a" > "$REPO/specs/057-a/spec.md"
echo '{"feature_directory": "specs/057-a"}' > "$REPO/.specify/feature.json"
echo "local edit" >> "$REPO/README.md"
mkdir -p "$REPO/brainstorm"; echo "idea" > "$REPO/brainstorm/01-idea.md"
echo "staged" > "$REPO/staged.txt"; git -C "$REPO" add staged.txt
flow_state "$REPO" "057-a"
run_wt "$REPO" adopt
WT="$REPO/.claude/worktrees/057-a"
assert_eq "exit code" "0" "$RC"
assert_eq "status line" "WORKTREE_CREATED path=$WT branch=057-a" "$(status_line)"
assert_eq "last line is cd" "cd $WT" "$(last_line)"
assert_eq "commit holds only the spec dir" "specs/057-a/spec.md" "$(git -C "$REPO" show --name-only --format= 057-a)"
assert_eq "main back on main" "main" "$(main_head)"
assert_contains "tracked change still uncommitted in main" " M README.md" "$(main_status)"
assert_contains "staged file still staged in main" "A  staged.txt" "$(main_status)"
assert_contains "brainstorm still untracked in main" "?? brainstorm/" "$(main_status)"
assert_eq "worktree README clean" "hello" "$(cat "$WT/README.md")"
assert_eq "feature.json in worktree" "specs/057-a" "$(jq -r .feature_directory "$WT/.specify/feature.json")"
assert_file "state moved to worktree" "$WT/.specify/.spex-state"
assert_no_file "main has no state" "$REPO/.specify/.spex-state"

# ===========================================================================
# Test cases: review fixes (late-mode safety, rollback, markers, paths)
# ===========================================================================

echo "Test: late-mode failure never removes an existing worktree at the target path"
make_repo
mkdir -p "$REPO/.claude/worktrees"
git -C "$REPO" worktree add -q --detach "$REPO/.claude/worktrees/057-x" main
echo "work" > "$REPO/.claude/worktrees/057-x/userwork.txt"
git -C "$REPO" checkout -q -b 057-x
run_wt "$REPO" prepare --short-name x
assert_eq "exit code" "1" "$RC"
assert_contains "error reported" "ERROR: target path already exists" "$OUT"
assert_file "existing worktree kept" "$REPO/.claude/worktrees/057-x/userwork.txt"
assert_eq "existing worktree still registered" "2" "$(wt_count)"
assert_eq "main on previous ref" "main" "$(main_head)"
assert_eq "commit-less branch deleted" "no" "$(branch_exists 057-x && echo yes || echo no)"

echo "Test: prepare leaves a stale commit-less feature branch in main alone"
make_repo
GIT_COMMITTER_DATE="2020-01-01T00:00:00Z" git -C "$REPO" checkout -q -b 057-old
OLD_TIP=$(git -C "$REPO" rev-parse 057-old)
run_wt "$REPO" prepare --short-name x
assert_eq "exit code" "0" "$RC"
assert_eq "mode early" "early" "$(status_field mode)"
assert_eq "no branch on the status line" "" "$(status_field branch)"
assert_eq "provisional path" "yes" "$(is_pending_for "$(status_field path)" "$(pending_glob x)" && echo yes || echo no)"
assert_eq "main stays on 057-old" "057-old" "$(main_head)"
assert_eq "057-old untouched" "$OLD_TIP" "$(git -C "$REPO" rev-parse 057-old)"
assert_contains "FR-017 notice" "NOTICE: main checkout is on '057-old'" "$OUT"

echo "Test: prepare refuses a fresh feature branch in main that belongs to another run"
make_repo
git -C "$REPO" checkout -q -b 057-other
REFLOG_BEFORE=$(main_reflog_top)
run_wt "$REPO" prepare --short-name x
assert_eq "exit code" "1" "$RC"
assert_contains "error names the branch" "ERROR: the main checkout is on '057-other'" "$OUT"
assert_eq "main stays on 057-other" "057-other" "$(main_head)"
assert_eq "main reflog unchanged" "$REFLOG_BEFORE" "$(main_reflog_top)"
assert_eq "057-other kept" "yes" "$(branch_exists 057-other && echo yes || echo no)"
assert_eq "only the main worktree" "1" "$(wt_count)"

echo "Test: prepare with --branch refuses a different fresh feature branch in main"
make_repo
git -C "$REPO" checkout -q -b 057-x
run_wt "$REPO" prepare --short-name x --branch 057-y
assert_eq "exit code" "1" "$RC"
assert_eq "main stays on 057-x" "057-x" "$(main_head)"
assert_eq "057-x kept" "yes" "$(branch_exists 057-x && echo yes || echo no)"

echo "Test: prepare never rewinds or deletes a fresh feature branch with commits"
make_repo
git -C "$REPO" checkout -q -b 057-x
echo "c" > "$REPO/c.txt"; git -C "$REPO" add c.txt; git -C "$REPO" commit -qm "foreign commit"
TIP=$(git -C "$REPO" rev-parse 057-x)
run_wt "$REPO" prepare --short-name x
assert_eq "exit code" "1" "$RC"
assert_contains "error explains the commits" "already has commits of its own" "$OUT"
assert_eq "branch tip unchanged" "$TIP" "$(git -C "$REPO" rev-parse 057-x)"
assert_eq "main stays on 057-x" "057-x" "$(main_head)"
assert_eq "only the main worktree" "1" "$(wt_count)"

echo "Test: early-mode rollback when copying the configuration fails"
make_repo
mkdir -p "$TMPROOT/bin"; printf '#!/bin/sh\nexit 1\n' > "$TMPROOT/bin/rsync"; chmod +x "$TMPROOT/bin/rsync"
HEAD_BEFORE=$(main_head); REFLOG_BEFORE=$(main_reflog_top); STATUS_BEFORE=$(main_status)
RC=0; OUT=$(cd "$REPO" && PATH="$TMPROOT/bin:$PATH" bash "$WT_SCRIPT" prepare --short-name x 2>&1) || RC=$?
assert_eq "exit code" "1" "$RC"
assert_contains "error reported" "ERROR: copying configuration" "$OUT"
assert_eq "only the main worktree" "1" "$(wt_count)"
assert_eq "no worktree dir left" "" "$(ls -A "$REPO/.claude/worktrees" 2>/dev/null || true)"
assert_eq "no branch" "1" "$(branch_count)"
assert_eq "main branch unchanged" "$HEAD_BEFORE" "$(main_head)"
assert_eq "main reflog unchanged" "$REFLOG_BEFORE" "$(main_reflog_top)"
assert_eq "main status unchanged" "$STATUS_BEFORE" "$(main_status)"

echo "Test: late-mode rollback when copying the configuration fails"
make_repo
mkdir -p "$TMPROOT/bin"; printf '#!/bin/sh\nexit 1\n' > "$TMPROOT/bin/rsync"; chmod +x "$TMPROOT/bin/rsync"
git -C "$REPO" checkout -q -b 057-x
RC=0; OUT=$(cd "$REPO" && PATH="$TMPROOT/bin:$PATH" bash "$WT_SCRIPT" prepare --short-name x 2>&1) || RC=$?
assert_eq "exit code" "1" "$RC"
assert_eq "only the main worktree" "1" "$(wt_count)"
assert_no_file "no worktree dir" "$REPO/.claude/worktrees/057-x"
assert_eq "commit-less branch deleted" "no" "$(branch_exists 057-x && echo yes || echo no)"
assert_eq "main restored" "main" "$(main_head)"

echo "Test: prepare rejects a base_path that leads back into the repository"
make_repo
printf 'worktrees:\n  base_path: ".claude/worktrees/../../src"\n' > "$REPO/.specify/extensions/spex-worktrees/worktree-config.yml"
run_wt "$REPO" prepare --short-name x
assert_eq "exit code" "1" "$RC"
assert_contains "error names base_path" "worktrees.base_path" "$OUT"
assert_eq "only the main worktree" "1" "$(wt_count)"
assert_no_file "nothing created in src" "$REPO/src"

echo "Test: prepare rejects shell metacharacters in base_path"
make_repo
printf 'worktrees:\n  base_path: ".claude/worktrees/$(touch PWNED)"\n' > "$REPO/.specify/extensions/spex-worktrees/worktree-config.yml"
run_wt "$REPO" prepare --short-name x
assert_eq "exit code" "1" "$RC"
assert_eq "only the main worktree" "1" "$(wt_count)"
assert_no_file "no command ran" "$REPO/PWNED"

echo "Test: prepare keeps tracked config at the worktree's commit"
make_repo
git -C "$REPO" add -f .specify/memory/constitution.md
git -C "$REPO" commit -qm "track constitution"
echo "uncommitted edit" >> "$REPO/.specify/memory/constitution.md"
STATUS_BEFORE=$(main_status)
run_wt "$REPO" prepare --short-name x
WT=$(status_field path)
assert_eq "exit code" "0" "$RC"
assert_eq "worktree has the committed constitution" "# constitution" "$(cat "$WT/.specify/memory/constitution.md")"
assert_eq "worktree clean" "" "$(git -C "$WT" status --porcelain)"
assert_eq "main edit kept" "$STATUS_BEFORE" "$(main_status)"
assert_file "untracked config still copied" "$WT/.specify/extensions/.registry"

echo "Test: finalize handles a non-numeric branch from --branch"
make_repo
run_wt "$REPO" prepare --short-name login --branch feature/login
WT="$REPO/.claude/worktrees/feature/login"
assert_eq "prepare exit code" "0" "$RC"
git -C "$WT" checkout -q -b feature/login
mkdir -p "$WT/specs/login"; echo "# login" > "$WT/specs/login/spec.md"
echo '{"feature_directory": "specs/login"}' > "$WT/.specify/feature.json"
flow_state "$WT" "" "specify"
run_wt "$WT" finalize
assert_eq "exit code" "0" "$RC"
assert_eq "status line" "WORKTREE_FINALIZED path=$WT branch=feature/login" "$(status_line)"
assert_eq "state feature_branch" "feature/login" "$(jq -r .feature_branch "$WT/.specify/.spex-state")"

echo "Test: finalize never moves a worktree it did not create"
make_repo
git -C "$REPO" worktree add -q -b 057-bar "$TMPROOT/my-own-wt"
mkdir -p "$TMPROOT/my-own-wt/specs/057-bar"; echo "# bar" > "$TMPROOT/my-own-wt/specs/057-bar/spec.md"
run_wt "$TMPROOT/my-own-wt" finalize
assert_eq "exit code" "0" "$RC"
assert_eq "status line" "WORKTREE_FINALIZED path=$TMPROOT/my-own-wt branch=057-bar" "$(status_line)"
assert_file "worktree still in place" "$TMPROOT/my-own-wt/specs/057-bar/spec.md"
assert_no_file "not moved into .claude/worktrees" "$REPO/.claude/worktrees/057-bar"

# ===========================================================================
# Test cases: main-checkout repair (git.feature ran in main after prepare)
# ===========================================================================

echo "Test: finalize in main repairs a run whose git.feature ran in main after prepare"
make_repo
ship_state "$REPO" "specify"
run_wt "$REPO" prepare --short-name x
PENDING=$(status_field path)
simulate_git_feature "$REPO" x
mkdir -p "$REPO/specs/057-x"; echo "# spec" > "$REPO/specs/057-x/spec.md"
echo '{"feature_directory": "specs/057-x"}' > "$REPO/.specify/feature.json"
run_wt "$REPO" finalize
WT="$REPO/.claude/worktrees/057-x"
assert_eq "exit code" "0" "$RC"
assert_eq "status line" "WORKTREE_ADOPTED path=$WT branch=057-x" "$(status_line)"
assert_contains "notice explains the repair" "NOTICE: speckit.git.feature ran in the main checkout" "$OUT"
assert_eq "main back on main" "main" "$(main_head)"
assert_eq "worktree on feature branch" "057-x" "$(wt_head "$WT")"
assert_file "spec in worktree" "$WT/specs/057-x/spec.md"
assert_file "ship state in worktree" "$WT/.specify/.spex-state"
assert_no_file "main has no state" "$REPO/.specify/.spex-state"
assert_no_file "provisional worktree removed" "$PENDING"
assert_eq "two worktrees" "2" "$(wt_count)"

echo "Test: finalize in main repairs after the spec was committed on the branch"
make_repo
run_wt "$REPO" prepare --short-name x
PENDING=$(status_field path)
simulate_git_feature "$REPO" x
mkdir -p "$REPO/specs/057-x"; echo "# spec" > "$REPO/specs/057-x/spec.md"
git -C "$REPO" add specs/057-x; git -C "$REPO" commit -qm "spec"
run_wt "$REPO" finalize
assert_eq "status ADOPTED" "WORKTREE_ADOPTED" "$(status_line | cut -d' ' -f1)"
assert_no_file "provisional worktree removed" "$PENDING"

echo "Test: finalize in main refuses a branch whose short name differs"
make_repo
run_wt "$REPO" prepare --short-name x
PENDING=$(status_field path)
simulate_git_feature "$REPO" y
mkdir -p "$REPO/specs/057-y"; echo "# spec" > "$REPO/specs/057-y/spec.md"
run_wt "$REPO" finalize
assert_eq "status line" "WORKTREE_SKIPPED reason=prepared-worktree-exists" "$(status_line)"
assert_eq "main stays on 057-y" "057-y" "$(main_head)"
assert_file "prepared worktree kept" "$PENDING/README.md"

echo "Test: finalize in main refuses a matching branch created before prepare"
make_repo
GIT_COMMITTER_DATE="2020-01-01T00:00:00Z" git -C "$REPO" branch 057-x
run_wt "$REPO" prepare --short-name x
PENDING=$(status_field path)
git -C "$REPO" checkout -q 057-x
mkdir -p "$REPO/specs/057-x"; echo "# spec" > "$REPO/specs/057-x/spec.md"
run_wt "$REPO" finalize
assert_eq "status line" "WORKTREE_SKIPPED reason=prepared-worktree-exists" "$(status_line)"
assert_eq "main stays on 057-x" "057-x" "$(main_head)"
assert_file "prepared worktree kept" "$PENDING/README.md"

echo "Test: finalize in main refuses a matching branch with non-spec commits"
make_repo
run_wt "$REPO" prepare --short-name x
PENDING=$(status_field path)
simulate_git_feature "$REPO" x
echo "code" > "$REPO/code.txt"; git -C "$REPO" add code.txt; git -C "$REPO" commit -qm "foreign"
mkdir -p "$REPO/specs/057-x"; echo "# spec" > "$REPO/specs/057-x/spec.md"
TIP=$(git -C "$REPO" rev-parse 057-x)
run_wt "$REPO" finalize
assert_eq "status line" "WORKTREE_SKIPPED reason=prepared-worktree-exists" "$(status_line)"
assert_eq "branch tip unchanged" "$TIP" "$(git -C "$REPO" rev-parse 057-x)"
assert_file "prepared worktree kept" "$PENDING/README.md"

echo "Test: finalize in main refuses when two prepared worktrees share the short name"
make_repo
run_wt "$REPO" prepare --short-name x
P1=$(status_field path)
run_wt "$REPO" prepare --short-name x
P2=$(status_field path)
simulate_git_feature "$REPO" x
mkdir -p "$REPO/specs/057-x"; echo "# spec" > "$REPO/specs/057-x/spec.md"
run_wt "$REPO" finalize
assert_eq "status line" "WORKTREE_SKIPPED reason=prepared-worktree-exists" "$(status_line)"
assert_file "first prepared worktree kept" "$P1/README.md"
assert_file "second prepared worktree kept" "$P2/README.md"
assert_eq "main stays on 057-x" "057-x" "$(main_head)"

echo "Test: finalize in main still matches an old one-line marker exactly"
make_repo
run_wt "$REPO" prepare --short-name x --branch 057-x
WT="$REPO/.claude/worktrees/057-x"
printf '057-x\n' > "$(git -C "$WT" rev-parse --absolute-git-dir)/spex-prepared"
git -C "$REPO" worktree move "$WT" "$REPO/.claude/worktrees/old-style"
git -C "$REPO" checkout -q -b 057-x
mkdir -p "$REPO/specs/057-x"; echo "# spec" > "$REPO/specs/057-x/spec.md"
run_wt "$REPO" finalize
assert_eq "status line" "WORKTREE_ADOPTED path=$WT branch=057-x" "$(status_line)"
assert_no_file "old prepared worktree removed" "$REPO/.claude/worktrees/old-style"

echo "Test: finalize in main keeps both states when the repair would lose one"
make_repo
ship_state "$REPO" "specify"
run_wt "$REPO" prepare --short-name x
WT=$(status_field path)
flow_state "$REPO" "042-other"
simulate_git_feature "$REPO" x
mkdir -p "$REPO/specs/057-x"; echo "# spec" > "$REPO/specs/057-x/spec.md"
run_wt "$REPO" finalize
assert_eq "exit code" "0" "$RC"
assert_eq "status line" "WORKTREE_SKIPPED reason=prepared-worktree-exists" "$(status_line)"
assert_eq "prepared state kept" "ship" "$(jq -r .mode "$WT/.specify/.spex-state")"
assert_eq "main state kept" "042-other" "$(jq -r .feature_branch "$REPO/.specify/.spex-state")"
assert_eq "main still on 057-x" "057-x" "$(main_head)"
assert_eq "two worktrees" "2" "$(wt_count)"

echo "Test: finalize in main repairs when the flow-state hook also wrote state in main"
make_repo
# Untracked, not ignored config that prepare copies counts as a copy.
printf '.claude/*\n!.claude/local.json\n.specify/\n' > "$REPO/.gitignore"
git -C "$REPO" commit -qam "unignore local.json"
echo '{}' > "$REPO/.claude/local.json"
ship_state "$REPO" "specify"
run_wt "$REPO" prepare --short-name x
PENDING=$(status_field path)
assert_contains "copied config shows as untracked in the worktree" "?? .claude/" "$(git -C "$PENDING" status --porcelain)"
simulate_git_feature "$REPO" x
flow_state "$REPO" "057-x" "specify"
mkdir -p "$REPO/specs/057-x"; echo "# spec" > "$REPO/specs/057-x/spec.md"
run_wt "$REPO" finalize
WT="$REPO/.claude/worktrees/057-x"
assert_eq "exit code" "0" "$RC"
assert_eq "status ADOPTED" "WORKTREE_ADOPTED" "$(status_line | cut -d' ' -f1)"
assert_eq "worktree keeps the ship state" "ship" "$(jq -r .mode "$WT/.specify/.spex-state")"
assert_file "main flow state backed up" "$REPO/.specify/.spex-state.bak-057-x"
assert_eq "main back on main" "main" "$(main_head)"

echo "Test: finalize in main never removes a prepared worktree holding spec content"
make_repo
run_wt "$REPO" prepare --short-name x
WT=$(status_field path)
simulate_git_feature "$REPO" x
mkdir -p "$REPO/specs/057-x" "$WT/specs/057-x"
echo "# main" > "$REPO/specs/057-x/spec.md"; echo "# wt" > "$WT/specs/057-x/spec.md"
run_wt "$REPO" finalize
assert_eq "exit code" "0" "$RC"
assert_eq "status line" "WORKTREE_SKIPPED reason=prepared-worktree-exists" "$(status_line)"
assert_file "worktree spec kept" "$WT/specs/057-x/spec.md"

echo "Test: finalize in main never removes a prepared worktree with edited ignored config"
make_repo
run_wt "$REPO" prepare --short-name x
WT=$(status_field path)
simulate_git_feature "$REPO" x
mkdir -p "$REPO/specs/057-x"; echo "# spec" > "$REPO/specs/057-x/spec.md"
echo '{"edited": true}' > "$WT/.claude/settings.json"
touch -t 203001010000 "$WT/.claude/settings.json"
run_wt "$REPO" finalize
assert_eq "exit code" "0" "$RC"
assert_eq "status line" "WORKTREE_SKIPPED reason=prepared-worktree-exists" "$(status_line)"
assert_contains "edited config kept" "edited" "$(cat "$WT/.claude/settings.json")"

echo "Test: finalize in main never removes a prepared worktree with an added old file"
make_repo
run_wt "$REPO" prepare --short-name x
WT=$(status_field path)
simulate_git_feature "$REPO" x
mkdir -p "$REPO/specs/057-x"; echo "# spec" > "$REPO/specs/057-x/spec.md"
echo "artifact" > "$TMPROOT/artifact.txt"; touch -t 200001010000 "$TMPROOT/artifact.txt"
cp -p "$TMPROOT/artifact.txt" "$WT/.claude/artifact.txt"
run_wt "$REPO" finalize
assert_eq "status line" "WORKTREE_SKIPPED reason=prepared-worktree-exists" "$(status_line)"
assert_file "added file kept" "$WT/.claude/artifact.txt"

echo "Test: finalize in main never removes a prepared worktree with ignored spec content"
make_repo
mkdir -p "$REPO/.git/info"; printf 'specs/057-x/\n' >> "$REPO/.git/info/exclude"
run_wt "$REPO" prepare --short-name x
WT=$(status_field path)
simulate_git_feature "$REPO" x
mkdir -p "$REPO/specs/057-x" "$WT/specs/057-x"
echo "# main" > "$REPO/specs/057-x/spec.md"; echo "# wt" > "$WT/specs/057-x/spec.md"
run_wt "$REPO" finalize
assert_eq "status line" "WORKTREE_SKIPPED reason=prepared-worktree-exists" "$(status_line)"
assert_file "ignored worktree spec kept" "$WT/specs/057-x/spec.md"

echo "Test: finalize in main keeps a running flow state of another feature"
make_repo
ship_state "$REPO" "specify"
run_wt "$REPO" prepare --short-name x
WT=$(status_field path)
flow_state "$REPO" "042-other" "specify"
simulate_git_feature "$REPO" x
mkdir -p "$REPO/specs/057-x"; echo "# spec" > "$REPO/specs/057-x/spec.md"
run_wt "$REPO" finalize
assert_eq "status line" "WORKTREE_SKIPPED reason=prepared-worktree-exists" "$(status_line)"
assert_eq "other state untouched" "042-other" "$(jq -r .feature_branch "$REPO/.specify/.spex-state")"
assert_eq "prepared state kept" "ship" "$(jq -r .mode "$WT/.specify/.spex-state")"

echo "Test: late mode with an exact non-pattern branch name"
make_repo
git -C "$REPO" checkout -q -b feat/user-auth
run_wt "$REPO" prepare --short-name user-auth --branch feat/user-auth
assert_eq "exit code" "0" "$RC"
assert_eq "mode late" "late" "$(status_field mode)"
assert_eq "main restored" "main" "$(main_head)"
assert_eq "worktree on the branch" "feat/user-auth" "$(wt_head "$REPO/.claude/worktrees/feat/user-auth")"

echo "Test: an old-flow worktree does not block adopt from main"
make_repo
mkdir -p "$REPO/.claude/worktrees"
git -C "$REPO" worktree add -q -b 050-old "$REPO/.claude/worktrees/050-old"
git -C "$REPO" checkout -q -b 057-new
mkdir -p "$REPO/specs/057-new"; echo "# new" > "$REPO/specs/057-new/spec.md"
run_wt "$REPO" finalize
assert_eq "exit code" "0" "$RC"
assert_eq "status ADOPTED" "WORKTREE_ADOPTED" "$(status_line | cut -d' ' -f1)"
assert_eq "main back on main" "main" "$(main_head)"

echo "Test: adopt resets a staged tracked feature.json pointer in main"
make_repo
git -C "$REPO" add -f .specify/feature.json
git -C "$REPO" commit -qm "track feature.json"
git -C "$REPO" checkout -q -b 057-s
mkdir -p "$REPO/specs/057-s"; echo "# s" > "$REPO/specs/057-s/spec.md"
echo '{"feature_directory": "specs/057-s"}' > "$REPO/.specify/feature.json"
git -C "$REPO" add -f .specify/feature.json
run_wt "$REPO" adopt
WT="$REPO/.claude/worktrees/057-s"
assert_eq "exit code" "0" "$RC"
assert_eq "main back on main" "main" "$(main_head)"
assert_eq "staged feature.json reset in main" "" "$(git -C "$REPO" status --porcelain -- .specify/feature.json)"
assert_eq "feature.json in worktree" "specs/057-s" "$(jq -r .feature_directory "$WT/.specify/feature.json")"

# ===========================================================================
# Test cases: concurrent session in the main checkout (SC-002)
# ===========================================================================

echo "Test: commits made in main during prepare and finalize land on main"
make_repo
: > "$TMPROOT/commits.txt"; : > "$TMPROOT/heads.txt"
(
  i=0
  while [ ! -f "$TMPROOT/stop" ]; do
    i=$((i + 1))
    echo "$i" >> "$REPO/concurrent.txt"
    if git -C "$REPO" add concurrent.txt 2>/dev/null &&
       git -C "$REPO" commit -qm "concurrent $i" 2>/dev/null; then
      git -C "$REPO" rev-parse HEAD >> "$TMPROOT/commits.txt"
    fi
    git -C "$REPO" rev-parse --abbrev-ref HEAD >> "$TMPROOT/heads.txt"
    sleep 0.2
  done
) &
BGPID=$!
sleep 0.5
run_wt "$REPO" prepare --short-name x --description "Add x"
PREP_RC=$RC
PENDING=$(status_field path)
simulate_git_feature "$PENDING" x
mkdir -p "$PENDING/specs/057-x"; echo "# spec" > "$PENDING/specs/057-x/spec.md"
run_wt "$PENDING" finalize
FIN_RC=$RC
FIN_PATH=$(status_field path)
sleep 0.5
touch "$TMPROOT/stop"
wait "$BGPID" 2>/dev/null || true
BGPID=""
assert_eq "prepare exit code" "0" "$PREP_RC"
assert_eq "finalize exit code" "0" "$FIN_RC"
assert_eq "finalize renamed the worktree" "$REPO/.claude/worktrees/057-x" "$FIN_PATH"
COMMITS=$(wc -l < "$TMPROOT/commits.txt" | tr -d ' ')
if [ "$COMMITS" -ge 3 ]; then
  echo "  PASS: background loop committed ($COMMITS commits)"; PASS=$((PASS + 1))
else
  echo "  FAIL: background loop made only $COMMITS commits"; FAIL=$((FAIL + 1))
fi
NOT_ON_MAIN=0
while IFS= read -r c; do
  git -C "$REPO" merge-base --is-ancestor "$c" main || NOT_ON_MAIN=$((NOT_ON_MAIN + 1))
done < "$TMPROOT/commits.txt"
assert_eq "every concurrent commit is on main" "0" "$NOT_ON_MAIN"
FEATURE_ONLY=$(git -C "$REPO" rev-list main..057-x | wc -l | tr -d ' ')
assert_eq "no commit reachable from the feature branch only" "0" "$FEATURE_ONLY"
assert_eq "main checkout never left main" "main" "$(sort -u "$TMPROOT/heads.txt" | tr '\n' ' ' | sed 's/ $//')"

# ===========================================================================
# Test cases: stale worktree report (stale subcommand and the create notice)
# ===========================================================================

TAB=$'\t'

# stale_record <path>: the record the last `stale` run printed for a worktree.
stale_record() {
  printf '%s\n' "$OUT" | awk -F'\t' -v p="$1" '$2 == p'
}

# stale_summary <path>: state, branch, reasons, origin of that record.
stale_summary() {
  stale_record "$1" | cut -f1,3,4,5
}

# add_stale_wt <name> <branch>: a linked worktree on a new branch, with one commit.
add_stale_wt() {
  git -C "$REPO" worktree add -q -b "$2" "$WTS/$1" main
  echo "$1" > "$WTS/$1/$1.txt"
  git -C "$WTS/$1" add "$1.txt"
  git -C "$WTS/$1" commit -qm "work on $1"
}

echo "Test: stale report covers merged, upstream-gone, detached, dirty, locked, current"
make_repo
WTS="$TMPROOT/wts"
mkdir -p "$WTS"
INITIAL=$(git -C "$REPO" rev-parse main)
git init -q --bare "$TMPROOT/origin.git"
git -C "$REPO" remote add origin "$TMPROOT/origin.git"
git -C "$REPO" push -q origin main
add_stale_wt 004-merged 004-merged
add_stale_wt fix-typo fix/typo
add_stale_wt 005-dirty 005-dirty
add_stale_wt 006-locked 006-locked
add_stale_wt 008-current 008-current
add_stale_wt gone gone-branch
add_stale_wt wip wip-branch
git -C "$REPO" worktree add -q --detach "$WTS/det-unique" main
echo "only here" > "$WTS/det-unique/only-here.txt"
git -C "$WTS/det-unique" add only-here.txt
git -C "$WTS/det-unique" commit -qm "commit on no branch"
# gone-branch: pushed with an upstream, then deleted on the remote and pruned.
git -C "$WTS/gone" push -q -u origin gone-branch
git -C "$TMPROOT/origin.git" branch -q -D gone-branch
git -C "$REPO" fetch -q --prune origin
# The merged ones land on main (a merge commit each, so main moves on).
for b in 004-merged fix/typo 005-dirty 006-locked 008-current; do
  git -C "$REPO" merge -q --no-ff -m "merge $b" "$b"
done
git -C "$REPO" worktree add -q --detach "$WTS/det-merged" "$INITIAL"
# A branch just created at main's tip has nothing of its own yet: it looks
# the same as a fast-forward merged one, so it is not reported.
git -C "$REPO" worktree add -q -b 007-fresh "$WTS/007-fresh" main
echo "scratch" > "$WTS/005-dirty/scratch.txt"
git -C "$REPO" worktree lock "$WTS/006-locked"
BRANCHES_BEFORE=$(branch_count)
WT_BEFORE=$(wt_count)

run_wt "$REPO" stale
assert_eq "exit code" "0" "$RC"
assert_eq "status line counts" "WORKTREE_STALE count=5 dirty=1 default=main" "$(status_line)"
assert_eq "merged NNN branch" "STALE${TAB}004-merged${TAB}merged${TAB}spex" "$(stale_summary "$WTS/004-merged")"
assert_eq "merged fix/... branch" "STALE${TAB}fix/typo${TAB}merged${TAB}other" "$(stale_summary "$WTS/fix-typo")"
assert_eq "upstream gone, not merged" "STALE${TAB}gone-branch${TAB}upstream-gone${TAB}other" "$(stale_summary "$WTS/gone")"
assert_eq "detached HEAD reachable from main" "STALE${TAB}(detached)${TAB}detached-merged${TAB}other" "$(stale_summary "$WTS/det-merged")"
assert_eq "merged but dirty is reported as dirty" "DIRTY${TAB}005-dirty${TAB}merged${TAB}spex" "$(stale_summary "$WTS/005-dirty")"
assert_eq "current worktree is listed when run from main" "STALE${TAB}008-current${TAB}merged${TAB}spex" "$(stale_summary "$WTS/008-current")"
assert_eq "unmerged branch not reported" "" "$(stale_record "$WTS/wip")"
assert_eq "detached HEAD with its own commit not reported" "" "$(stale_record "$WTS/det-unique")"
assert_eq "new empty branch not reported" "" "$(stale_record "$WTS/007-fresh")"
assert_eq "locked worktree not reported" "" "$(stale_record "$WTS/006-locked")"
assert_eq "main checkout not reported" "" "$(stale_record "$REPO")"
assert_eq "ahead count of the upstream-gone branch" "1" "$(stale_record "$WTS/gone" | cut -f6)"
assert_eq "nothing removed (worktrees)" "$WT_BEFORE" "$(wt_count)"
assert_eq "nothing removed (branches)" "$BRANCHES_BEFORE" "$(branch_count)"
assert_file "dirty file still there" "$WTS/005-dirty/scratch.txt"

echo "Test: stale report never offers the worktree the session runs in"
run_wt "$WTS/008-current" stale
assert_eq "exit code" "0" "$RC"
assert_eq "current worktree not reported" "" "$(stale_record "$WTS/008-current")"
assert_eq "other stale worktrees still reported" "STALE${TAB}004-merged${TAB}merged${TAB}spex" "$(stale_summary "$WTS/004-merged")"
assert_eq "main checkout not reported from a worktree" "" "$(stale_record "$REPO")"

echo "Test: create prints a notice (no prompt, nothing removed), one line each up to three"
make_repo
WTS="$TMPROOT/wts"
mkdir -p "$WTS"
add_stale_wt 004-old 004-old
add_stale_wt fix-old fix/old
git -C "$REPO" merge -q --no-ff -m "merge old" 004-old
git -C "$REPO" merge -q --no-ff -m "merge fix" fix/old
WT_BEFORE=$(wt_count)
run_wt "$REPO" prepare --short-name x
assert_eq "exit code" "0" "$RC"
assert_contains "notice names the NNN worktree" "NOTICE: stale worktree $WTS/004-old (004-old): merged" "$OUT"
assert_contains "notice names the fix worktree" "NOTICE: stale worktree $WTS/fix-old (fix/old): merged" "$OUT"
assert_contains "notice points at cleanup" "/speckit-spex-worktrees-manage cleanup" "$OUT"
assert_eq "last line is still cd" "cd $(status_field path)" "$(last_line)"
assert_eq "only the new worktree was added" "$((WT_BEFORE + 1))" "$(wt_count)"

echo "Test: create collapses the notice to a count past three, and counts dirty ones"
make_repo
WTS="$TMPROOT/wts"
mkdir -p "$WTS"
for n in 1 2 3 4; do
  add_stale_wt "00$n-old" "00$n-old"
  git -C "$REPO" merge -q --no-ff -m "merge $n" "00$n-old"
done
add_stale_wt 005-old 005-old
git -C "$REPO" merge -q --no-ff -m "merge 5" 005-old
echo "scratch" > "$WTS/005-old/scratch.txt"
run_wt "$REPO" prepare --short-name x
assert_eq "exit code" "0" "$RC"
assert_contains "count line" "NOTICE: 4 stale worktrees (merged into main" "$OUT"
assert_not_contains "no per-worktree lines past the limit" "NOTICE: stale worktree" "$OUT"
assert_contains "dirty count line" "NOTICE: 1 more stale worktree(s) have uncommitted or untracked changes" "$OUT"
assert_eq "last line is still cd" "cd $(status_field path)" "$(last_line)"

echo "Test: create prints no notice when nothing is stale"
make_repo
run_wt "$REPO" prepare --short-name x
assert_eq "exit code" "0" "$RC"
assert_not_contains "no stale notice" "stale" "$OUT"

echo "Test: stale never fetches or touches the network"
assert_eq "script has no fetch, pull or remote update" "0" "$(grep -cE 'git (-C [^ ]+ )?(fetch|pull|remote update)' "$WT_SCRIPT" || true)"

echo "Test: a finalized spex worktree with copied config is stale, dirty only with real changes"
make_repo
# Do not ignore the copied config, so prepare puts untracked files in the worktree.
: > "$REPO/.gitignore"
git -C "$REPO" add .gitignore
git -C "$REPO" commit -qm "stop ignoring config"
run_wt "$REPO" prepare --short-name x
PENDING=$(status_field path)
simulate_git_feature "$PENDING" x 057
echo "feature" > "$PENDING/feature.txt"
git -C "$PENDING" add feature.txt
git -C "$PENDING" commit -qm "feature work"
run_wt "$PENDING" finalize
FINAL=$(status_field path)
git -C "$REPO" merge -q --no-ff -m "merge 057-x" 057-x
run_wt "$REPO" stale
assert_eq "copied config does not make it dirty" "STALE${TAB}057-x${TAB}merged${TAB}spex" "$(stale_summary "$FINAL")"
# The answer to "does a finalized one hit the same wall as pending": a plain
# git worktree remove refuses while the copied config is untracked.
PLAIN_RC=0
git -C "$REPO" worktree remove "$FINAL" >/dev/null 2>&1 || PLAIN_RC=$?
assert_ne "plain git worktree remove refuses (copied config is untracked)" "0" "$PLAIN_RC"
assert_file "worktree still there after the refused removal" "$FINAL"
echo "notes" > "$FINAL/notes.txt"
run_wt "$REPO" stale
assert_eq "a new untracked file makes it dirty" "DIRTY${TAB}057-x${TAB}merged${TAB}spex" "$(stale_summary "$FINAL")"

# ===========================================================================

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
