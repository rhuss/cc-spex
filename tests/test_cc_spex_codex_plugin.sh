#!/usr/bin/env bash
# Tests for the bundled cc-spex Codex plugin (FR-007 to FR-011, FR-013,
# FR-015, FR-020, FR-021).
#
# A stub `specify` records its arguments, SPEX_SOURCE and working directory.
# A `git` wrapper fails clone, fetch and ls-remote and passes every other call
# to the real git; a `curl` stub fails every call. Both log any attempt.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PLUGIN="$REPO_ROOT/spex"
SKILL="$PLUGIN/codex/skills/cc-spex-init"
BOOTSTRAP="$SKILL/scripts/bootstrap.sh"
MANIFEST="$PLUGIN/.codex-plugin/plugin.json"
MARKETPLACE="$REPO_ROOT/.agents/plugins/marketplace.json"
REAL_GIT="$(command -v git)"

PASS=0
FAIL=0
# A failed mktemp must never turn the current directory into TMP (the trap
# below removes TMP).
TMP_RAW="$(mktemp -d "${TMPDIR:-/tmp}/cc-spex-codex-plugin-test.XXXXXX")" || exit 1
TMP="$(cd "$TMP_RAW" && pwd -P)" || exit 1
[ -n "$TMP" ] && [ -d "$TMP" ] && [ "$TMP" != "$(pwd -P)" ] || { echo "cannot create a temporary directory" >&2; exit 1; }
trap 'rm -rf -- "$TMP"' EXIT

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

assert_eq() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$2', got '$3')"; fi
}

assert_contains() {
  if printf '%s' "$3" | grep -qF -- "$2"; then pass "$1"; else
    fail "$1 (missing '$2' in:"; printf '%s\n' "$3" | sed 's/^/      /'; echo "    )"
  fi
}

assert_not_contains() {
  if printf '%s' "$3" | grep -qF -- "$2"; then fail "$1 (unexpected '$2')"; else pass "$1"; fi
}

# --- Stubs ------------------------------------------------------------------
mkdir -p "$TMP/bin" "$TMP/tmpdir"
cat > "$TMP/bin/specify" <<'EOF'
#!/usr/bin/env bash
{
  printf 'SPEX_SOURCE=%s\n' "${SPEX_SOURCE:-}"
  printf 'PWD=%s\n' "$(pwd -P)"
  for argument in "$@"; do printf 'ARG=%s\n' "$argument"; done
} > "$STUB_ROOT/specify.log"
if [ -n "${STUB_RUN_ID:-}" ]; then
  printf '{"run_id": "%s", "workflow_id": "spex-setup", "status": "%s"}\n' "$STUB_RUN_ID" "${STUB_STATUS:-completed}"
fi
exit "${STUB_SPECIFY_RC:-0}"
EOF
cat > "$TMP/bin/git" <<EOF
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
    printf 'git %s\n' "\${original[*]}" >> "\$STUB_ROOT/network.log"
    echo "network disabled in tests" >&2
    exit 128 ;;
esac
exec "$REAL_GIT" "\${original[@]}"
EOF
cat > "$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >> "$STUB_ROOT/network.log"
exit 7
EOF
chmod +x "$TMP/bin/specify" "$TMP/bin/git" "$TMP/bin/curl"
: > "$TMP/network.log"

echo "Test: the git stub catches network subcommands behind global options"
RC=0
STUB_ROOT="$TMP" "$TMP/bin/git" -C "$TMP" -c http.sslVerify=true clone https://example.invalid/x.git "$TMP/never" >/dev/null 2>&1 || RC=$?
assert_eq "git -C dir -c kv clone fails" "128" "$RC"
assert_contains "the attempt is logged" "git -C $TMP -c http.sslVerify=true clone" "$(cat "$TMP/network.log")"
assert_contains "other git calls reach the real git" "git version" "$(STUB_ROOT="$TMP" "$TMP/bin/git" -C "$TMP" --version 2>&1)"
: > "$TMP/network.log"

# new_project <name>: a fresh git project that is not the cc-spex repository.
new_project() {
  local dir="$TMP/projects/$1"
  mkdir -p "$dir"
  "$REAL_GIT" -C "$dir" init -q
  printf '%s' "$dir"
}

write_declaration() {
  mkdir -p "$1/.specify"
  printf '%s\n' '{"schema_version": 1, "harness": "codex", "extensions": ["spex", "spex-gates", "spex-teams"], "security": "autonomous"}' \
    > "$1/.specify/spex.json"
}

