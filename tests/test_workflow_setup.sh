#!/usr/bin/env bash
set -euo pipefail

# Isolate git from the developer's global configuration: a global excludes
# file (core.excludesFile, or the default ~/.config/git/ignore) would change
# what git reports as ignored in the stealth-mode checks below.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.excludesFile GIT_CONFIG_VALUE_0=/dev/null

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_REPO="$(mktemp -d "${TMPDIR:-/tmp}/spex-workflow-setup.XXXXXX")"
LEGACY_REPO="$(mktemp -d "${TMPDIR:-/tmp}/spex-workflow-legacy.XXXXXX")"
CODEX_REPO="$(mktemp -d "${TMPDIR:-/tmp}/spex-workflow-codex.XXXXXX")"
trap 'rm -rf -- "$TEST_REPO" "$LEGACY_REPO" "$CODEX_REPO"' EXIT
git -C "$TEST_REPO" init -q
git -C "$LEGACY_REPO" init -q
git -C "$CODEX_REPO" init -q

run_setup() {
  (
    cd "$TEST_REPO"
    SPEX_SOURCE="$REPO_ROOT/spex" specify workflow run "$REPO_ROOT/spex/setup.yml" --json "$@"
  )
}

initial="$(run_setup \
  -i integration=claude \
  -i extensions=spex-gates,spex-worktrees \
  -i security=autonomous)"
jq -e '.status == "completed"' <<<"$initial" >/dev/null

profile="$TEST_REPO/.specify/spex.json"
jq -e '
  .schema_version == 1 and .harness == "claude" and
  .security == "autonomous" and
  .extensions == ["spex", "spex-gates", "spex-worktrees"]
' "$profile" >/dev/null
before="$(shasum -a 256 "$profile" | awk '{print $1}')"

refresh="$(run_setup)"
jq -e '.status == "completed"' <<<"$refresh" >/dev/null
after="$(shasum -a 256 "$profile" | awk '{print $1}')"
[[ "$before" == "$after" ]]

legacy="$({
  cd "$LEGACY_REPO"
  SPEX_SOURCE="$REPO_ROOT/spex" specify workflow run "$REPO_ROOT/spex/setup.yml" --json \
    -i integration=claude -i extensions=recommended -i permissions=standard
})"
jq -e '.status == "completed"' <<<"$legacy" >/dev/null
jq -e '.security == "autonomous"' "$LEGACY_REPO/.specify/spex.json" >/dev/null

mkdir -p "$CODEX_REPO/.codex"
printf '%s\n' 'approval_policy = "on-request"' > "$CODEX_REPO/.codex/config.toml"
codex_refusal="$({
  cd "$CODEX_REPO"
  SPEX_SOURCE="$REPO_ROOT/spex" specify workflow run "$REPO_ROOT/spex/setup.yml" --json \
    -i integration=codex -i extensions=recommended -i security=yolo
} || true)"
jq -e '.status == "failed" and .current_step_id == "codex-project"' \
  <<<"$codex_refusal" >/dev/null

if find "$TEST_REPO" "$CODEX_REPO" -maxdepth 2 -type d -name '*materializ*' | grep -q .; then
  echo "FAIL: workflow setup created a staged distribution" >&2
  exit 1
fi

echo "PASS: workflow setup persists intent, migrates legacy permissions, propagates Codex refusal, and refreshes without materialization"

# --- Helpers for the cases below -------------------------------------------

