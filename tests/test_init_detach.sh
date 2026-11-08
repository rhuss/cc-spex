#!/usr/bin/env bash
# Tests for the spex-detach handling in spex-init.sh --refresh (the Claude
# refresh path, which calls install_extensions directly, not the workflow):
# the detach configuration survives the reinstall and missing exclude
# entries are repaired.
#
# A stub `specify` CLI on PATH records registry changes the way specify-cli
# does: `extension remove` deletes the extension directory and the registry
# entry, `extension add` copies the source extension directory (template
# config included) and registers it as enabled.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_SCRIPT="$REPO_ROOT/spex/scripts/spex-init.sh"

EXT_SRC="$REPO_ROOT/spex/extensions"

PASS=0
FAIL=0
TMPROOT=""

# Isolate git from the developer's global configuration.
GIT_ISOLATION_HOME=$(mktemp -d)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$GIT_ISOLATION_HOME"
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

cleanup() {
  if [ -n "$TMPROOT" ] && [ -d "$TMPROOT" ]; then
    chmod -R u+w "$TMPROOT" 2>/dev/null || true
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
    echo "  FAIL: $desc (unexpected '$needle' in output)"; FAIL=$((FAIL + 1))
  fi
}

CONFIG_REL=".specify/extensions/spex-detach/spex-detach-config.yml"

# make_project <spex-detach enabled: true|false> [declaration csv]
# A git repository with every bundled extension installed (spex-worktrees
# disabled), a customized spex-detach config and no detach exclude entries.
make_project() {
  cleanup
  local raw
  raw=$(mktemp -d) || exit 1
  TMPROOT=$(cd "$raw" && pwd -P) || exit 1
  [ -n "$TMPROOT" ] && [ -d "$TMPROOT" ] && [ "$TMPROOT" != "$(pwd -P)" ] || { echo "cannot create a temporary directory" >&2; exit 1; }
  PROJ="$TMPROOT/proj"
  mkdir -p "$PROJ/.specify/extensions" "$TMPROOT/bin" "$TMPROOT/tmp"
  git -C "$PROJ" init -q
  mkdir -p "$PROJ/.git/info"
  : > "$TMPROOT/specify-calls.log"
  local ext
  for ext in spex spex-gates spex-worktrees spex-deep-review spex-teams spex-collab spex-detach; do
    cp -R "$EXT_SRC/$ext" "$PROJ/.specify/extensions/$ext"
  done
  jq -n --argjson detach "$1" '{schema_version: "1.0", extensions: {
    "spex": {enabled: true}, "spex-gates": {enabled: true}, "spex-worktrees": {enabled: false},
    "spex-deep-review": {enabled: true}, "spex-teams": {enabled: false}, "spex-collab": {enabled: false},
    "spex-detach": {enabled: $detach}}}' > "$PROJ/.specify/extensions/.registry"
  cat > "$PROJ/$CONFIG_REL" <<'EOF'
# my settings
archive:
  path: "../my-specs"   # sibling repo
  auto_commit: false
exclude:
  paths:
    - ".specify/"
    - "specs/"
    - "brainstorm/"
custom: kept
EOF
  if [ -n "${2:-}" ]; then
    jq -n --arg exts "$2" '{schema_version: 1, harness: "claude", extensions: ($exts | split(",")), security: "safe"}' \
      > "$PROJ/.specify/spex.json"
  fi

  cat > "$TMPROOT/bin/specify" <<'EOF'
#!/usr/bin/env bash
REG=".specify/extensions/.registry"
printf '%s\n' "$*" >> "$STUB_ROOT/specify-calls.log"
set_enabled() {
  jq --arg id "$1" --argjson v "$2" '.extensions[$id] = ((.extensions[$id] // {}) + {enabled: $v})' "$REG" > "$REG.tmp" && mv "$REG.tmp" "$REG"
}
case "$1 $2" in
  "init "*) exit 0 ;;
  "extension remove")
    rm -rf ".specify/extensions/$3"
    jq --arg id "$3" 'del(.extensions[$id])' "$REG" > "$REG.tmp" && mv "$REG.tmp" "$REG"
    exit 0 ;;
  "extension add")
    [ "$3" != git ] || exit 1
    id=$(basename "$3")
    rm -rf ".specify/extensions/$id"
    cp -R "$3" ".specify/extensions/$id"
    if [ -f "$3/config-template.yml" ]; then
      cp "$3/config-template.yml" ".specify/extensions/$id/$id-config.yml"
    fi
    # Simulate a restore that cannot write the extension directory.
    [ "${STUB_FAIL_RESTORE:-}" != "$id" ] || chmod a-w ".specify/extensions/$id"
    set_enabled "$id" true; exit 0 ;;
  "extension enable")
    [ "$3" != git ] || exit 1
    set_enabled "$3" true; exit 0 ;;
  "extension disable")
    set_enabled "$3" false; exit 0 ;;