# run_bootstrap <project> <script> [args...]: sets RC, OUT, ERR, LOG.
run_bootstrap() {
  local project="$1" script="$2"
  shift 2
  [ -n "$project" ] && [ -d "$project" ] || { echo "fixture missing" >&2; exit 1; }
  rm -f "$TMP/specify.log"
  RC=0
  (
    cd "$project" || exit 1
    STUB_ROOT="$TMP" TMPDIR="$TMP/tmpdir" PATH="$TMP/bin:$PATH" sh "$script" "$@"
  ) > "$TMP/out" 2> "$TMP/err" || RC=$?
  OUT="$(cat "$TMP/out")"
  ERR="$(cat "$TMP/err")"
  LOG="$(cat "$TMP/specify.log" 2>/dev/null || true)"
}

input_lines() {
  printf '%s\n' "$LOG" | grep -E '^ARG=(integration|extensions|security)=' | sed 's/^ARG=//' || true
}

# --- Source resolution and inputs -------------------------------------------
echo "Test: bundled source in a project that is not the cc-spex repository"
proj="$(new_project plain)"
run_bootstrap "$proj" "$BOOTSTRAP"
assert_eq "exit code 0" "0" "$RC"
assert_contains "SPEX_SOURCE is the bundled plugin root" "SPEX_SOURCE=$PLUGIN" "$LOG"
assert_contains "runs the bundled setup workflow" "ARG=$PLUGIN/setup.yml" "$LOG"
assert_contains "runs specify workflow run" "ARG=workflow" "$LOG"
assert_contains "stderr names the bundled source" "bundled" "$ERR"
assert_eq "working directory stays the project root" "PWD=$proj" "$(printf '%s\n' "$LOG" | grep '^PWD=')"
assert_eq "inputs without a declaration" "integration=codex
extensions=recommended
security=safe" "$(input_lines)"

echo "Test: no temporary checkout and no network access"
assert_eq "no cc-spex-init-* directory under TMPDIR" "" "$(find "$TMP/tmpdir" -maxdepth 1 -name 'cc-spex-init-*' -print)"
assert_eq "TMPDIR untouched" "" "$(ls -A "$TMP/tmpdir")"
assert_eq "no git clone/fetch/ls-remote or curl calls" "" "$(cat "$TMP/network.log")"

echo "Test: a declaration without overrides passes only integration"
proj="$(new_project declared)"
write_declaration "$proj"
run_bootstrap "$proj" "$BOOTSTRAP"
assert_eq "exit code 0" "0" "$RC"
assert_eq "only integration=codex" "integration=codex" "$(input_lines)"
assert_contains "stderr says the declaration is used" "from .specify/spex.json" "$ERR"
assert_contains "stderr names the stored security level" "security=autonomous (from .specify/spex.json)" "$ERR"
assert_contains "a non-safe stored security level is called out" "NOTE: .specify/spex.json requests security=autonomous" "$ERR"

echo "Test: a declaration with --extensions all"
run_bootstrap "$proj" "$BOOTSTRAP" --extensions all
assert_eq "exit code 0" "0" "$RC"
assert_eq "integration and extensions only" "integration=codex
extensions=all" "$(input_lines)"

echo "Test: a declaration with --security autonomous"
run_bootstrap "$proj" "$BOOTSTRAP" --security autonomous
assert_eq "integration and security only" "integration=codex
security=autonomous" "$(input_lines)"

echo "Test: explicit integration override"
run_bootstrap "$proj" "$BOOTSTRAP" --integration claude
assert_eq "integration passed through" "integration=claude" "$(input_lines)"

echo "Test: SPEX_SOURCE takes precedence"
fake_src="$TMP/fake-src"
mkdir -p "$fake_src/extensions/spex"
: > "$fake_src/setup.yml"
proj="$(new_project spex-source)"
RC=0
rm -f "$TMP/specify.log"
(cd "$proj" && SPEX_SOURCE="$fake_src" STUB_ROOT="$TMP" TMPDIR="$TMP/tmpdir" PATH="$TMP/bin:$PATH" sh "$BOOTSTRAP") \
  > "$TMP/out" 2> "$TMP/err" || RC=$?
LOG="$(cat "$TMP/specify.log" 2>/dev/null || true)"
assert_eq "exit code 0" "0" "$RC"
assert_contains "uses SPEX_SOURCE" "SPEX_SOURCE=$fake_src" "$LOG"
assert_contains "stderr names SPEX_SOURCE" "SPEX_SOURCE" "$(cat "$TMP/err")"