SCRATCH_RAW="$(mktemp -d "${TMPDIR:-/tmp}/spex-workflow-cases.XXXXXX")" || exit 1
SCRATCH="$(cd "$SCRATCH_RAW" && pwd -P)" || exit 1
[ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && [ "$SCRATCH" != "$(pwd -P)" ] || { echo "cannot create a temporary directory" >&2; exit 1; }
TMP_COPY=""
trap 'rm -rf -- "$TEST_REPO" "$LEGACY_REPO" "$CODEX_REPO" "$SCRATCH" ${TMP_COPY:+"$TMP_COPY"}' EXIT
ALL_SPEX_EXTENSIONS="spex spex-gates spex-worktrees spex-deep-review spex-teams spex-collab spex-detach"
OPTIONAL_SPEX_EXTENSIONS="spex-gates spex-worktrees spex-deep-review spex-teams spex-collab spex-detach"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# new_project <name>: prints the path of a fresh git project under SCRATCH.
new_project() {
  local dir="$SCRATCH/$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  printf '%s' "$dir"
}

# setup_in <project> <source> [-i k=v ...]: runs the setup workflow from
# <source> inside <project>. Prints the workflow JSON on stdout; stderr goes
# to <project>.log. Returns the workflow exit code.
setup_in() {
  local project="$1" source="$2"
  shift 2
  [ -n "$project" ] && [ -d "$project" ] || fail "project directory missing: $project"
  (
    cd "$project" || exit 1
    SPEX_SOURCE="$source" specify workflow run "$source/setup.yml" --json "$@"
  ) 2> "$project.log"
}

# enabled_optional <project>: comma-separated optional spex extensions that
# the registry shows enabled, in canonical order.
enabled_optional() {
  local registry="$1/.specify/extensions/.registry" ext result=""
  for ext in $OPTIONAL_SPEX_EXTENSIONS; do
    if jq -e --arg id "$ext" '.extensions[$id].enabled == true' "$registry" >/dev/null 2>&1; then
      result="${result:+$result,}$ext"
    fi
  done
  printf '%s' "$result"
}

# declared_optional <project>: optional extensions in .specify/spex.json.
declared_optional() {
  jq -r '[.extensions[] | select(. != "spex")] | join(",")' "$1/.specify/spex.json"
}

assert_completed() {
  jq -e '.status == "completed"' <<<"$2" >/dev/null ||
    fail "$1: workflow did not complete: $(jq -c '{status, current_step_id}' <<<"$2" 2>/dev/null || printf '%s' "$2")"
}

assert_enabled() {
  local desc="$1" project="$2" expected="$3" actual
  actual="$(enabled_optional "$project")"
  [ "$actual" = "$expected" ] || fail "$desc: enabled '$actual', expected '$expected'"
  [ "$(declared_optional "$project")" = "$actual" ] ||
    fail "$desc: declaration '$(declared_optional "$project")' differs from enabled '$actual'"
}

# --- US2: setup from a temporary source (FR-001, FR-002) --------------------

# tmp_source_case <label> <TMPDIR value>
tmp_source_case() {
  local label="$1" tmpdir="$2" copy project out ext dangling
  mkdir -p "$tmpdir"
  # Build the path exactly like "${TMPDIR:-/tmp}/..." does. With a macOS-style
  # TMPDIR that ends in a slash this yields ".../T//spex-src-*", the shape the
  # old temp-path exception matched (and then installed without --dev).
  copy="$(TMPDIR="$tmpdir" mktemp -d "$tmpdir/spex-src-XXXXXX")"
  TMP_COPY="$copy"
  case "$copy" in "$tmpdir"/spex-src-*) ;; *) fail "$label: copy not under $tmpdir: $copy" ;; esac
  cp -R "$REPO_ROOT/spex/." "$copy/"
  project="$(new_project "tmp-source-$label")"

  out="$(TMPDIR="$tmpdir" setup_in "$project" "$copy" \
    -i integration=claude -i extensions=recommended -i security=safe)" ||
    fail "$label: setup from $copy failed: $(cat "$project.log")"
  assert_completed "$label" "$out"
  for ext in $ALL_SPEX_EXTENSIONS; do
    [ -f "$project/.specify/extensions/$ext/extension.yml" ] ||
      fail "$label: extension $ext not installed from $copy"
  done

  rm -rf -- "$copy"
  TMP_COPY=""
  for ext in $ALL_SPEX_EXTENSIONS; do
    [ -f "$project/.specify/extensions/$ext/extension.yml" ] ||
      fail "$label: extension $ext gone after deleting the source"
  done
  ls "$project"/.claude/skills/speckit-spex-*/SKILL.md >/dev/null 2>&1 ||
    fail "$label: no generated spex command skills"
  dangling="$(find "$project/.claude" "$project/.specify" -type l ! -exec test -e {} \; -print)"
  [ -z "$dangling" ] || fail "$label: dangling symlinks after deleting the source: $dangling"
  if find "$project/.claude" "$project/.specify" -type l -exec readlink {} \; | grep -qF "$copy"; then
    fail "$label: symlinks still point into the deleted source $copy"
  fi
  echo "PASS: setup from a source under $label installs all 7 extensions and survives deleting it"
}

tmp_source_case "tmp" "/tmp"
tmp_source_case "macos-tmpdir" "$SCRATCH/var/folders/xx/T/"

# --- US3: the selection is exactly what ends up enabled (FR-003 to FR-005) --

SRC="$REPO_ROOT/spex"
RECOMMENDED_SET="spex-gates,spex-worktrees,spex-deep-review"
ALL_SET="spex-gates,spex-worktrees,spex-deep-review,spex-teams,spex-collab"

# run_case <desc> <project> [-i k=v ...]: runs setup and stores the run's
# output in RUN_OUTPUT: stdout, stderr, and the step messages that the
# workflow engine keeps in the run state (printed by spex-setup-report.sh,
# which is how the bootstrap and spex-init.sh surface them).
run_case() {
  local desc="$1" project="$2" out run_id report
  shift 2
  out="$(setup_in "$project" "$SRC" "$@")" || fail "$desc: setup failed: $(cat "$project.log")"
  assert_completed "$desc" "$out"
  run_id="$(jq -r '.run_id' <<<"$out")"
  report="$(cd "$project" && sh "$SRC/scripts/spex-setup-report.sh" "$run_id" 2>&1)"
  for leftover in .specify/extensions/.registry.before .specify/.spex-extensions-reply .specify/.spex-security-reply; do
    [ ! -e "$project/$leftover" ] || fail "$desc: $leftover left behind"
  done
  RUN_OUTPUT="$out
$(cat "$project.log")
$report"
}

profile_hash() {
  shasum -a 256 "$1/.specify/spex.json" | awk '{print $1}'
}

# recommended, then a refresh without input
rec="$(new_project select-recommended)"
run_case "recommended" "$rec" -i integration=claude -i extensions=recommended -i security=safe
assert_enabled "recommended" "$rec" "$RECOMMENDED_SET"
rec_hash="$(profile_hash "$rec")"
run_case "refresh after recommended" "$rec"
assert_enabled "refresh after recommended" "$rec" "$RECOMMENDED_SET"
[ "$(profile_hash "$rec")" = "$rec_hash" ] || fail "refresh after recommended changed .specify/spex.json"
echo "PASS: recommended enables exactly gates, worktrees, deep-review; a refresh re-applies it unchanged"

