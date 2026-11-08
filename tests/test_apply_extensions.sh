#!/usr/bin/env bash
# Tests for spex/scripts/spex-apply-extensions.sh (FR-003, FR-006, FR-018).
#
# A stub `specify` CLI on PATH edits .specify/extensions/.registry with jq the
# way specify-cli does for `extension enable/disable/list`, and records every
# call in a log file. STUB_FAIL_ENABLE / STUB_FAIL_DISABLE name extensions
# whose enable or disable should fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APPLY="$REPO_ROOT/spex/scripts/spex-apply-extensions.sh"

DETACH_SRC="$REPO_ROOT/spex/extensions/spex-detach/scripts"

PASS=0
FAIL=0
TMPROOT=""
PROJ=""

# Isolate git from the developer's global configuration (a global excludes
# file would change what the stealth-mode verification reports).
GIT_ISOLATION_HOME=$(mktemp -d)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$GIT_ISOLATION_HOME"
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

cleanup() {
  if [ -n "$TMPROOT" ] && [ -d "$TMPROOT" ]; then
    rm -rf "$TMPROOT"
  fi
  TMPROOT=""
}
trap 'cleanup; rm -rf "$GIT_ISOLATION_HOME"' EXIT

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected '$expected', got '$actual')"; FAIL=$((FAIL + 1))
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
    echo "  FAIL: $desc (unexpected '$needle' in output:"; printf '%s\n' "$haystack" | sed 's/^/      /'; echo "    )"
    FAIL=$((FAIL + 1))
  fi
}

# make_project '<registry extensions JSON object>'
# Example: make_project '{"spex": true, "spex-gates": false}'
make_project() {
  cleanup
  local raw
  raw=$(mktemp -d) || exit 1
  TMPROOT=$(cd "$raw" && pwd -P) || exit 1
  [ -n "$TMPROOT" ] && [ -d "$TMPROOT" ] && [ "$TMPROOT" != "$(pwd -P)" ] || { echo "cannot create a temporary directory" >&2; exit 1; }
  PROJ="$TMPROOT/proj"
  mkdir -p "$PROJ/.specify/extensions" "$TMPROOT/bin"
  : > "$TMPROOT/calls.log"
  jq -n --argjson exts "$1" \
    '{schema_version: "1.0", extensions: ($exts | with_entries(.value = {enabled: .value, version: "1.0.0"}))}' \
    > "$PROJ/.specify/extensions/.registry"

  cat > "$TMPROOT/bin/specify" <<'EOF'
#!/usr/bin/env bash
REG=".specify/extensions/.registry"
printf '%s\n' "$*" >> "$STUB_ROOT/calls.log"
in_list() { case " $1 " in *" $2 "*) return 0 ;; esac; return 1; }
set_enabled() {
  jq -e --arg id "$1" '.extensions[$id] != null' "$REG" >/dev/null || { echo "Extension '$1' is not installed" >&2; exit 1; }
  jq --arg id "$1" --argjson v "$2" '.extensions[$id].enabled = $v' "$REG" > "$REG.tmp" && mv "$REG.tmp" "$REG"
}
case "$1 $2" in
  "extension enable")
    if in_list "${STUB_FAIL_ENABLE:-}" "$3"; then echo "enable failed" >&2; exit 1; fi
    set_enabled "$3" true; echo "Extension '$3' enabled"; exit 0 ;;
  "extension disable")
    if in_list "${STUB_FAIL_DISABLE:-}" "$3"; then echo "disable failed" >&2; exit 1; fi
    set_enabled "$3" false; echo "Extension '$3' disabled"; exit 0 ;;
  "extension list")
    jq -r '.extensions | to_entries[] | "\(.key) \(.value.enabled)"' "$REG"; exit 0 ;;
esac
echo "unexpected stub call: $*" >&2
exit 1
EOF
  chmod +x "$TMPROOT/bin/specify"
}

# run_apply <args...>: runs the script in the fixture project.
# Sets RC, OUT (stdout), ERR (stderr).
run_apply() {
  RC=0
  [ -n "${PROJ:-}" ] && [ -d "$PROJ/.specify" ] || { echo "fixture missing" >&2; exit 1; }
  [ "$(PATH="$TMPROOT/bin:$PATH" command -v specify)" = "$TMPROOT/bin/specify" ] || { echo "specify stub not first on PATH" >&2; exit 1; }
  : > "$TMPROOT/calls.log"
  (cd "$PROJ" && STUB_ROOT="$TMPROOT" PATH="$TMPROOT/bin:$PATH" sh "$APPLY" "$@" \
    > "$TMPROOT/out" 2> "$TMPROOT/err") || RC=$?
  OUT=$(cat "$TMPROOT/out")
  ERR=$(cat "$TMPROOT/err")
  CALLS=$(cat "$TMPROOT/calls.log")
}