echo "Test: SPEX_SOURCE takes precedence over ./spex"
proj="$(new_project repo-like-with-source)"
mkdir -p "$proj/spex/extensions/spex"
: > "$proj/spex/setup.yml"
RC=0
rm -f "$TMP/specify.log"
(cd "$proj" && SPEX_SOURCE="$fake_src" STUB_ROOT="$TMP" TMPDIR="$TMP/tmpdir" PATH="$TMP/bin:$PATH" sh "$BOOTSTRAP") \
  > "$TMP/out" 2> "$TMP/err" || RC=$?
LOG="$(cat "$TMP/specify.log" 2>/dev/null || true)"
assert_eq "exit code 0" "0" "$RC"
assert_contains "uses SPEX_SOURCE, not ./spex" "SPEX_SOURCE=$fake_src" "$LOG"

echo "Test: an incomplete ./spex falls through to the bundled tree"
proj="$(new_project repo-like-incomplete)"
mkdir -p "$proj/spex"
: > "$proj/spex/setup.yml"
run_bootstrap "$proj" "$BOOTSTRAP"
assert_eq "exit code 0" "0" "$RC"
assert_contains "uses the bundled tree" "SPEX_SOURCE=$PLUGIN" "$LOG"
assert_contains "stderr names the bundled source" "bundled" "$ERR"

echo "Test: an invalid SPEX_SOURCE exits 1"
RC=0
rm -f "$TMP/specify.log"
(cd "$proj" && SPEX_SOURCE="$TMP/not-a-source" STUB_ROOT="$TMP" PATH="$TMP/bin:$PATH" sh "$BOOTSTRAP") \
  > "$TMP/out" 2> "$TMP/err" || RC=$?
assert_eq "exit code 1" "1" "$RC"
assert_contains "names SPEX_SOURCE" "SPEX_SOURCE does not contain a Spex source tree" "$(cat "$TMP/err")"
assert_eq "specify not run" "no" "$([ -f "$TMP/specify.log" ] && echo yes || echo no)"

echo "Test: ./spex takes precedence inside a repository-like directory"
proj="$(new_project repo-like)"
mkdir -p "$proj/spex/extensions/spex"
: > "$proj/spex/setup.yml"
run_bootstrap "$proj" "$BOOTSTRAP"
assert_eq "exit code 0" "0" "$RC"
assert_contains "uses ./spex" "SPEX_SOURCE=$proj/spex" "$LOG"
assert_contains "stderr names the repository source" "repository" "$ERR"

echo "Test: a broken bundled tree exits 1 without fetching anything"
broken="$TMP/broken-root"
mkdir -p "$broken/codex/skills/cc-spex-init/scripts" "$broken/extensions/spex"
cp "$BOOTSTRAP" "$broken/codex/skills/cc-spex-init/scripts/bootstrap.sh"
: > "$broken/extensions/spex/extension.yml"
proj="$(new_project broken)"
run_bootstrap "$proj" "$broken/codex/skills/cc-spex-init/scripts/bootstrap.sh"
assert_eq "exit code 1 without setup.yml" "1" "$RC"
assert_contains "names the missing setup.yml" "setup.yml is missing" "$ERR"
assert_contains "suggests SPEX_SOURCE" "SPEX_SOURCE" "$ERR"
assert_eq "specify not run" "" "$LOG"
: > "$broken/setup.yml"
rm "$broken/extensions/spex/extension.yml"
run_bootstrap "$proj" "$broken/codex/skills/cc-spex-init/scripts/bootstrap.sh"
assert_eq "exit code 1 without the spex extension" "1" "$RC"
assert_contains "names the missing extension manifest" "extensions/spex/extension.yml is missing" "$ERR"
assert_eq "no network access after failures" "" "$(cat "$TMP/network.log")"
assert_eq "still no cc-spex-init-* directory" "" "$(find "$TMP/tmpdir" -maxdepth 1 -name 'cc-spex-init-*' -print)"

echo "Test: the specify exit code is passed through"
proj="$(new_project failing)"
RC=0
(cd "$proj" && STUB_SPECIFY_RC=5 STUB_ROOT="$TMP" PATH="$TMP/bin:$PATH" sh "$BOOTSTRAP") >/dev/null 2>&1 || RC=$?
assert_eq "exit code 5" "5" "$RC"