# An invalid selection stops setup before anything is changed.
rec_registry="$(shasum -a 256 "$rec/.specify/extensions/.registry" | awk '{print $1}')"
bad_out="$(setup_in "$rec" "$SRC" -i extensions=spex-gates,spex-bogus)" && fail "invalid selection: setup succeeded"
jq -e '.status == "failed"' <<<"$bad_out" >/dev/null || fail "invalid selection: unexpected result $bad_out"
[ "$(shasum -a 256 "$rec/.specify/extensions/.registry" | awk '{print $1}')" = "$rec_registry" ] ||
  fail "invalid selection: the registry changed"
[ "$(profile_hash "$rec")" = "$rec_hash" ] || fail "invalid selection: .specify/spex.json changed"
[ ! -e "$rec/.specify/extensions/.registry.before" ] || fail "invalid selection: registry snapshot left behind"
bad_report="$(cd "$rec" && sh "$SRC/scripts/spex-setup-report.sh" "$(jq -r '.run_id' <<<"$bad_out")" 2>&1)"
printf '%s' "$bad_report" | grep -qF "spex-bogus" || fail "invalid selection: the unknown name is not reported: $bad_report"
echo "PASS: an invalid explicit selection stops setup (resolve-request) with the unknown name and leaves the project unchanged"

# explicit list with a dependency
teams="$(new_project select-teams)"
run_case "explicit spex-teams" "$teams" -i integration=claude -i extensions=spex-teams -i security=safe
assert_enabled "explicit spex-teams" "$teams" "spex-gates,spex-teams"
echo "PASS: an explicit list enables only the listed extensions plus spex-gates"

# all, then a legacy declaration with spex-detach, then recommended
all="$(new_project select-all)"
run_case "all" "$all" -i integration=claude -i extensions=all -i security=safe
assert_enabled "all" "$all" "$ALL_SET"
echo "PASS: all enables every optional extension except spex-detach"

# Simulate a declaration written by an earlier `all` run (spex-detach listed
# while the registry has it disabled).
jq '.extensions += ["spex-detach"]' "$all/.specify/spex.json" > "$all/.specify/spex.json.new"
mv "$all/.specify/spex.json.new" "$all/.specify/spex.json"
jq -e '.extensions["spex-detach"].enabled == false' "$all/.specify/extensions/.registry" >/dev/null ||
  fail "legacy fixture: spex-detach should be disabled before the refresh"
run_case "legacy spex-detach refresh" "$all"
jq -e '.extensions["spex-detach"].enabled == false' "$all/.specify/extensions/.registry" >/dev/null ||
  fail "legacy refresh enabled spex-detach"
jq -e '.extensions | index("spex-detach") == null' "$all/.specify/spex.json" >/dev/null ||
  fail "legacy refresh kept spex-detach in .specify/spex.json"
printf '%s' "$RUN_OUTPUT" | grep -qF "Migrated: removed spex-detach" || fail "legacy refresh did not report the migration: $RUN_OUTPUT"
assert_enabled "legacy spex-detach refresh" "$all" "$ALL_SET"
echo "PASS: a legacy declaration drops spex-detach instead of enabling it, and says so"

run_case "all then recommended" "$all" -i extensions=recommended
assert_enabled "all then recommended" "$all" "$RECOMMENDED_SET"
for ext in spex-teams spex-collab; do
  printf '%s' "$RUN_OUTPUT" | grep -qF "Disabled: $ext" || fail "all then recommended: no 'Disabled: $ext' in output: $RUN_OUTPUT"
done
echo "PASS: switching from all to recommended disables teams and collab and names both"

# spex-worktrees as the last selected extension still gets the git extension
# (the selection is matched as ",<list>,", so it must carry no newline).
wt="$(new_project select-worktrees-last)"
run_case "gates and worktrees" "$wt" -i integration=claude -i extensions=spex-gates,spex-worktrees -i security=safe
assert_enabled "gates and worktrees" "$wt" "spex-gates,spex-worktrees"
jq -e '.extensions.git.enabled == true' "$wt/.specify/extensions/.registry" >/dev/null ||
  fail "gates and worktrees: the git extension was not enabled for spex-worktrees"
echo "PASS: selecting spex-worktrees last still enables the git extension"

# --- spex-detach: stealth mode written, verified, kept and repaired ---------

det="$(new_project select-detach)"
det_config="$det/.specify/extensions/spex-detach/spex-detach-config.yml"
det_exclude="$det/.git/info/exclude"
det_hash() { shasum -a 256 "$det_config" | awk '{print $1}'; }
run_case "detach selected" "$det" -i integration=claude -i extensions=spex-detach -i security=safe
assert_enabled "detach selected" "$det" "spex-detach"
for line in "Enabled: spex-detach" "Stealth mode: exclude entries written: .specify/ specs/ brainstorm/" "Stealth mode: active (verified:"; do
  printf '%s' "$RUN_OUTPUT" | grep -qF "$line" || fail "detach selected: no '$line' in output: $RUN_OUTPUT"
done
for probe in specs/x/spec.md .specify/spex.json .specify/memory/constitution.md brainstorm/x.md; do
  git -C "$det" check-ignore -q -- "$probe" || fail "detach selected: git does not ignore $probe"
done
for e in .specify/ specs/ brainstorm/; do
  [ "$(grep -cxF -- "$e" "$det_exclude")" = 1 ] || fail "detach selected: $e is not in the local exclude file exactly once"
done
# The refresh keeps a saved copy instead of overwriting it only when the live
# config equals the template, so the installed config must be the template.
cmp -s "$det_config" "$SRC/extensions/spex-detach/config-template.yml" ||
  fail "detach selected: the installed config differs from config-template.yml"