enabled() {
  jq -r --arg id "$1" '.extensions[$id] | if . == null then "absent" else (.enabled | tostring) end' \
    "$PROJ/.specify/extensions/.registry"
}

# add_detach_scripts [git]: install the real spex-detach scripts into the
# fixture; with "git", also make the project a git repository.
add_detach_scripts() {
  mkdir -p "$PROJ/.specify/extensions/spex-detach/scripts"
  cp "$DETACH_SRC"/* "$PROJ/.specify/extensions/spex-detach/scripts/"
  chmod +x "$PROJ/.specify/extensions/spex-detach/scripts/spex-detach.sh"
  if [ "${1:-}" = git ]; then
    git -C "$PROJ" init -q
    mkdir -p "$PROJ/.git/info"
  fi
}

EXCLUDE_FILE_REL=".git/info/exclude"

ALL_ON='{"spex": true, "spex-gates": true, "spex-worktrees": true, "spex-deep-review": true, "spex-teams": true, "spex-collab": true, "spex-detach": true, "git": true}'
RECOMMENDED="spex,spex-gates,spex-worktrees,spex-deep-review"

echo "Test: recommended selection on a fully enabled project"
make_project "$ALL_ON"
run_apply "$RECOMMENDED"
assert_eq "exit code 0" "0" "$RC"
for ext in spex-gates spex-worktrees spex-deep-review; do
  assert_eq "$ext enabled" "true" "$(enabled "$ext")"
done
for ext in spex-teams spex-collab spex-detach; do
  assert_eq "$ext disabled" "false" "$(enabled "$ext")"
  assert_contains "reports Disabled: $ext" "Disabled: $ext" "$ERR"
done
assert_contains "summary line" "Extensions: 0 enabled, 3 disabled, 3 unchanged" "$ERR"
assert_eq "stdout stays empty" "" "$OUT"
assert_eq "spex untouched" "true" "$(enabled spex)"
assert_eq "git untouched" "true" "$(enabled git)"
assert_not_contains "no call for spex" "extension disable spex " "$CALLS "
assert_not_contains "never disables git" "disable git" "$CALLS"

echo "Test: a selection naming spex-detach enables it"
make_project '{"spex": true, "spex-gates": true, "spex-detach": false}'
run_apply "spex,spex-gates,spex-detach"
assert_eq "exit code 0" "0" "$RC"
assert_eq "spex-detach enabled" "true" "$(enabled spex-detach)"
assert_contains "reports Enabled: spex-detach" "Enabled: spex-detach" "$ERR"
assert_contains "summary line" "Extensions: 1 enabled, 0 disabled, 1 unchanged" "$ERR"

echo "Test: matching state makes no enable or disable call"
make_project '{"spex": true, "spex-gates": true, "spex-worktrees": true, "spex-deep-review": true, "spex-teams": false, "spex-collab": false, "spex-detach": false, "git": true}'
run_apply "$RECOMMENDED"
assert_eq "exit code 0" "0" "$RC"
assert_not_contains "no enable call" "extension enable" "$CALLS"
assert_not_contains "no disable call" "extension disable" "$CALLS"
assert_not_contains "no Enabled: line" "Enabled:" "$ERR"
assert_not_contains "no Disabled: line" "Disabled:" "$ERR"
assert_contains "summary line" "Extensions: 0 enabled, 0 disabled, 6 unchanged" "$ERR"

echo "Test: every change is named, in both directions"
make_project '{"spex": true, "spex-gates": false, "spex-worktrees": false, "spex-deep-review": true, "spex-teams": true, "spex-collab": false, "spex-detach": false, "git": true}'
run_apply "$RECOMMENDED"
assert_eq "exit code 0" "0" "$RC"
assert_contains "Enabled: spex-gates" "Enabled: spex-gates" "$ERR"
assert_contains "Enabled: spex-worktrees" "Enabled: spex-worktrees" "$ERR"
assert_contains "Disabled: spex-teams" "Disabled: spex-teams" "$ERR"
assert_not_contains "deep-review unchanged" "spex-deep-review" "$(printf '%s\n' "$ERR" | grep -E '^(Enabled|Disabled):' || true)"
assert_contains "summary line" "Extensions: 2 enabled, 1 disabled, 3 unchanged" "$ERR"

echo "Test: spex and a non-spex git extension are never touched"
make_project '{"spex": false, "spex-gates": true, "git": true, "other": true}'
run_apply "spex,spex-gates"
assert_eq "exit code 0" "0" "$RC"
assert_eq "spex left as it is" "false" "$(enabled spex)"
assert_eq "git still enabled" "true" "$(enabled git)"
assert_eq "other still enabled" "true" "$(enabled other)"
assert_eq "no specify calls at all" "" "$CALLS"

echo "Test: an unselected extension that is not installed is ignored"
make_project '{"spex": true, "spex-gates": true}'
run_apply "spex,spex-gates"
assert_eq "exit code 0" "0" "$RC"
assert_eq "no specify calls" "" "$CALLS"
assert_contains "summary counts installed only" "Extensions: 0 enabled, 0 disabled, 1 unchanged" "$ERR"

echo "Test: a selected extension that is not installed exits 1"
make_project '{"spex": true, "spex-gates": true, "spex-teams": true}'
run_apply "spex,spex-gates,spex-collab"
assert_eq "exit code 1" "1" "$RC"
assert_contains "names the missing extension" "spex-collab" "$ERR"
assert_contains "says it is not installed" "not installed" "$ERR"

echo "Test: selecting spex-worktrees enables a disabled git extension"
make_project '{"spex": true, "spex-worktrees": true, "git": false}'
run_apply "spex,spex-worktrees"
assert_eq "exit code 0" "0" "$RC"
assert_eq "git enabled" "true" "$(enabled git)"
assert_contains "reports git" "Enabled: git" "$ERR"

echo "Test: without spex-worktrees a disabled git stays disabled and an enabled one stays enabled"
make_project '{"spex": true, "spex-worktrees": true, "git": false}'
run_apply "spex"
assert_eq "exit code 0" "0" "$RC"
assert_eq "git still disabled" "false" "$(enabled git)"
assert_not_contains "no git call" " git" "$CALLS"
make_project '{"spex": true, "spex-worktrees": true, "git": true}'
run_apply "spex"
assert_eq "git still enabled" "true" "$(enabled git)"
assert_not_contains "never disables git" "disable git" "$CALLS"

echo "Test: a failing git enable only warns"
make_project '{"spex": true, "spex-worktrees": true, "git": false}'
STUB_FAIL_ENABLE="git" run_apply "spex,spex-worktrees"
assert_eq "exit code 0" "0" "$RC"
assert_contains "warns about git" "WARNING" "$ERR"
assert_contains "warning names git" "git" "$ERR"
assert_eq "git stays disabled" "false" "$(enabled git)"
echo "Test: a missing git extension only warns"
make_project '{"spex": true, "spex-worktrees": true}'
run_apply "spex,spex-worktrees"
assert_eq "exit code 0" "0" "$RC"
assert_contains "warns about git" "WARNING" "$ERR"

echo "Test: --before reports only changes against the snapshot"
make_project "$ALL_ON"
jq -n '{schema_version: "1.0", extensions: {
  "spex": {enabled: true}, "spex-gates": {enabled: true}, "spex-worktrees": {enabled: true},
  "spex-deep-review": {enabled: true}, "spex-teams": {enabled: true},
  "spex-collab": {enabled: false}, "spex-detach": {enabled: false}, "git": {enabled: true}}}' \
  > "$TMPROOT/before.json"
run_apply --before "$TMPROOT/before.json" "$RECOMMENDED"
assert_eq "exit code 0" "0" "$RC"
assert_contains "teams changed against the snapshot" "Disabled: spex-teams" "$ERR"
assert_not_contains "collab was already disabled" "Disabled: spex-collab" "$ERR"
assert_not_contains "detach was already disabled" "Disabled: spex-detach" "$ERR"
assert_eq "collab disabled again" "false" "$(enabled spex-collab)"
assert_eq "detach disabled again" "false" "$(enabled spex-detach)"
assert_contains "summary line" "Extensions: 0 enabled, 1 disabled, 5 unchanged" "$ERR"

echo "Test: --before with an extension absent from the snapshot reports against the current state"
make_project "$ALL_ON"
jq -n '{schema_version: "1.0", extensions: {"spex": {enabled: true}}}' > "$TMPROOT/before.json"
run_apply --before "$TMPROOT/before.json" "$RECOMMENDED"
assert_contains "new install disabled is reported" "Disabled: spex-teams" "$ERR"

echo "Test: a failing disable exits 1 and names the extension"
make_project "$ALL_ON"
STUB_FAIL_DISABLE="spex-collab" run_apply "$RECOMMENDED"
assert_eq "exit code 1" "1" "$RC"
assert_contains "names spex-collab" "spex-collab" "$ERR"
assert_contains "error line" "ERROR" "$ERR"

echo "Test: a failing enable exits 1 and names the extension"
make_project '{"spex": true, "spex-gates": false}'
STUB_FAIL_ENABLE="spex-gates" run_apply "spex,spex-gates"
assert_eq "exit code 1" "1" "$RC"
assert_contains "names spex-gates" "spex-gates" "$ERR"

echo "Test: a selection containing spex is accepted and spex is left alone"
make_project '{"spex": true, "spex-gates": true, "spex-teams": true}'
run_apply "spex"
assert_eq "exit code 0" "0" "$RC"
assert_eq "spex still enabled" "true" "$(enabled spex)"
assert_eq "gates disabled" "false" "$(enabled spex-gates)"
assert_eq "teams disabled" "false" "$(enabled spex-teams)"
assert_eq "no call for spex" "0" "$(printf '%s\n' "$CALLS" | grep -cxE 'extension (enable|disable) spex' || true)"

echo "Test: usage errors exit 2"
make_project "$ALL_ON"
run_apply ""
assert_eq "empty selection exits 2" "2" "$RC"
run_apply
assert_eq "missing selection exits 2" "2" "$RC"
run_apply "spex,spex-unknown"
assert_eq "unknown name exits 2" "2" "$RC"
assert_contains "names the unknown extension" "spex-unknown" "$ERR"
run_apply "spex,git"
assert_eq "non-spex name exits 2" "2" "$RC"
run_apply --before "$TMPROOT/does-not-exist.json" "$RECOMMENDED"
assert_eq "unreadable --before exits 2" "2" "$RC"
run_apply --bogus "$RECOMMENDED"
assert_eq "unknown option exits 2" "2" "$RC"
assert_eq "usage errors change nothing" "true" "$(enabled spex-teams)"

echo "Test: selecting spex-detach writes and verifies the exclude entries (US1)"
make_project '{"spex": true, "spex-gates": true, "spex-detach": false}'
add_detach_scripts git
run_apply "spex,spex-gates,spex-detach"
assert_eq "exit code 0" "0" "$RC"
assert_contains "reports Enabled: spex-detach" "Enabled: spex-detach" "$ERR"
assert_contains "entries written line" "Stealth mode: exclude entries written: .specify/ specs/ brainstorm/" "$ERR"
assert_contains "active line" "Stealth mode: active (verified: .specify/ specs/ brainstorm/)" "$ERR"
assert_not_contains "no repair on first enable" "Repaired" "$ERR"
assert_eq "stdout stays empty" "" "$OUT"
for e in .specify/ specs/ brainstorm/; do
  assert_eq "$e in exclude file" "1" "$(grep -cxF "$e" "$PROJ/$EXCLUDE_FILE_REL")"
done
assert_contains "summary line still printed" "Extensions: 1 enabled, 0 disabled, 1 unchanged" "$ERR"

echo "Test: a visible configured path warns and still exits 0 (US1)"
make_project '{"spex": true, "spex-gates": true, "spex-detach": false}'
add_detach_scripts git
mkdir -p "$PROJ/specs" && echo x > "$PROJ/specs/tracked.md"
git -C "$PROJ" add specs/tracked.md && git -C "$PROJ" commit -q -m tracked
run_apply "spex,spex-gates,spex-detach"
assert_eq "exit code 0" "0" "$RC"
assert_contains "warning" "WARNING: stealth mode is NOT fully active" "$ERR"
assert_contains "names the tracked path" "specs/ (tracked)" "$ERR"
assert_not_contains "no active line" "Stealth mode: active" "$ERR"

echo "Test: selecting spex-detach outside a git repository stays quiet (US1)"
make_project '{"spex": true, "spex-gates": true, "spex-detach": false}'
add_detach_scripts
run_apply "spex,spex-gates,spex-detach"
assert_eq "exit code 0" "0" "$RC"
assert_not_contains "no ERROR" "ERROR" "$ERR"
assert_not_contains "no stealth line" "tealth mode" "$ERR"
assert_contains "reports Enabled: spex-detach" "Enabled: spex-detach" "$ERR"

echo "Test: the was-enabled marker from spex-init.sh turns a write into a repair (FR-010)"
make_project '{"spex": true, "spex-gates": true, "spex-detach": false}'
add_detach_scripts git
: > "$PROJ/.specify/.spex-detach-was-enabled"
run_apply "spex,spex-gates,spex-detach"
assert_eq "exit code 0" "0" "$RC"
assert_contains "repair line" "Repaired stealth mode: added .specify/ specs/ brainstorm/" "$ERR"
assert_not_contains "no written line" "exclude entries written" "$ERR"
assert_eq "marker removed" "false" "$([ -e "$PROJ/.specify/.spex-detach-was-enabled" ] && echo true || echo false)"

# ─── US3: repair on refresh ───

# before_with_detach <true|false>: snapshot as taken before reinstalling
before_with_detach() {
  jq -n --argjson d "$1" '{schema_version: "1.0", extensions: {
    "spex": {enabled: true}, "spex-gates": {enabled: true}, "spex-detach": {enabled: $d}}}' > "$TMPROOT/before.json"
}

echo "Test: enabled before, all entries missing -> repair names every path (US3)"
make_project '{"spex": true, "spex-gates": true, "spex-detach": true}'
add_detach_scripts git
before_with_detach true
run_apply --before "$TMPROOT/before.json" "spex,spex-gates,spex-detach"
assert_eq "exit code 0" "0" "$RC"
assert_contains "repair line" "Repaired stealth mode: added .specify/ specs/ brainstorm/" "$ERR"
assert_contains "verified" "Stealth mode: active" "$ERR"
assert_not_contains "no Enabled: line" "Enabled: spex-detach" "$ERR"

echo "Test: enabled before, only specs/ missing -> repair names only specs/ (US3)"
make_project '{"spex": true, "spex-gates": true, "spex-detach": true}'
add_detach_scripts git
printf '%s\n' '# spex-detach: spec artifacts excluded from git' '.specify/' 'brainstorm/' > "$PROJ/$EXCLUDE_FILE_REL"
before_with_detach true
run_apply --before "$TMPROOT/before.json" "spex,spex-gates,spex-detach"
assert_eq "exit code 0" "0" "$RC"
assert_contains "repair names specs/" "Repaired stealth mode: added specs/" "$ERR"
assert_not_contains "repair names nothing else" "added specs/ " "$ERR"
assert_not_contains ".specify/ not re-added" "added .specify/" "$ERR"

echo "Test: enabled before, all entries present -> no repair, still verified (US3)"
run_apply --before "$TMPROOT/before.json" "spex,spex-gates,spex-detach"
assert_eq "exit code 0" "0" "$RC"
assert_not_contains "no repair line" "Repaired" "$ERR"
assert_contains "verified" "Stealth mode: active" "$ERR"

echo "Test: two runs leave each entry exactly once (US3)"
run_apply --before "$TMPROOT/before.json" "spex,spex-gates,spex-detach"
for e in .specify/ specs/ brainstorm/; do
  assert_eq "$e once" "1" "$(grep -cxF "$e" "$PROJ/$EXCLUDE_FILE_REL")"
done

# ─── US4: projects without detach are unaffected ───

echo "Test: selection without spex-detach leaves the exclude file alone (US4)"
make_project '{"spex": true, "spex-gates": true, "spex-detach": false}'
add_detach_scripts git
printf '%s\n' '*.log' > "$PROJ/$EXCLUDE_FILE_REL"
EXCL_BEFORE=$(shasum "$PROJ/$EXCLUDE_FILE_REL" | cut -d' ' -f1)
run_apply "spex,spex-gates"
assert_eq "exit code 0" "0" "$RC"
assert_not_contains "no stealth output" "tealth mode" "$ERR"
assert_eq "exclude file byte-identical" "$EXCL_BEFORE" "$(shasum "$PROJ/$EXCLUDE_FILE_REL" | cut -d' ' -f1)"

echo "Test: deselecting spex-detach keeps its entries and prints no stealth output (US4)"
make_project '{"spex": true, "spex-gates": true, "spex-detach": true}'
add_detach_scripts git
printf '%s\n' '# spex-detach: spec artifacts excluded from git' '.specify/' 'specs/' 'brainstorm/' > "$PROJ/$EXCLUDE_FILE_REL"
run_apply "spex,spex-gates"
assert_eq "exit code 0" "0" "$RC"
assert_contains "reports Disabled: spex-detach" "Disabled: spex-detach" "$ERR"
assert_not_contains "no stealth output" "tealth mode" "$ERR"
assert_eq "specs/ entry kept" "1" "$(grep -cxF specs/ "$PROJ/$EXCLUDE_FILE_REL")"

echo "Test: spex-detach enabled but its scripts missing -> no output, exit code unchanged (US4)"
make_project '{"spex": true, "spex-gates": true, "spex-detach": false}'
git -C "$PROJ" init -q
run_apply "spex,spex-gates,spex-detach"
assert_eq "exit code 0" "0" "$RC"
assert_not_contains "no stealth output" "tealth mode" "$ERR"
assert_contains "reports Enabled: spex-detach" "Enabled: spex-detach" "$ERR"

# ─── The before-snapshot decides between "written" and "repaired" ───
# In the setup workflow, install-ext-spex-detach disables spex-detach before
# apply-extensions runs, so the live registry says false and only --before
# knows whether it was enabled before this run.

echo "Test: registry disabled, snapshot enabled -> entries are a repair (FR-010)"
make_project '{"spex": true, "spex-gates": true, "spex-detach": false}'
add_detach_scripts git
before_with_detach true
run_apply --before "$TMPROOT/before.json" "spex,spex-gates,spex-detach"
assert_eq "exit code 0" "0" "$RC"
assert_contains "repair line" "Repaired stealth mode: added .specify/ specs/ brainstorm/" "$ERR"
assert_not_contains "no written line" "exclude entries written" "$ERR"

echo "Test: registry disabled, snapshot disabled -> entries are written, not repaired (US1-4)"
make_project '{"spex": true, "spex-gates": true, "spex-detach": false}'
add_detach_scripts git
before_with_detach false
run_apply --before "$TMPROOT/before.json" "spex,spex-gates,spex-detach"
assert_eq "exit code 0" "0" "$RC"
assert_contains "written line" "Stealth mode: exclude entries written: .specify/ specs/ brainstorm/" "$ERR"
assert_not_contains "no repair line" "Repaired" "$ERR"
assert_contains "verified" "Stealth mode: active" "$ERR"

# ─── A failing ensure is reported, never silent ───

echo "Test: ensure crashing without a result prints a warning, exit code unchanged (R7)"
make_project '{"spex": true, "spex-gates": true, "spex-detach": false}'
add_detach_scripts git
printf '#!/bin/sh\necho "ERROR: No Python interpreter found" >&2\nexit 1\n' \
  > "$PROJ/.specify/extensions/spex-detach/scripts/spex-detach.sh"
run_apply "spex,spex-gates,spex-detach"
assert_eq "exit code 0" "0" "$RC"
assert_contains "warning line" "WARNING: stealth mode is NOT fully active. The exclude entries could not be written or verified:" "$ERR"
assert_contains "names the exit code and the error" "  spex-detach.sh ensure failed with exit code 1: ERROR: No Python interpreter found" "$ERR"
assert_not_contains "no active line" "Stealth mode: active" "$ERR"

echo "Test: a visible path (exit 1 with a result) is not reported as a failed ensure (R7)"
make_project '{"spex": true, "spex-gates": true, "spex-detach": false}'
add_detach_scripts git
mkdir -p "$PROJ/specs" && echo x > "$PROJ/specs/t.md"
git -C "$PROJ" add specs/t.md
run_apply "spex,spex-gates,spex-detach"
assert_eq "exit code 0" "0" "$RC"
assert_contains "visible-path warning" "  specs/ (tracked)" "$ERR"
assert_not_contains "no failed-ensure line" "could not be written or verified" "$ERR"

echo "Test: outside a git repository (exit 2) no failed-ensure warning (R7)"
make_project '{"spex": true, "spex-gates": true, "spex-detach": false}'
add_detach_scripts
run_apply "spex,spex-gates,spex-detach"
assert_eq "exit code 0" "0" "$RC"
assert_not_contains "no stealth output" "tealth mode" "$ERR"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
