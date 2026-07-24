#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MATERIALIZE="$REPO_ROOT/spex/scripts/spex-materialize-plugin.sh"
SETUP="$REPO_ROOT/spex/setup.yml"
PROFILE_TOOL="$REPO_ROOT/spex/scripts/spex-init-profile.py"
CONFIGURE_PROJECT="$REPO_ROOT/spex/scripts/adapters/codex/configure-project.py"
CODEX_MANIFEST="$REPO_ROOT/plugins/codex/.codex-plugin/plugin.json"
CODEX_HOOKS="$REPO_ROOT/plugins/codex/hooks/hooks.json"
CODEX_MARKETPLACE="$REPO_ROOT/.codex-plugin/marketplace.json"
INIT_SKILL="$REPO_ROOT/spex/skills/init/SKILL.md"

# shellcheck source=../lib/test_helpers.sh
source "$REPO_ROOT/tests/lib/test_helpers.sh"
trap spex_test_cleanup EXIT HUP INT TERM

PASSED=0
FAILED=0
SKIPPED=0

pass() { printf 'PASS: %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=$((FAILED + 1)); }
skip() { printf 'SKIP: %s\n' "$1"; SKIPPED=$((SKIPPED + 1)); }

path_digest() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    printf 'absent\n'
  elif [[ -f "$path" ]]; then
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$path" | awk '{print $1}'
    else shasum -a 256 "$path" | awk '{print $1}'; fi
  else
    (
      cd "$path" || exit 1
      find . -type f -print | LC_ALL=C sort | while IFS= read -r file; do
        if command -v sha256sum >/dev/null 2>&1; then sha256sum "$file"
        else shasum -a 256 "$file"; fi
      done
    ) | if command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}'
        else shasum -a 256 | awk '{print $1}'; fi
  fi
}

echo "=== Codex install journey prerequisites ==="
for dependency in jq yq git python3; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    printf 'ERROR: required integration-test dependency missing: %s\n' "$dependency" >&2
    exit 2
  fi
done

# T017 is intentionally test-first. Report missing US1 pieces together and stop
# before invoking a client, so red-state output identifies implementation work.
for artifact in \
  "$CODEX_MANIFEST:Codex plugin manifest (T018)" \
  "$CODEX_HOOKS:Codex bundled hooks (T018)" \
  "$CODEX_MARKETPLACE:Codex personal marketplace (T019)" \
  "$PROFILE_TOOL:InitializationProfile helper (T021)" \
  "$CONFIGURE_PROJECT:Codex project configurator (T022)"; do
  path="${artifact%%:*}"
  label="${artifact#*:}"
  if [[ ! -f "$path" ]]; then
    fail "$label is missing: ${path#"$REPO_ROOT"/}"
  fi
done

if ! yq -e '.inputs.extensions.default == "recommended" and
             .inputs.security.default == "safe"' "$SETUP" >/dev/null 2>&1; then
  fail "setup workflow lacks recommended extensions and Safe security defaults (T020)"
fi
if grep -Eq 'AskUserQuestion|CLAUDE_PLUGIN_ROOT|\.claude/settings|status.?line' "$INIT_SKILL"; then
  fail "spex:init still contains Claude-only interaction or status-line behavior (T023/T024)"
fi

if [[ $FAILED -ne 0 ]]; then
  printf '\nCodex install journey: %d passed, %d failed, %d skipped\n' "$PASSED" "$FAILED" "$SKIPPED"
  exit 1
fi

if ! command -v codex >/dev/null 2>&1; then
  skip "Codex CLI is unavailable; local marketplace boundary cannot be exercised"
  printf '\nCodex install journey: %d passed, %d failed, %d skipped\n' "$PASSED" "$FAILED" "$SKIPPED"
  exit 0
fi
if ! codex plugin marketplace add --help >/dev/null 2>&1 ||
   ! codex plugin add --help >/dev/null 2>&1; then
  skip "installed Codex CLI lacks personal marketplace/plugin commands"
  printf '\nCodex install journey: %d passed, %d failed, %d skipped\n' "$PASSED" "$FAILED" "$SKIPPED"
  exit 0