echo "PASS: selecting spex-detach writes and verifies the exclude entries; declaration and constitution are ignored"

yq -i '.archive.path = "/tmp/x-specs" | .archive.auto_commit = false' "$det_config"
det_before="$(det_hash)"
run_case "detach refresh" "$det"
[ "$(det_hash)" = "$det_before" ] || fail "detach refresh: the detach configuration changed"
[ ! -e "$det/.specify/.spex-detach-config.saved.yml" ] || fail "detach refresh: saved config copy left behind"
echo "PASS: a refresh keeps the customized detach configuration byte-identical"

grep -vxF 'specs/' "$det_exclude" > "$det_exclude.new" && mv "$det_exclude.new" "$det_exclude"
run_case "detach repair" "$det"
printf '%s' "$RUN_OUTPUT" | grep -qF "Repaired stealth mode: added specs/" ||
  fail "detach repair: no repair reported: $RUN_OUTPUT"
run_case "detach second refresh" "$det"
if printf '%s' "$RUN_OUTPUT" | grep -qF "Repaired stealth mode"; then
  fail "detach second refresh: repaired again"
fi
for e in .specify/ specs/ brainstorm/; do
  [ "$(grep -cxF -- "$e" "$det_exclude")" = 1 ] || fail "detach second refresh: $e is not in the exclude file exactly once"
done
[ "$(det_hash)" = "$det_before" ] || fail "detach second refresh: the detach configuration changed"
echo "PASS: a refresh repairs a missing exclude entry once, and a second refresh adds nothing"

run_case "detach left out" "$det" -i extensions=spex-gates
assert_enabled "detach left out" "$det" "spex-gates"
[ "$(det_hash)" = "$det_before" ] || fail "detach left out: the disabled detach configuration changed"
if printf '%s' "$RUN_OUTPUT" | grep -qF "tealth mode"; then
  fail "detach left out: stealth-mode output without spex-detach: $RUN_OUTPUT"
fi
echo "PASS: a refresh that leaves spex-detach out keeps its configuration and prints no stealth-mode output"

# The verification runs after spex's own exclude rules are written, so what
# it reports matches the final exclude file (SC-002): with a glob entry for
# .specify/, an "active" report must mean git still ignores the files the spex
# rules re-include.
glob="$(new_project detach-glob)"
glob_exclude="$glob/.git/info/exclude"
run_case "detach glob" "$glob" -i integration=claude -i extensions=spex-detach -i security=safe
yq -i '.exclude.paths = [".specify/**", "specs/", "brainstorm/"]' "$glob/.specify/extensions/spex-detach/spex-detach-config.yml"
: > "$glob_exclude"
run_case "detach glob refresh" "$glob"
printf '%s' "$RUN_OUTPUT" | grep -qF "Stealth mode: active" ||
  fail "detach glob refresh: no 'Stealth mode: active' line: $RUN_OUTPUT"
for probe in .specify/spex.json .specify/memory/constitution.md specs/x.md; do
  git -C "$glob" check-ignore -q -- "$probe" ||
    fail "detach glob refresh: stealth mode reported active, but git does not ignore $probe: $(cat "$glob_exclude")"
done
echo "PASS: with a glob entry, an active stealth-mode report matches the final exclude rules"

# --- spex-detach config preservation under failures (FR-009, R11, R13) ------
#
# Failure injection: a read-only .specify/ would also break the workflow
# engine's own run state (.specify/workflows/runs), so the save failure is
# injected by making the live config unreadable (cp fails, nothing else is
# touched). The add and restore failures come from a specify wrapper that
# fails `extension add .../spex-detach`, or makes the freshly added
# extension directory read-only so the restore cannot move the config back.
fails="$(new_project detach-failures)"
fails_config="$fails/.specify/extensions/spex-detach/spex-detach-config.yml"
fails_saved="$fails/.specify/.spex-detach-config.saved.yml"
fails_registry="$fails/.specify/extensions/.registry"
fails_hash() { shasum -a 256 "$1" | awk '{print $1}'; }
run_case "detach failures setup" "$fails" -i integration=claude -i extensions=spex-detach -i security=safe
yq -i '.archive.path = "../fails-specs" | .archive.auto_commit = false' "$fails_config"
user_hash="$(fails_hash "$fails_config")"

registry_before="$(fails_hash "$fails_registry")"
chmod 000 "$fails_config"
save_out="$(setup_in "$fails" "$SRC")" && fail "detach save failure: setup succeeded"
chmod 644 "$fails_config"
jq -e '.status == "failed" and .current_step_id == "save-detach-config"' <<<"$save_out" >/dev/null ||
  fail "detach save failure: unexpected result $save_out"
save_report="$(cd "$fails" && sh "$SRC/scripts/spex-setup-report.sh" "$(jq -r '.run_id' <<<"$save_out")" 2>&1)"
printf '%s' "$save_report" | grep -qF "ERROR: cannot save .specify/extensions/spex-detach/spex-detach-config.yml" ||
  fail "detach save failure: the error does not name the config file: $save_report"
[ "$(fails_hash "$fails_config")" = "$user_hash" ] || fail "detach save failure: the config changed"
[ "$(fails_hash "$fails_registry")" = "$registry_before" ] || fail "detach save failure: the registry changed"
[ ! -e "$fails_saved" ] || fail "detach save failure: a saved copy was written"
echo "PASS: a failed config save stops the workflow at save-detach-config, names the file and changes nothing"