esac
exit 0
EOF
  chmod +x "$TMPROOT/bin/specify"
  printf '#!/bin/sh\nexit 1\n' > "$TMPROOT/bin/curl"; chmod +x "$TMPROOT/bin/curl"
  # --update reinstalls specify-cli with uv; record the call, change nothing.
  printf '#!/bin/sh\nprintf "uv %%s\\n" "$*" >> "$STUB_ROOT/specify-calls.log"\nexit 0\n' > "$TMPROOT/bin/uv"; chmod +x "$TMPROOT/bin/uv"
}

# run_init <init script> [flag]: runs spex-init.sh with the stubs first on
# PATH. Sets RC and OUT (stdout and stderr).
run_init() {
  local script="$1"
  shift
  RC=0
  [ -n "${PROJ:-}" ] && [ -d "$PROJ/.specify" ] || { echo "fixture missing" >&2; exit 1; }
  [ "$(PATH="$TMPROOT/bin:$PATH" command -v specify)" = "$TMPROOT/bin/specify" ] || { echo "specify stub not first on PATH" >&2; exit 1; }
  OUT=$(cd "$PROJ" && STUB_ROOT="$TMPROOT" TMPDIR="$TMPROOT/tmp" PATH="$TMPROOT/bin:$PATH" bash "$script" "$@" 2>&1) || RC=$?
}

run_refresh() { run_init "$INIT_SCRIPT" --refresh; }

config_hash() { shasum "$PROJ/$CONFIG_REL" | cut -d' ' -f1; }
entry_count() { grep -cxF -- "$1" "$PROJ/.git/info/exclude" 2>/dev/null || true; }
registry_enabled() {
  jq -r --arg id "$1" '.extensions[$id] | if . == null then "absent" else (.enabled | tostring) end' "$PROJ/.specify/extensions/.registry"
}

echo "Test: refresh with a declaration naming spex-detach keeps the config and repairs entries"
make_project true "spex,spex-gates,spex-deep-review,spex-detach"
BEFORE=$(config_hash)
run_refresh
assert_eq "exit code 3 (restart required)" "3" "$RC"
assert_eq "config byte-identical" "$BEFORE" "$(config_hash)"
assert_eq "no saved copy left" "false" "$([ -e "$PROJ/.specify/.spex-detach-config.saved.yml" ] && echo true || echo false)"
assert_eq "spex-detach enabled" "true" "$(registry_enabled spex-detach)"
assert_contains "repair reported" "Repaired stealth mode: added .specify/ specs/ brainstorm/" "$OUT"
assert_contains "verification shown" "Stealth mode: active" "$OUT"
assert_not_contains "no ERROR" "ERROR" "$OUT"
echo "Test: a second refresh adds nothing and keeps each entry once"
run_refresh
assert_eq "exit code 3" "3" "$RC"
assert_not_contains "no repair the second time" "Repaired" "$OUT"
assert_contains "verification still shown" "Stealth mode: active" "$OUT"
for e in .specify/ specs/ brainstorm/; do
  assert_eq "$e once" "1" "$(entry_count "$e")"
done
assert_eq "config still byte-identical" "$BEFORE" "$(config_hash)"

echo "Test: refresh with a declaration leaving out spex-detach keeps the disabled config"
make_project false "spex,spex-gates,spex-deep-review"
BEFORE=$(config_hash)
run_refresh
assert_eq "exit code 3" "3" "$RC"
assert_eq "config byte-identical" "$BEFORE" "$(config_hash)"
assert_eq "spex-detach stays disabled" "false" "$(registry_enabled spex-detach)"
assert_not_contains "no stealth output" "tealth mode" "$OUT"
assert_eq "no entries written" "0" "$(entry_count specs/)"

echo "Test: refresh without a declaration repairs an enabled spex-detach"
make_project true
BEFORE=$(config_hash)
run_refresh
assert_eq "exit code 3" "3" "$RC"
assert_eq "config byte-identical" "$BEFORE" "$(config_hash)"
assert_eq "spex-detach stays enabled" "true" "$(registry_enabled spex-detach)"
assert_contains "repair reported" "Repaired stealth mode: added .specify/ specs/ brainstorm/" "$OUT"
assert_eq "specs/ written once" "1" "$(entry_count specs/)"

echo "Test: refresh without a declaration and a disabled spex-detach stays quiet"
make_project false
BEFORE=$(config_hash)
run_refresh
assert_eq "exit code 3" "3" "$RC"
assert_eq "config byte-identical" "$BEFORE" "$(config_hash)"
assert_not_contains "no stealth output" "tealth mode" "$OUT"

