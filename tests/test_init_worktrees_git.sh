#!/usr/bin/env bash
# Tests for the spex-worktrees / git extension check in spex-init.sh (FR-014).
#
# A stub `specify` CLI on PATH records registry changes the way specify-cli
# does (remove deletes the entry, add re-registers it as enabled), and can be
# told to fail enabling or adding the git extension.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_SCRIPT="$REPO_ROOT/spex/scripts/spex-init.sh"

PASS=0
FAIL=0
TMPROOT=""

cleanup() {
  if [ -n "$TMPROOT" ] && [ -d "$TMPROOT" ]; then
    rm -rf "$TMPROOT"
  fi
  TMPROOT=""
}
trap cleanup EXIT

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
    echo "  FAIL: $desc (unexpected '$needle' in output)"; FAIL=$((FAIL + 1))
  fi
}

# make_project <worktrees-enabled: true|false> <git-available: yes|no> [extra registry entries]
# The optional third argument is a JSON object of id -> enabled merged into
# the registry, for example '{"spex-teams": false}'.
make_project() {
  cleanup
  local raw
  raw=$(mktemp -d) || exit 1
  TMPROOT=$(cd "$raw" && pwd -P) || exit 1
  [ -n "$TMPROOT" ] && [ -d "$TMPROOT" ] && [ "$TMPROOT" != "$(pwd -P)" ] || { echo "cannot create a temporary directory" >&2; exit 1; }
  PROJ="$TMPROOT/proj"
  mkdir -p "$PROJ/.specify/extensions" "$TMPROOT/bin"
  jq -n --argjson wt "$1" --argjson extra "${3:-"{}"}" '{schema_version: "1.0", extensions: (
    {"spex-worktrees": {enabled: $wt}, "spex": {enabled: true}} +
    ($extra | with_entries(.value = {enabled: .value})))}' \
    > "$PROJ/.specify/extensions/.registry"
  echo "$2" > "$TMPROOT/git-available"

  cat > "$TMPROOT/bin/specify" <<'EOF'
#!/usr/bin/env bash
REG=".specify/extensions/.registry"
GIT_OK=$(cat "$STUB_ROOT/git-available")
printf '%s\n' "$*" >> "$STUB_ROOT/specify-calls.log"
set_enabled() {
  jq --arg id "$1" --argjson v "$2" '.extensions[$id] = ((.extensions[$id] // {}) + {enabled: $v})' "$REG" > "$REG.tmp" && mv "$REG.tmp" "$REG"
}
case "$1 $2" in
  "init "*) exit 0 ;;
  "extension remove")
    jq --arg id "$3" 'del(.extensions[$id])' "$REG" > "$REG.tmp" && mv "$REG.tmp" "$REG"
    exit 0 ;;
  "extension add")
    if [ "$3" = "git" ]; then
      [ "$GIT_OK" = yes ] || exit 1
      set_enabled git true; exit 0
    fi
    id=$(basename "$3"); mkdir -p ".specify/extensions/$id"; set_enabled "$id" true; exit 0 ;;
  "extension enable")
    if [ "$3" = "git" ] && [ "$GIT_OK" != yes ]; then exit 1; fi
    set_enabled "$3" true; exit 0 ;;
  "extension disable")
    set_enabled "$3" false; exit 0 ;;
esac
exit 0
EOF
  chmod +x "$TMPROOT/bin/specify"
  # No network in tests: check_update returns early without curl.
  printf '#!/bin/sh\nexit 1\n' > "$TMPROOT/bin/curl"; chmod +x "$TMPROOT/bin/curl"
}

run_refresh() {
  RC=0
  # Never run init outside the fixture (an empty PROJ would mean the caller's
  # directory), and never with the real specify CLI.
  [ -n "${PROJ:-}" ] && [ -d "$PROJ/.specify" ] || { echo "fixture missing" >&2; exit 1; }
  [ "$(PATH="$TMPROOT/bin:$PATH" command -v specify)" = "$TMPROOT/bin/specify" ] || { echo "specify stub not first on PATH" >&2; exit 1; }
  mkdir -p "$TMPROOT/tmp"
  OUT=$(cd "$PROJ" && STUB_ROOT="$TMPROOT" TMPDIR="$TMPROOT/tmp" PATH="$TMPROOT/bin:$PATH" bash "$INIT_SCRIPT" --refresh 2>&1) || RC=$?
}