REAL_SPECIFY="$(command -v specify)"
FAIL_BIN="$SCRATCH/detach-fail-bin"
mkdir -p "$FAIL_BIN"
cat > "$FAIL_BIN/specify" <<STUB
#!/usr/bin/env bash
detach_add=false
if [ "\${1:-} \${2:-}" = "extension add" ] && [ "\${3%/spex-detach}" != "\${3:-}" ]; then
  detach_add=true
fi
if [ "\$detach_add" = true ] && [ "\${DETACH_FAIL_MODE:-}" = add ]; then
  echo "spex-detach add failed in this test" >&2
  exit 1
fi
"$REAL_SPECIFY" "\$@"
rc=\$?
if [ "\$detach_add" = true ] && [ "\$rc" -eq 0 ] && [ "\${DETACH_FAIL_MODE:-}" = restore ]; then
  chmod a-w .specify/extensions/spex-detach
fi
exit \$rc
STUB
chmod +x "$FAIL_BIN/specify"

add_out="$(DETACH_FAIL_MODE=add PATH="$FAIL_BIN:$PATH" setup_in "$fails" "$SRC")" &&
  fail "detach add failure: setup succeeded"
jq -e '.status == "failed" and .current_step_id == "install-ext-spex-detach"' <<<"$add_out" >/dev/null ||
  fail "detach add failure: the failed add did not stop the step: $add_out"
[ -f "$fails_saved" ] && [ "$(fails_hash "$fails_saved")" = "$user_hash" ] ||
  fail "detach add failure: the saved copy is missing or not the user config"
run_case "detach add failure recovery" "$fails"
[ "$(fails_hash "$fails_config")" = "$user_hash" ] || fail "detach add failure recovery: the user config was not restored"
[ ! -e "$fails_saved" ] || fail "detach add failure recovery: saved copy left behind"
echo "PASS: a failed spex-detach add stops the step, keeps the saved config, and the next run restores it"

# Enabled before: a failed restore leaves it enabled, so the next refresh
# keeps spex-detach in the declaration instead of dropping it as legacy.
restore_out="$(DETACH_FAIL_MODE=restore PATH="$FAIL_BIN:$PATH" setup_in "$fails" "$SRC")" &&
  fail "detach restore failure: setup succeeded"
chmod u+w "$fails/.specify/extensions/spex-detach"
jq -e '.status == "failed" and .current_step_id == "install-ext-spex-detach"' <<<"$restore_out" >/dev/null ||
  fail "detach restore failure: unexpected result $restore_out"
jq -e '.extensions["spex-detach"].enabled == true' "$fails_registry" >/dev/null ||
  fail "detach restore failure: spex-detach was enabled before but is not now: $(jq -c '.extensions["spex-detach"]' "$fails_registry")"
[ "$(fails_hash "$fails_saved")" = "$user_hash" ] || fail "detach restore failure: the saved copy is not the user config"
run_case "detach restore failure recovery" "$fails"
[ "$(fails_hash "$fails_config")" = "$user_hash" ] ||
  fail "detach restore failure recovery: the template replaced the user config"
assert_enabled "detach restore failure recovery" "$fails" "spex-detach"
echo "PASS: a failed restore keeps an enabled spex-detach enabled, and the next run restores the user config"

# Disabled before: a failed restore must not switch stealth mode on
# (disable runs before the restore).
run_case "detach left out before restore failure" "$fails" -i extensions=spex-gates
jq -e '.extensions["spex-detach"].enabled == false' "$fails_registry" >/dev/null ||
  fail "detach left out before restore failure: spex-detach still enabled"
restore_off_out="$(DETACH_FAIL_MODE=restore PATH="$FAIL_BIN:$PATH" setup_in "$fails" "$SRC")" &&
  fail "detach restore failure (disabled): setup succeeded"
chmod u+w "$fails/.specify/extensions/spex-detach"
jq -e '.status == "failed" and .current_step_id == "install-ext-spex-detach"' <<<"$restore_off_out" >/dev/null ||
  fail "detach restore failure (disabled): unexpected result $restore_off_out"
jq -e '.extensions["spex-detach"].enabled == false' "$fails_registry" >/dev/null ||
  fail "detach restore failure (disabled): the failed run switched spex-detach on"
[ "$(fails_hash "$fails_saved")" = "$user_hash" ] || fail "detach restore failure (disabled): the saved copy is not the user config"
echo "PASS: a failed restore never switches a disabled spex-detach on and keeps the saved config"

# Without an obtainable git extension, setup stops with the FR-019 guidance.
REAL_SPECIFY="$(command -v specify)"
NOGIT_BIN="$SCRATCH/nogit-bin"
mkdir -p "$NOGIT_BIN"
cat > "$NOGIT_BIN/specify" <<STUB
#!/usr/bin/env bash
case "\${1:-} \${2:-} \${3:-}" in
  "extension add git"|"extension enable git")
    echo "git extension unavailable in this test" >&2
    exit 1 ;;
esac
exec "$REAL_SPECIFY" "\$@"
STUB
chmod +x "$NOGIT_BIN/specify"
nogit="$(new_project worktrees-without-git)"
nogit_out="$(PATH="$NOGIT_BIN:$PATH" setup_in "$nogit" "$SRC" \
  -i integration=claude -i extensions=spex-gates,spex-worktrees -i security=safe)" &&
  fail "worktrees without git: setup succeeded"
jq -e '.status == "failed" and .current_step_id == "enforce-git-extension"' <<<"$nogit_out" >/dev/null ||
  fail "worktrees without git: unexpected result $nogit_out"