fi
if ! command -v specify >/dev/null 2>&1 || ! specify workflow run --help >/dev/null 2>&1; then
  skip "Specify CLI with workflow support is unavailable"
  printf '\nCodex install journey: %d passed, %d failed, %d skipped\n' "$PASSED" "$FAILED" "$SKIPPED"
  exit 0
fi

REAL_HOME="$HOME"
REAL_CODEX_DIGEST="$(path_digest "$REAL_HOME/.codex/config.toml")"
REAL_MARKETPLACE_DIGEST="$(path_digest "$REAL_HOME/.agents/plugins/marketplace.json")"

spex_test_make_home TEST_HOME
spex_test_use_home "$TEST_HOME"
spex_test_make_temp_dir TEST_ROOT
spex_test_make_repo TEST_REPO
export TMPDIR="$TEST_ROOT/tmp"
mkdir -p "$TMPDIR"

MARKETPLACE_ROOT="$TEST_ROOT/marketplace"
PLUGIN_OUTPUT="$MARKETPLACE_ROOT/plugins/codex"
mkdir -p "$MARKETPLACE_ROOT/.codex-plugin" "$MARKETPLACE_ROOT/plugins"
cp "$CODEX_MARKETPLACE" "$MARKETPLACE_ROOT/.codex-plugin/marketplace.json"

echo "=== Local materialization and personal marketplace install ==="
materialized="$($MATERIALIZE --harness codex --output "$PLUGIN_OUTPUT")"
if jq -e --arg output "$PLUGIN_OUTPUT" \
    '.harness == "codex" and .output == $output and (.inventory | length > 0)' \
    <<< "$materialized" >/dev/null; then
  pass "Codex distribution materializes into the disposable marketplace"
else
  fail "Codex materialization did not return its expected inventory"
fi

plugin_name="$(jq -r .name "$PLUGIN_OUTPUT/.codex-plugin/plugin.json")"
marketplace_name="$(jq -r .name "$MARKETPLACE_ROOT/.codex-plugin/marketplace.json")"

marketplace_result="$(codex plugin marketplace add "$MARKETPLACE_ROOT" --json 2>&1)"
marketplace_status=$?
if [[ $marketplace_status -eq 0 ]] && jq empty <<< "$marketplace_result" >/dev/null 2>&1; then
  pass "Codex adds the disposable local marketplace"
else
  fail "Codex could not add the disposable local marketplace"
  printf '%s\n' "$marketplace_result" >&2
fi

install_result="$(codex plugin add "$plugin_name@$marketplace_name" --json 2>&1)"
install_status=$?
if [[ $install_status -eq 0 ]] && jq empty <<< "$install_result" >/dev/null 2>&1; then
  pass "Codex installs the materialized plugin"
else
  fail "Codex could not install $plugin_name@$marketplace_name"
  printf '%s\n' "$install_result" >&2
fi

plugin_list="$(codex plugin list --json 2>&1)"
if jq -e --arg name "$plugin_name" '.. | objects | select(.name? == $name)' \
    <<< "$plugin_list" >/dev/null 2>&1; then
  pass "installed plugin appears in the isolated Codex inventory"
else
  fail "installed plugin is absent from the isolated Codex inventory"
fi

if find "$PLUGIN_OUTPUT" -path '*/.claude-plugin/*' -o -path '*/.claude/*' | grep -q . ||
   grep -RIlE 'CLAUDE_PLUGIN_ROOT|AskUserQuestion|spex-ship-statusline|statusline-command' \
     "$PLUGIN_OUTPUT" >/dev/null 2>&1; then
  fail "Codex distribution leaks Claude-only paths or runtime instructions"
else
  pass "Codex distribution contains no Claude-only leakage"
fi

echo "=== Initialize, refresh, and invoke a first command ==="
mkdir -p "$TEST_REPO/.codex"
printf '[unrelated]\nkeep = true\n' > "$TEST_REPO/.codex/config.toml"
printf '# User-owned guidance\nKeep this line.\n' > "$TEST_REPO/AGENTS.md"