# run_default: spex-init.sh without flags (delegates to the stubbed setup
# workflow). Sets RC and OUT.
run_default() {
  RC=0
  [ -n "${PROJ:-}" ] && [ -d "$PROJ/.specify" ] || { echo "fixture missing" >&2; exit 1; }
  [ "$(PATH="$TMPROOT/bin:$PATH" command -v specify)" = "$TMPROOT/bin/specify" ] || { echo "specify stub not first on PATH" >&2; exit 1; }
  OUT=$(cd "$PROJ" && STUB_ROOT="$TMPROOT" TMPDIR="$TMPROOT/tmp" PATH="$TMPROOT/bin:$PATH" bash "$INIT_SCRIPT" 2>&1) || RC=$?
}

registry_enabled() {
  jq -r --arg id "$1" '.extensions[$id] | if . == null then "absent" else (.enabled | tostring) end' "$PROJ/.specify/extensions/.registry"
}

echo "Test: refresh fails when spex-worktrees is enabled and git cannot be enabled"
make_project true no
run_refresh
assert_eq "exit code 1" "1" "$RC"
assert_contains "names the missing git extension" "ERROR: spex-worktrees requires the spec-kit git extension" "$OUT"
assert_contains "remedy: add git" "specify extension add git" "$OUT"
assert_contains "remedy: re-run setup without spex-worktrees" "re-run setup with an extension selection that leaves out spex-worktrees" "$OUT"
assert_contains "remedy names the setup command" "specify workflow run" "$OUT"
assert_not_contains "old remedy is gone" "specify extension disable spex-worktrees" "$OUT"
assert_not_contains "no restart advice" "RESTART_REQUIRED" "$OUT"

echo "Test: refresh enables git when spex-worktrees is enabled and git is available"
make_project true yes
run_refresh
assert_eq "exit code 3 (restart required)" "3" "$RC"
assert_not_contains "no error" "ERROR:" "$OUT"
assert_eq "git enabled" "true" "$(registry_enabled git)"

echo "Test: refresh keeps working when spex-worktrees is disabled and git is unavailable"
make_project false no
run_refresh
assert_eq "exit code 3 (restart required)" "3" "$RC"
assert_not_contains "no error" "ERROR:" "$OUT"
assert_eq "spex-worktrees stays disabled" "false" "$(registry_enabled spex-worktrees)"

# write_declaration <comma-separated extensions>
write_declaration() {
  jq -n --arg exts "$1" '{schema_version: 1, harness: "claude", extensions: ($exts | split(",")), security: "safe"}' \
    > "$PROJ/.specify/spex.json"
}

declared() {
  jq -r '.extensions | join(",")' "$PROJ/.specify/spex.json"
}

echo "Test: refresh with a declaration re-applies it (FR-004)"
# spex-teams was enabled by hand outside the declaration; spex-gates is in
# the declaration but was disabled by hand.
make_project true yes '{"git": true, "spex-gates": false, "spex-teams": true, "spex-collab": false}'
write_declaration "spex,spex-gates,spex-worktrees"
run_refresh
assert_eq "exit code 3 (restart required)" "3" "$RC"
assert_not_contains "no error" "ERROR:" "$OUT"
assert_eq "spex-teams disabled again" "false" "$(registry_enabled spex-teams)"
assert_eq "spex-gates enabled again" "true" "$(registry_enabled spex-gates)"
assert_eq "spex-worktrees enabled" "true" "$(registry_enabled spex-worktrees)"
assert_eq "spex-deep-review disabled" "false" "$(registry_enabled spex-deep-review)"
assert_eq "spex-detach disabled" "false" "$(registry_enabled spex-detach)"
assert_contains "reports Disabled: spex-teams" "Disabled: spex-teams" "$OUT"
assert_contains "reports Enabled: spex-gates" "Enabled: spex-gates" "$OUT"
assert_not_contains "collab was already disabled" "Disabled: spex-collab" "$OUT"
assert_eq "declaration unchanged" "spex,spex-gates,spex-worktrees" "$(declared)"