echo "Test: refresh without a config installs the template"
make_project true
rm -f "$PROJ/$CONFIG_REL"
run_refresh
assert_eq "exit code 3" "3" "$RC"
assert_eq "template installed" "$(shasum "$EXT_SRC/spex-detach/config-template.yml" | cut -d' ' -f1)" "$(config_hash)"

echo "Test: a failed config save stops refresh before anything changes"
if [ "$(id -u)" = 0 ]; then
  echo "  SKIP: running as root, a read-only directory cannot make save fail"
else
  make_project true "spex,spex-gates,spex-deep-review,spex-detach"
  BEFORE=$(config_hash)
  chmod a-w "$PROJ/.specify"
  run_refresh
  chmod u+w "$PROJ/.specify"
  assert_eq "exit code 1" "1" "$RC"
  assert_contains "names the config file" "$CONFIG_REL" "$OUT"
  assert_eq "config untouched" "$BEFORE" "$(config_hash)"
  assert_not_contains "no extension removed" "extension remove" "$(cat "$TMPROOT/specify-calls.log")"
  assert_not_contains "specify init never ran" "init " "$(cat "$TMPROOT/specify-calls.log")"
fi

echo "Test: refresh drops a stale was-enabled marker"
make_project true "spex,spex-gates,spex-deep-review,spex-detach"
: > "$PROJ/.specify/.spex-detach-was-enabled"
run_refresh
assert_eq "exit code 3" "3" "$RC"
assert_eq "marker removed" "false" "$([ -e "$PROJ/.specify/.spex-detach-was-enabled" ] && echo true || echo false)"

echo "Test: a failed config restore stops refresh with spex-detach disabled"
if [ "$(id -u)" = 0 ]; then
  echo "  SKIP: running as root, a read-only directory cannot make restore fail"
else
  make_project false "spex,spex-gates,spex-deep-review,spex-detach"
  BEFORE=$(shasum "$PROJ/$CONFIG_REL" | cut -d' ' -f1)
  STUB_FAIL_RESTORE=spex-detach run_refresh
  chmod u+w "$PROJ/.specify/extensions/spex-detach"
  assert_eq "exit code 1" "1" "$RC"
  assert_contains "names the saved copy" "your configuration is kept in .specify/.spex-detach-config.saved.yml" "$OUT"
  assert_eq "spex-detach left disabled" "false" "$(registry_enabled spex-detach)"
  assert_eq "saved copy holds the user config" "$BEFORE" "$(shasum "$PROJ/.specify/.spex-detach-config.saved.yml" | cut -d' ' -f1)"
fi

echo "Test: a failed config restore keeps an enabled spex-detach enabled"
if [ "$(id -u)" = 0 ]; then
  echo "  SKIP: running as root, a read-only directory cannot make restore fail"
else
  make_project true "spex,spex-gates,spex-deep-review,spex-detach"
  STUB_FAIL_RESTORE=spex-detach run_refresh
  chmod u+w "$PROJ/.specify/extensions/spex-detach"
  assert_eq "exit code 1" "1" "$RC"
  assert_eq "spex-detach still enabled" "true" "$(registry_enabled spex-detach)"
fi

echo "Test: a crashing ensure on refresh prints a warning with the error and keeps exit 3"
make_project true
REAL_PY="$(command -v python3)"
cat > "$TMPROOT/bin/python3" <<PYSTUB
#!/bin/sh
case "\${1:-}" in
  */spex-detach.py) echo "Traceback: PermissionError: info/exclude" >&2; exit 1 ;;
esac
exec "$REAL_PY" "\$@"
PYSTUB
chmod +x "$TMPROOT/bin/python3"
run_refresh
assert_eq "exit code 3" "3" "$RC"
assert_contains "warning line" "WARNING: stealth mode is NOT fully active. The exclude entries could not be written or verified:" "$OUT"
assert_contains "error in the warning" "  spex-detach.sh ensure failed with exit code 1: Traceback: PermissionError: info/exclude" "$OUT"
assert_not_contains "no active line" "Stealth mode: active" "$OUT"

echo "Test: --update keeps the config and repairs entries"
make_project true "spex,spex-gates,spex-deep-review,spex-detach"
BEFORE=$(config_hash)
: > "$PROJ/.specify/.spex-detach-was-enabled"
run_init "$INIT_SCRIPT" --update
assert_eq "exit code 3 (restart required)" "3" "$RC"
assert_contains "uv reinstall ran" "uv tool install specify-cli" "$(cat "$TMPROOT/specify-calls.log")"
assert_eq "config byte-identical" "$BEFORE" "$(config_hash)"
assert_eq "no saved copy left" "false" "$([ -e "$PROJ/.specify/.spex-detach-config.saved.yml" ] && echo true || echo false)"
assert_contains "repair reported" "Repaired stealth mode: added .specify/ specs/ brainstorm/" "$OUT"
assert_contains "verified" "Stealth mode: active" "$OUT"
assert_eq "stale marker removed" "false" "$([ -e "$PROJ/.specify/.spex-detach-was-enabled" ] && echo true || echo false)"