run_setup() {
  local -a inputs=(--input integration=codex)
  if [[ "$1" == "initial" ]]; then
    inputs+=(--input extensions=recommended --input security=safe)
  fi
  (
    cd "$TEST_REPO" || exit 1
    CODEX_SESSION_ID="spex-integration-test" SPEX_SOURCE="$PLUGIN_OUTPUT" \
      specify workflow run "$PLUGIN_OUTPUT/setup.yml" "${inputs[@]}" --json
  )
}

init_result="$(run_setup initial 2>&1)"
init_status=$?
if [[ $init_status -eq 0 ]] && jq empty <<< "$init_result" >/dev/null 2>&1; then
  pass "spex:init setup workflow completes with recommended Safe settings"
else
  fail "spex:init setup workflow failed"
  printf '%s\n' "$init_result" >&2
fi

PROFILE="$TEST_REPO/.specify/spex-profile.yml"
if [[ -f "$PROFILE" ]] && yq -e \
    '.active_harness == "codex" and .requested_security == "safe" and
     .effective_security == "safe" and
     (.enabled_extensions | contains(["spex", "spex-gates", "spex-deep-review", "spex-worktrees"])) and
     ((.enabled_extensions | index("spex-teams")) == null)' "$PROFILE" >/dev/null 2>&1; then
  pass "initialization persists the recommended Codex Safe profile"
else
  fail "initialization did not persist the recommended Codex Safe profile"
fi

profile_before="$(yq -o=json -I=0 '{enabled_extensions,requested_security,effective_security}' "$PROFILE" 2>/dev/null || true)"
revision_before="$(yq -r '.config_revision // 0' "$PROFILE" 2>/dev/null || printf 0)"
refresh_result="$(run_setup refresh 2>&1)"
refresh_status=$?
if [[ $refresh_status -eq 0 ]] && jq empty <<< "$refresh_result" >/dev/null 2>&1; then
  pass "spex:init refresh completes in the existing repository"
else
  fail "spex:init refresh failed"
  printf '%s\n' "$refresh_result" >&2
fi

profile_after="$(yq -o=json -I=0 '{enabled_extensions,requested_security,effective_security}' "$PROFILE" 2>/dev/null || true)"
revision_after="$(yq -r '.config_revision // 0' "$PROFILE" 2>/dev/null || printf 0)"
if [[ "$profile_after" == "$profile_before" && "$revision_after" -gt "$revision_before" ]]; then
  pass "refresh preserves selections and security while advancing revision"
else
  fail "refresh changed selections/security or failed to advance revision"
fi

if grep -qF 'keep = true' "$TEST_REPO/.codex/config.toml" &&
   grep -qF 'Keep this line.' "$TEST_REPO/AGENTS.md"; then
  pass "initialization preserves unrelated project configuration and guidance"
else
  fail "initialization overwrote unrelated project configuration or guidance"
fi

hook_output="$(printf '%s\n' "$(jq -cn --arg cwd "$TEST_REPO" \
  '{prompt:"/spex:help",turn_id:"integration-first-command",cwd:$cwd}')" |
  TMPDIR="$TMPDIR" python3 "$PLUGIN_OUTPUT/scripts/adapters/codex/context-hook.py" 2>&1)"
hook_status=$?
if [[ $hook_status -eq 0 ]] && jq -e \
    '.systemMessage | contains("<spex-context>") and contains("<agent>codex</agent>")' \
    <<< "$hook_output" >/dev/null 2>&1; then
  pass "first Spex command resolves through the installed Codex hook"
else
  fail "first Spex command did not resolve through the Codex hook"
  printf '%s\n' "$hook_output" >&2
fi

if [[ "$(path_digest "$REAL_HOME/.codex/config.toml")" == "$REAL_CODEX_DIGEST" &&
      "$(path_digest "$REAL_HOME/.agents/plugins/marketplace.json")" == "$REAL_MARKETPLACE_DIGEST" ]]; then
  pass "real user Codex configuration remains byte-identical"
else
  fail "integration journey mutated real user Codex configuration"
fi

printf '\nCodex install journey: %d passed, %d failed, %d skipped\n' "$PASSED" "$FAILED" "$SKIPPED"
[[ $FAILED -eq 0 ]]