echo "Test: refresh with a declaration enabling spex-worktrees still requires git"
make_project false no '{"spex-gates": true}'
write_declaration "spex,spex-gates,spex-worktrees"
run_refresh
assert_eq "exit code 1" "1" "$RC"
assert_contains "names the missing git extension" "ERROR: spex-worktrees requires the spec-kit git extension" "$OUT"

echo "Test: refresh with a legacy declaration drops spex-detach (FR-023)"
make_project false no '{"spex-gates": true, "spex-detach": false}'
write_declaration "spex,spex-gates,spex-detach"
run_refresh
assert_eq "exit code 3 (restart required)" "3" "$RC"
assert_eq "spex-detach stays disabled" "false" "$(registry_enabled spex-detach)"
assert_eq "spex-detach removed from the declaration" "spex,spex-gates" "$(declared)"
assert_contains "reports the migration" "Migrated: removed spex-detach" "$OUT"

echo "Test: refresh with a declaration that selects an enabled spex-detach keeps it"
make_project false no '{"spex-gates": true, "spex-detach": true}'
write_declaration "spex,spex-gates,spex-detach"
run_refresh
assert_eq "exit code 3 (restart required)" "3" "$RC"
assert_eq "spex-detach enabled" "true" "$(registry_enabled spex-detach)"
assert_eq "declaration unchanged" "spex,spex-gates,spex-detach" "$(declared)"
assert_not_contains "no migration" "Migrated: removed spex-detach" "$OUT"

echo "Test: refresh with an invalid declaration stops with the validator message"
make_project false no '{"spex-gates": true}'
printf '%s\n' '{"schema_version": 1, "harness": "nope", "extensions": ["spex"], "security": "safe"}' > "$PROJ/.specify/spex.json"
run_refresh
assert_eq "exit code 1" "1" "$RC"
assert_contains "validator message" "harness must be" "$OUT"

echo "Test: refresh without a declaration keeps disabled extensions disabled (FR-016)"
make_project false no '{"spex-gates": true, "spex-teams": false, "spex-collab": true}'
run_refresh
assert_eq "exit code 3 (restart required)" "3" "$RC"
assert_eq "spex-teams stays disabled" "false" "$(registry_enabled spex-teams)"
assert_eq "spex-collab stays enabled" "true" "$(registry_enabled spex-collab)"
assert_eq "spex-worktrees stays disabled" "false" "$(registry_enabled spex-worktrees)"
assert_eq "no declaration written" "no" "$([ -f "$PROJ/.specify/spex.json" ] && echo yes || echo no)"

echo "Test: refresh without a declaration keeps a newly installed spex-detach disabled"
make_project false no '{"spex-gates": true}'
run_refresh
assert_eq "exit code 3 (restart required)" "3" "$RC"
assert_eq "spex-detach installed but disabled" "false" "$(registry_enabled spex-detach)"

echo "Test: refresh without a declaration keeps an enabled spex-detach enabled (FR-016)"
make_project false no '{"spex-gates": true, "spex-detach": true}'
run_refresh
assert_eq "exit code 3 (restart required)" "3" "$RC"
assert_eq "spex-detach stays enabled" "true" "$(registry_enabled spex-detach)"

echo "Test: the registry snapshot of a declaration refresh is removed"
make_project false no '{"spex-gates": true}'
printf '%s\n' '{"schema_version": 1, "harness": "claude", "extensions": ["spex", "spex-gates"], "security": "safe"}' > "$PROJ/.specify/spex.json"
run_refresh
assert_eq "exit code 3 (restart required)" "3" "$RC"
assert_eq "no snapshot left in TMPDIR" "" "$(ls -A "$TMPROOT/tmp")"