echo "Test: /spex:init without a declaration marks an enabled spex-detach for the skill"
make_project true
run_init "$INIT_SCRIPT"
assert_contains "no declaration reported" "DECLARATION_EXISTED=false" "$OUT"
assert_contains "workflow delegated" "workflow run" "$(cat "$TMPROOT/specify-calls.log")"
assert_eq "marker created" "true" "$([ -e "$PROJ/.specify/.spex-detach-was-enabled" ] && echo true || echo false)"

echo "Test: /spex:init without a declaration and a disabled spex-detach creates no marker"
make_project false
: > "$PROJ/.specify/.spex-detach-was-enabled"
run_init "$INIT_SCRIPT"
assert_eq "stale marker removed, none created" "false" "$([ -e "$PROJ/.specify/.spex-detach-was-enabled" ] && echo true || echo false)"

echo "Test: /spex:init with a declaration creates no marker"
make_project true "spex,spex-gates,spex-deep-review,spex-detach"
run_init "$INIT_SCRIPT"
assert_contains "declaration reported" "DECLARATION_EXISTED=true" "$OUT"
assert_eq "no marker" "false" "$([ -e "$PROJ/.specify/.spex-detach-was-enabled" ] && echo true || echo false)"

# make_legacy_ready: a copy of spex without setup.yml (the legacy path) and a
# project that check_ready accepts, so the fast path runs.
make_legacy_ready() {
  LEGACY_SPEX="$TMPROOT/spex-legacy"
  cp -R "$REPO_ROOT/spex" "$LEGACY_SPEX"
  rm -f "$LEGACY_SPEX/setup.yml"
  mkdir -p "$PROJ/.specify/templates"
  : > "$PROJ/.specify/templates/spec-template.md"
  local cmd
  for cmd in specify plan implement tasks clarify; do
    mkdir -p "$PROJ/.claude/skills/speckit-$cmd"
    : > "$PROJ/.claude/skills/speckit-$cmd/SKILL.md"
  done
}

echo "Test: legacy fast path with a declaration shows only the stealth-mode lines of the quiet install"
make_project true "spex,spex-gates,spex-deep-review,spex-detach"
make_legacy_ready
BEFORE=$(config_hash)
run_init "$LEGACY_SPEX/scripts/spex-init.sh"
assert_eq "exit code 0" "0" "$RC"
assert_contains "READY" "READY" "$OUT"
assert_contains "repair line passes the filter" "Repaired stealth mode: added .specify/ specs/ brainstorm/" "$OUT"
assert_contains "active line passes the filter" "Stealth mode: active" "$OUT"
assert_not_contains "install noise filtered" "Extensions: " "$OUT"
assert_eq "repair reported once" "1" "$(printf '%s\n' "$OUT" | grep -c "Repaired stealth mode")"
assert_eq "config byte-identical" "$BEFORE" "$(config_hash)"
assert_eq "no saved copy left" "false" "$([ -e "$PROJ/.specify/.spex-detach-config.saved.yml" ] && echo true || echo false)"
for e in .specify/ specs/ brainstorm/; do
  assert_eq "$e once" "1" "$(entry_count "$e")"
done

echo "Test: legacy fast path with a visible path keeps the warning and its path lines"
make_project true "spex,spex-gates,spex-deep-review,spex-detach"
make_legacy_ready
mkdir -p "$PROJ/specs" && echo x > "$PROJ/specs/tracked.md"
git -C "$PROJ" add specs/tracked.md
run_init "$LEGACY_SPEX/scripts/spex-init.sh"
assert_eq "exit code 0" "0" "$RC"
assert_contains "warning passes the filter" "WARNING: stealth mode is NOT fully active" "$OUT"
assert_contains "path line passes the filter" "  specs/ (tracked)" "$OUT"
assert_not_contains "no active line" "Stealth mode: active" "$OUT"

echo "Test: legacy fast path without a declaration repairs an enabled spex-detach"
make_project true
make_legacy_ready
run_init "$LEGACY_SPEX/scripts/spex-init.sh"
assert_eq "exit code 0" "0" "$RC"
assert_contains "repair line" "Repaired stealth mode: added .specify/ specs/ brainstorm/" "$OUT"
assert_eq "spex-detach still enabled" "true" "$(registry_enabled spex-detach)"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