echo "Test: the bootstrap prints the selection changes kept in the run state"
proj="$(new_project report)"
mkdir -p "$proj/.specify/workflows/runs/r1"
jq -n '{run_id: "r1", status: "completed", current_step_id: "check-update", step_results: {
  "snapshot-registry": {output: {stderr: "Migrated: removed spex-detach from .specify/spex.json (it was disabled; select it explicitly to enable it)\n"}},
  "apply-extensions": {output: {stderr: "Disabled: spex-teams\nExtensions: 0 enabled, 1 disabled, 5 unchanged\n"}},
  "persist-request": {output: {stderr: "Saved requested setup to .specify/spex.json\n"}}}}' \
  > "$proj/.specify/workflows/runs/r1/state.json"
STUB_RUN_ID=r1 run_bootstrap "$proj" "$BOOTSTRAP"
assert_eq "exit code 0" "0" "$RC"
assert_contains "workflow JSON on stdout" '"run_id": "r1"' "$OUT"
assert_contains "reports Disabled: spex-teams" "Disabled: spex-teams" "$ERR"
assert_contains "reports the summary" "Extensions: 0 enabled, 1 disabled, 5 unchanged" "$ERR"
assert_contains "reports the migration" "Migrated: removed spex-detach" "$ERR"
assert_not_contains "no unrelated step chatter" "Saved requested setup" "$ERR"

echo "Test: a failed run prints the failed step's error and keeps the exit code"
mkdir -p "$proj/.specify/workflows/runs/r2"
jq -n '{run_id: "r2", status: "failed", current_step_id: "enforce-git-extension", step_results: {
  "apply-extensions": {output: {stderr: "Extensions: 0 enabled, 0 disabled, 6 unchanged\n"}},
  "enforce-git-extension": {output: {stderr: "ERROR: spex-worktrees requires the spec-kit git extension\n  re-run setup with an extension selection that leaves out spex-worktrees, for example:\n"}}}}' \
  > "$proj/.specify/workflows/runs/r2/state.json"
STUB_RUN_ID=r2 STUB_STATUS=failed STUB_SPECIFY_RC=1 run_bootstrap "$proj" "$BOOTSTRAP"
assert_eq "exit code 1 passed through" "1" "$RC"
assert_contains "prints the git error" "ERROR: spex-worktrees requires the spec-kit git extension" "$ERR"
assert_contains "prints the FR-019 guidance" "leaves out spex-worktrees" "$ERR"

echo "Test: help and usage errors"
proj="$(new_project usage)"
run_bootstrap "$proj" "$BOOTSTRAP" --help
assert_eq "--help exits 0" "0" "$RC"
assert_contains "help lists integration default" "codex (default)" "$OUT"
assert_contains "help lists extensions default" "recommended (default)" "$OUT"
assert_contains "help lists security default" "safe (default)" "$OUT"
assert_eq "--help does not run specify" "" "$LOG"
run_bootstrap "$proj" "$BOOTSTRAP" --bogus
assert_eq "unknown option exits 2" "2" "$RC"
run_bootstrap "$proj" "$BOOTSTRAP" --extensions spex-gates,spex-bogus
assert_eq "unknown extension exits 2" "2" "$RC"
assert_contains "names the unknown extension" "spex-bogus" "$ERR"
run_bootstrap "$proj" "$BOOTSTRAP" --security unsafe
assert_eq "unknown security exits 2" "2" "$RC"
run_bootstrap "$proj" "$BOOTSTRAP" --integration vscode
assert_eq "unknown integration exits 2" "2" "$RC"
run_bootstrap "$proj" "$BOOTSTRAP" --extensions
assert_eq "missing value exits 2" "2" "$RC"

# --- Plugin layout and versions ----------------------------------------------
echo "Test: manifest, versions and skill layout"
workflow_version="$(awk '/^workflow:/ { in_wf = 1; next } in_wf && /^  version:/ { gsub(/"/, "", $2); print $2; exit }' "$PLUGIN/setup.yml")"
codex_version="$(jq -r '.version' "$MANIFEST")"
claude_version="$(jq -r '.version' "$PLUGIN/.claude-plugin/plugin.json")"
[ -n "$workflow_version" ] && pass "setup.yml workflow version found ($workflow_version)" || fail "setup.yml workflow version not found"
assert_eq "Codex manifest version equals the setup.yml workflow version" "$workflow_version" "$codex_version"
assert_eq "Codex manifest version equals the Claude plugin version" "$claude_version" "$codex_version"
assert_eq "Codex plugin name" "cc-spex" "$(jq -r '.name' "$MANIFEST")"
assert_eq "Codex skills path" "./codex/skills/" "$(jq -r '.skills' "$MANIFEST")"
assert_eq "only cc-spex-init is exposed to Codex" "cc-spex-init" "$(ls "$PLUGIN/codex/skills")"
[ -f "$SKILL/SKILL.md" ] && [ -f "$SKILL/agents/openai.yaml" ] && pass "skill files present" || fail "skill files missing"
assert_eq "bootstrap is executable" "yes" "$([ -x "$BOOTSTRAP" ] && echo yes || echo no)"
if grep -Eq '`/[^` ]+' "$SKILL/SKILL.md"; then fail "SKILL.md advertises a slash-prefixed command"; else pass "SKILL.md has no slash-prefixed command"; fi
assert_contains "SKILL.md suggests \$speckit-spex-help" '$speckit-spex-help' "$(cat "$SKILL/SKILL.md")"
assert_not_contains "SKILL.md does not clone" "git clone" "$(cat "$SKILL/SKILL.md")"
assert_not_contains "bootstrap does not clone" "git clone" "$(grep -v '^#' "$BOOTSTRAP")"
assert_not_contains "bootstrap creates no temporary directory" "mktemp" "$(grep -v '^#' "$BOOTSTRAP")"