nogit_report="$(cd "$nogit" && sh "$SRC/scripts/spex-setup-report.sh" "$(jq -r '.run_id' <<<"$nogit_out")" 2>&1)"
printf '%s' "$nogit_report" | grep -qF "spex-worktrees requires the spec-kit git extension" ||
  fail "worktrees without git: no error in the report: $nogit_report"
printf '%s' "$nogit_report" | grep -qF "leaves out spex-worktrees" ||
  fail "worktrees without git: no FR-019 guidance in the report: $nogit_report"
if printf '%s' "$nogit_report" | grep -qF "extension disable spex-worktrees"; then
  fail "worktrees without git: the report suggests disabling spex-worktrees by hand"
fi
[ ! -e "$nogit/.specify/spex.json" ] || fail "worktrees without git: a declaration was written"
echo "PASS: without the git extension, setup stops before persisting and prints the FR-019 guidance"

# --- Spec 061: permission rules (FR-002, FR-004, FR-010) --------------------

LEGACY_RULES_JQ='[.permissions.allow[] | select(. == "Bash(*)" or . == "Read(*)" or . == "Edit(*)" or . == "Write(*)")] | length == 0'

# YOLO writes bare Bash, Read, Edit and Write, once each.
yolo="$(new_project permissions-yolo)"
run_case "yolo permissions" "$yolo" -i integration=claude -i extensions=recommended -i security=yolo
yolo_settings="$yolo/.claude/settings.json"
jq -e '.permissions.defaultMode == "bypassPermissions"' "$yolo_settings" >/dev/null ||
  fail "yolo permissions: defaultMode is not bypassPermissions: $(cat "$yolo_settings")"
for tool in Bash Read Edit Write; do
  jq -e --arg t "$tool" '[.permissions.allow[] | select(. == $t)] | length == 1' "$yolo_settings" >/dev/null ||
    fail "yolo permissions: '$tool' is not in the allow list exactly once: $(cat "$yolo_settings")"
done
jq -e "$LEGACY_RULES_JQ" "$yolo_settings" >/dev/null ||
  fail "yolo permissions: a Tool(*) form was written: $(cat "$yolo_settings")"
printf '%s' "$RUN_OUTPUT" | grep -qE "Permissions configured in \.claude/settings\.json \([0-9]+ rules added\)" ||
  fail "yolo permissions: the setup report does not show the apply result: $RUN_OUTPUT"
echo "PASS: security=yolo writes bare Bash, Read, Edit, Write and no Tool(*) forms"

# security=safe adds no rules but still migrates legacy ones, in both files,
# and the setup report relays the Migrated lines.
safe="$(new_project permissions-safe-legacy)"
mkdir -p "$safe/.claude"
printf '%s' '{"permissions":{"defaultMode":"bypassPermissions","allow":["Bash(*)","Read(*)","Edit(*)","Write(*)","Bash(npm test)"]},"hooks":{"Stop":[]}}' \
  > "$safe/.claude/settings.json"
printf '%s' '{"permissions":{"allow":["Read(*)","Skill"]}}' > "$safe/.claude/settings.local.json"
run_case "safe with legacy permissions" "$safe" -i integration=claude -i extensions=recommended -i security=safe
[ "$(jq -c '.permissions.allow' "$safe/.claude/settings.json")" = '["Bash","Read","Edit","Write","Bash(npm test)"]' ] ||
  fail "safe with legacy permissions: settings.json not migrated: $(cat "$safe/.claude/settings.json")"
jq -e '.hooks == {"Stop": []} and .permissions.defaultMode == "bypassPermissions"' "$safe/.claude/settings.json" >/dev/null ||
  fail "safe with legacy permissions: other keys changed: $(cat "$safe/.claude/settings.json")"
[ "$(jq -c '.permissions.allow' "$safe/.claude/settings.local.json")" = '["Read","Skill"]' ] ||
  fail "safe with legacy permissions: settings.local.json not migrated: $(cat "$safe/.claude/settings.local.json")"
safe_report="$(cd "$safe" && sh "$SRC/scripts/spex-setup-report.sh" 2>&1)"
printf '%s' "$safe_report" | grep -qF "Migrated: .claude/settings.json permissions: Bash(*) -> Bash, Read(*) -> Read, Edit(*) -> Edit, Write(*) -> Write" ||
  fail "safe with legacy permissions: the setup report misses the settings.json Migrated line: $safe_report"
printf '%s' "$safe_report" | grep -qF "Migrated: .claude/settings.local.json permissions: Read(*) -> Read" ||
  fail "safe with legacy permissions: the setup report misses the settings.local.json Migrated line: $safe_report"
if printf '%s' "$safe_report" | grep -qF "Permissions configured"; then
  fail "safe with legacy permissions: rules were applied for security=safe: $safe_report"
fi
safe_hash="$(shasum -a 256 "$safe/.claude/settings.json" | awk '{print $1}')"
run_case "refresh after the migration" "$safe"
[ "$(shasum -a 256 "$safe/.claude/settings.json" | awk '{print $1}')" = "$safe_hash" ] ||
  fail "refresh after the migration: settings.json changed again"
if printf '%s' "$RUN_OUTPUT" | grep -qF "Migrated: .claude/settings"; then
  fail "refresh after the migration: a second migration was reported: $RUN_OUTPUT"
fi
echo "PASS: security=safe migrates legacy rules in both settings files, the report shows it, and a refresh is a no-op"