echo "Test: init reports whether a declaration existed before the setup run (FR-022)"
make_project false no '{"spex-gates": true}'
run_default
assert_eq "exit code 0" "0" "$RC"
assert_contains "no declaration yet" "DECLARATION_EXISTED=false" "$OUT"
assert_contains "defaults passed instead of workflow prompts" "-i extensions=recommended -i security=safe" "$(grep '^workflow run' "$TMPROOT/specify-calls.log")"
: > "$TMPROOT/specify-calls.log"
printf '%s\n' '{"schema_version": 1, "harness": "codex", "extensions": ["spex"], "security": "safe"}' > "$PROJ/.specify/spex.json"
run_default
assert_eq "exit code 0" "0" "$RC"
assert_contains "declaration present" "DECLARATION_EXISTED=true" "$OUT"
assert_not_contains "never both" "DECLARATION_EXISTED=false" "$OUT"
assert_not_contains "no inputs with a declaration" " -i " "$(grep '^workflow run' "$TMPROOT/specify-calls.log")"

echo "Test: refresh migrates legacy permission rules in both settings files (spec 061, US2)"
make_project false no
mkdir -p "$PROJ/.claude"
printf '%s' '{"permissions":{"defaultMode":"bypassPermissions","allow":["Bash(*)","Read(*)","Bash(npm test)"]},"hooks":{"Stop":[]}}' > "$PROJ/.claude/settings.json"
printf '%s' '{"permissions":{"allow":["Edit(*)"]}}' > "$PROJ/.claude/settings.local.json"
run_refresh
assert_eq "exit code 3 (restart required)" "3" "$RC"
assert_eq "settings.json migrated" '["Bash","Read","Bash(npm test)"]' "$(jq -c .permissions.allow "$PROJ/.claude/settings.json")"
assert_eq "other keys kept" '{"Stop":[]}|bypassPermissions' "$(jq -c .hooks "$PROJ/.claude/settings.json")|$(jq -r .permissions.defaultMode "$PROJ/.claude/settings.json")"
assert_eq "settings.local.json migrated" '["Edit"]' "$(jq -c .permissions.allow "$PROJ/.claude/settings.local.json")"
assert_contains "Migrated line" "Migrated: .claude/settings.json permissions: Bash(*) -> Bash, Read(*) -> Read" "$OUT"
assert_contains "Migrated line (local)" "Migrated: .claude/settings.local.json permissions: Edit(*) -> Edit" "$OUT"
BEFORE=$(cksum < "$PROJ/.claude/settings.json")
run_refresh
assert_eq "second refresh: exit code 3" "3" "$RC"
assert_eq "second refresh: settings.json byte-identical" "$BEFORE" "$(cksum < "$PROJ/.claude/settings.json")"
assert_not_contains "second refresh: no Migrated line" "Migrated: .claude/settings" "$OUT"

echo "Test: refresh with invalid settings JSON warns and still completes (spec 061, US3-3)"
make_project false no
mkdir -p "$PROJ/.claude"
printf '%s' '{"permissions":' > "$PROJ/.claude/settings.json"
BEFORE=$(cksum < "$PROJ/.claude/settings.json")
run_refresh
assert_eq "exit code 3 (restart required)" "3" "$RC"
assert_eq "file unchanged" "$BEFORE" "$(cksum < "$PROJ/.claude/settings.json")"
assert_contains "warning names the file" "WARNING: .claude/settings.json is not valid JSON; permission rules not migrated" "$OUT"
assert_contains "refresh completed" "RESTART_REQUIRED" "$OUT"

echo "Test: update migrates legacy permission rules (spec 061, FR-004)"
make_project false no
printf '#!/bin/sh\nexit 0\n' > "$TMPROOT/bin/uv"; chmod +x "$TMPROOT/bin/uv"
mkdir -p "$PROJ/.claude"
printf '%s' '{"permissions":{"allow":["Write(*)","Skill"]}}' > "$PROJ/.claude/settings.json"
RC=0
OUT=$(cd "$PROJ" && STUB_ROOT="$TMPROOT" TMPDIR="$TMPROOT/tmp" PATH="$TMPROOT/bin:$PATH" bash "$INIT_SCRIPT" --update 2>&1) || RC=$?
assert_eq "exit code 3 (restart required)" "3" "$RC"
assert_eq "settings.json migrated" '["Write","Skill"]' "$(jq -c .permissions.allow "$PROJ/.claude/settings.json")"
assert_contains "Migrated line" "Migrated: .claude/settings.json permissions: Write(*) -> Write" "$OUT"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