echo "Test: Codex progress display (footer and terminal title setup)"
PROGRESS="$SKILL/scripts/codex-progress.sh"
assert_eq "codex-progress.sh is executable" "yes" "$([ -x "$PROGRESS" ] && echo yes || echo no)"
assert_not_contains "codex-progress.sh does not clone" "git clone" "$(grep -v '^#' "$PROGRESS")"
assert_not_contains "codex-progress.sh creates no temporary directory" "mktemp" "$(grep -v '^#' "$PROGRESS")"
skill_md="$(cat "$SKILL/SKILL.md")"
assert_contains "SKILL.md has the Codex progress display section" "## Codex progress display" "$skill_md"
assert_contains "SKILL.md runs the check" "codex-progress.sh check --root" "$skill_md"
assert_contains "SKILL.md records a decline" "codex-progress.sh decline --root" "$skill_md"
assert_contains "SKILL.md asks only for the codex integration" "only when the effective" "$skill_md"
section_order="$(grep -n -e '^## Defaults and overrides' -e '^## Codex progress display' -e '^## Report' "$SKILL/SKILL.md" | cut -d: -f2 | tr '\n' '|')"
assert_eq "progress section sits between defaults and report" "## Defaults and overrides|## Codex progress display|## Report|" "$section_order"
# The wrapper resolves the bundled source from its own location (no ./spex in
# the project) and runs the check against an empty Codex home.
mkdir -p "$TMP/progress-proj" "$TMP/progress-home"
progress_out="$(cd "$TMP/progress-proj" && env -u SPEX_SOURCE CODEX_HOME="$TMP/progress-home" sh "$PROGRESS" check --root "$TMP/progress-proj" 2>&1)" || true
assert_eq "wrapper check from the bundled source asks" "ASK" "$progress_out"
assert_contains "SKILL.md handles an UNSUPPORTED check" "UNSUPPORTED" "$skill_md"
# FR-019: Claude init and the shared setup workflow never run the Codex setup.
claude_refs="$(grep -rlE "codex-progress|spex-codex-progress" "$PLUGIN/skills" "$PLUGIN/setup.yml" "$PLUGIN/scripts/spex-init.sh" 2>/dev/null || true)"
assert_eq "Claude init and setup.yml do not reference the Codex progress setup" "" "$claude_refs"

echo "Test: FR-019 guidance never says to disable spex-worktrees by hand"
manual_disable="$(grep -rlF "extension disable spex-worktrees" "$PLUGIN" 2>/dev/null || true)"
assert_eq "no 'extension disable spex-worktrees' anywhere in spex/" "" "$manual_disable"
enforce_block="$(yq -r '.steps[] | select(.id == "enforce-git-extension") | .run' "$PLUGIN/setup.yml")"
assert_contains "setup.yml git check suggests a selection without spex-worktrees" "leaves out spex-worktrees" "$enforce_block"
assert_contains "init skill suggests a selection without spex-worktrees" "leaves out \`spex-worktrees\`" "$(cat "$PLUGIN/skills/init/SKILL.md")"

echo "Test: Codex marketplace"
[ -f "$MARKETPLACE" ] && pass "marketplace file exists" || fail "marketplace file missing"
if jq -e '.name == "cc-spex" and (.plugins | length) == 1 and
  (.plugins[0] | .name == "cc-spex" and .source.source == "local" and .source.path == "./spex")' \
  "$MARKETPLACE" >/dev/null 2>&1; then
  pass "marketplace cc-spex exposes plugin cc-spex from ./spex"
else
  fail "marketplace does not expose plugin cc-spex from ./spex"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