# A non-Claude harness still repairs existing Claude settings (spec 061 edge
# case), because migrate-permissions runs outside the harness switch.
codexperm="$(new_project permissions-codex-legacy)"
mkdir -p "$codexperm/.claude"
printf '%s' '{"permissions":{"allow":["Read(*)","Skill"]}}' > "$codexperm/.claude/settings.json"
run_case "codex with legacy permissions" "$codexperm" -i integration=codex -i extensions=recommended -i security=safe
[ "$(jq -c '.permissions.allow' "$codexperm/.claude/settings.json")" = '["Read","Skill"]' ] ||
  fail "codex with legacy permissions: settings.json not migrated: $(cat "$codexperm/.claude/settings.json")"
codex_report="$(cd "$codexperm" && sh "$SRC/scripts/spex-setup-report.sh" 2>&1)"
printf '%s' "$codex_report" | grep -qF "Migrated: .claude/settings.json permissions: Read(*) -> Read" ||
  fail "codex with legacy permissions: the setup report misses the Migrated line: $codex_report"
echo "PASS: a Codex setup run migrates legacy rules in existing Claude settings"

# --- US1: $cc-spex-init from a bundled plugin copy without network (SC-001) --

PLUGIN_COPY="$SCRATCH/codex-cache/cc-spex/current"
mkdir -p "$PLUGIN_COPY"
cp -R "$REPO_ROOT/spex/." "$PLUGIN_COPY/"
NET_BIN="$SCRATCH/net-bin"
NET_LOG="$SCRATCH/network.log"
CODEX_TMP="$SCRATCH/codex-tmp"
mkdir -p "$NET_BIN" "$CODEX_TMP"
: > "$NET_LOG"
REAL_GIT="$(command -v git)"
cat > "$NET_BIN/git" <<STUB
#!/usr/bin/env bash
# Skip git's global options so "git -C dir clone" is caught as well; the
# original arguments are kept for the real git.
original=("\$@")
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    -C|-c|--git-dir|--work-tree|--namespace|--exec-path) shift 2 ;;
    -*) shift ;;
    *) break ;;
  esac
done
case "\${1:-}" in
  clone|fetch|ls-remote)
    printf 'git %s\n' "\${original[*]}" >> "$NET_LOG"
    echo "network disabled in tests" >&2
    exit 128 ;;
esac
exec "$REAL_GIT" "\${original[@]}"
STUB
cat > "$NET_BIN/curl" <<STUB
#!/usr/bin/env bash
printf 'curl %s\n' "\$*" >> "$NET_LOG"
exit 7
STUB
chmod +x "$NET_BIN/git" "$NET_BIN/curl"

codex="$(new_project codex-bundled)"
[ ! -e "$codex/spex" ] || fail "codex project must not look like the cc-spex repository"
codex_out="$(
  cd "$codex" || exit 1
  env -u SPEX_SOURCE TMPDIR="$CODEX_TMP" PATH="$NET_BIN:$PATH" \
    sh "$PLUGIN_COPY/codex/skills/cc-spex-init/scripts/bootstrap.sh" 2> "$codex.log"
)" || fail "bundled bootstrap failed: $(cat "$codex.log")"
assert_completed "bundled bootstrap" "$codex_out"
codex_ship="$codex/.agents/skills/speckit-spex-ship/SKILL.md"
grep -qF 'Call `update_plan`' "$codex_ship" ||
  fail "bundled bootstrap: generated ship skill lacks native progress instructions"
if grep -qE '\{/?harness:' "$codex_ship"; then
  fail "bundled bootstrap: generated ship skill contains unresolved harness markers"
fi
grep -qF "bundled source $PLUGIN_COPY" "$codex.log" || fail "bootstrap did not use the bundled plugin copy: $(cat "$codex.log")"
assert_enabled "bundled bootstrap" "$codex" "$RECOMMENDED_SET"
jq -e '.harness == "codex" and .security == "safe"' "$codex/.specify/spex.json" >/dev/null ||
  fail "bundled bootstrap: declaration is not harness=codex, security=safe: $(cat "$codex/.specify/spex.json")"
if grep '^git ' "$NET_LOG"; then
  fail "bundled bootstrap tried a git network call"
fi
# The only allowed curl call is the release check; nothing may download spex.
if grep '^curl' "$NET_LOG" | grep -v 'api.github.com/repos/rhuss/cc-spex/releases/latest' | grep -q .; then
  fail "bundled bootstrap made an unexpected download: $(cat "$NET_LOG")"
fi
if find "$CODEX_TMP" -maxdepth 1 -name 'cc-spex-init-*' 2>/dev/null | grep -q .; then
  fail "bundled bootstrap created a cc-spex-init-* directory"
fi
echo "PASS: \$cc-spex-init runs setup from a bundled plugin copy without fetching spex (recommended set, harness codex)"

# US3 scenario 7: a project initialized with all and autonomous keeps both
# when $cc-spex-init runs again without arguments.
s7="$(new_project codex-all-autonomous)"
(
  cd "$s7" || exit 1
  env -u SPEX_SOURCE TMPDIR="$CODEX_TMP" PATH="$NET_BIN:$PATH" \
    sh "$PLUGIN_COPY/codex/skills/cc-spex-init/scripts/bootstrap.sh" --extensions all --security autonomous
) > "$s7.out" 2> "$s7.log" || fail "all/autonomous bootstrap failed: $(cat "$s7.log")"
assert_enabled "all/autonomous bootstrap" "$s7" "$ALL_SET"
(
  cd "$s7" || exit 1
  env -u SPEX_SOURCE TMPDIR="$CODEX_TMP" PATH="$NET_BIN:$PATH" \
    sh "$PLUGIN_COPY/codex/skills/cc-spex-init/scripts/bootstrap.sh"
) > "$s7.out" 2> "$s7.log" || fail "bootstrap refresh failed: $(cat "$s7.log")"
assert_completed "bootstrap refresh" "$(cat "$s7.out")"
assert_enabled "bootstrap refresh" "$s7" "$ALL_SET"
jq -e '.harness == "codex" and .security == "autonomous"' "$s7/.specify/spex.json" >/dev/null ||
  fail "bootstrap refresh: declaration is not harness=codex, security=autonomous: $(cat "$s7/.specify/spex.json")"
grep -qF "security=autonomous (from .specify/spex.json)" "$s7.log" ||
  fail "bootstrap refresh: the stored security level was not named: $(cat "$s7.log")"
echo "PASS: \$cc-spex-init without arguments keeps the all selection and autonomous security"

# --- A failed step's stdout error is surfaced, not only its stderr ----------
#
# Regression (init-project opacity): `specify init` writes its `Error:` lines
# to stdout, and `specify workflow run` captures them in the failed step's
# stdout while its stderr stays empty. spex-setup-report.sh must surface that
# stdout, otherwise a failed init shows only the generic run-state message
# "Shell command exited with code 1." with no underlying cause. A minimal
# one-step workflow reproduces a genuine specify-init failure: --integration
# generic needs --integration-options, and that error prints to stdout.
stdout_fail="$(new_project report-stdout-failure)"
cat > "$stdout_fail/fail.yml" <<'WF'
schema_version: "1.0"
workflow:
  id: report-stdout-failure
  name: report-stdout-failure
  version: "1.0.0"
steps:
  - id: init-project
    type: shell
    run: |
      specify init --here --integration generic --script sh --force
WF
stdout_fail_out="$(cd "$stdout_fail" && specify workflow run "$stdout_fail/fail.yml" --json </dev/null 2>/dev/null || true)"
jq -e '.status == "failed" and .current_step_id == "init-project"' <<<"$stdout_fail_out" >/dev/null ||
  fail "stdout failure: the init step did not fail as expected: $stdout_fail_out"
stdout_fail_run="$(jq -r '.run_id' <<<"$stdout_fail_out")"
stdout_fail_state="$stdout_fail/.specify/workflows/runs/$stdout_fail_run/state.json"
# Guard the scenario: the underlying error must really be on the step's
# stdout (this is what made it invisible before the fix).
jq -e '.step_results["init-project"].output.stdout | test("integration-options")' "$stdout_fail_state" >/dev/null ||
  fail "stdout failure: specify's error is not on the step's stdout (test assumption broke): $(cat "$stdout_fail_state")"
stdout_fail_report="$(cd "$stdout_fail" && sh "$SRC/scripts/spex-setup-report.sh" "$stdout_fail_run" 2>&1)"
printf '%s' "$stdout_fail_report" | grep -qF "integration-options" ||
  fail "stdout failure: the report did not surface the underlying stdout error: $stdout_fail_report"
echo "PASS: a failed step's stdout error (e.g. specify init) is surfaced by spex-setup-report.sh"

# --- A sandbox "Operation not permitted" failure gets an actionable hint ----
#
# When `specify init` is blocked by a sandbox (Codex guards the project's
# .agents/ directory, where spec-kit installs its Codex skills), it fails with
# EPERM: "Operation not permitted: .../.agents". The report must surface that
# error and add a hint that names the resolution (approve the filesystem
# escalation, or grant write access), so the user is not left with a bare
# "Operation not permitted". A one-step workflow prints that EPERM to stdout.
perm_fail="$(new_project report-perm-hint)"
cat > "$perm_fail/fail.yml" <<'WF'
schema_version: "1.0"
workflow:
  id: report-perm-hint
  name: report-perm-hint
  version: "1.0.0"
steps:
  - id: init-project
    type: shell
    run: |
      echo "Initialization failed: [Errno 1] Operation not permitted: '$(pwd)/.agents'"
      exit 1
WF
perm_fail_out="$(cd "$perm_fail" && specify workflow run "$perm_fail/fail.yml" --json </dev/null 2>/dev/null || true)"
jq -e '.status == "failed" and .current_step_id == "init-project"' <<<"$perm_fail_out" >/dev/null ||
  fail "perm hint: the step did not fail as expected: $perm_fail_out"
perm_fail_report="$(cd "$perm_fail" && sh "$SRC/scripts/spex-setup-report.sh" "$(jq -r '.run_id' <<<"$perm_fail_out")" 2>&1)"
printf '%s' "$perm_fail_report" | grep -qF "Operation not permitted" ||
  fail "perm hint: the underlying EPERM error was not surfaced: $perm_fail_report"
printf '%s' "$perm_fail_report" | grep -qF "filesystem escalation" ||
  fail "perm hint: no actionable hint was added: $perm_fail_report"
echo "PASS: a sandbox \"Operation not permitted\" failure is surfaced with an actionable hint"

# And a non-EPERM failure must NOT get the sandbox hint.
if printf '%s' "$stdout_fail_report" | grep -qF "filesystem escalation"; then
  fail "perm hint: the sandbox hint leaked onto an unrelated failure"
fi
echo "PASS: the sandbox hint is scoped to EPERM failures only"
