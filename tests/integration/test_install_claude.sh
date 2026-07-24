#!/usr/bin/env bash
# Claude-specific disposable marketplace install/update/uninstall contract (T062).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
CLAUDE_MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"
CLAUDE_MANIFEST="$REPO_ROOT/spex/.claude-plugin/plugin.json"

# shellcheck source=../lib/test_helpers.sh
source "$REPO_ROOT/tests/lib/test_helpers.sh"
trap spex_test_cleanup EXIT HUP INT TERM

PASSED=0
FAILED=0
SKIPPED=0
PRE_FEATURE_ACCEPTANCE_RATE=100
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

summary() {
  printf '\nClaude install journey: %d passed, %d failed, %d skipped\n' \
    "$PASSED" "$FAILED" "$SKIPPED"
}

echo "=== Claude install journey prerequisites ==="
for dependency in jq git; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    printf 'ERROR: required integration-test dependency missing: %s\n' "$dependency" >&2
    exit 2
  fi
done

for artifact in "$CLAUDE_MARKETPLACE" "$CLAUDE_MANIFEST" "$REPO_ROOT/spex/hooks.json"; do
  if [[ ! -f "$artifact" ]]; then
    fail "Claude baseline artifact is missing: ${artifact#"$REPO_ROOT"/}"
  fi
done
if [[ $FAILED -ne 0 ]]; then summary; exit 1; fi

if ! command -v claude >/dev/null 2>&1; then
  skip "Claude CLI is unavailable; disposable marketplace lifecycle cannot be exercised"
  summary
  exit 0
fi
for command in marketplace install update uninstall validate; do
  if ! claude plugin "$command" --help >/dev/null 2>&1; then
    skip "installed Claude CLI lacks plugin $command support"
    summary
    exit 0
  fi
done

REAL_CLAUDE_CONFIG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
real_registry_digest() {
  path_digest "$REAL_CLAUDE_CONFIG/settings.json"
  path_digest "$REAL_CLAUDE_CONFIG/plugins/installed_plugins.json"
  path_digest "$REAL_CLAUDE_CONFIG/plugins/known_marketplaces.json"
}
REAL_CLAUDE_DIGEST="$(real_registry_digest)"

spex_test_make_home TEST_HOME
spex_test_use_home "$TEST_HOME"
spex_test_make_temp_dir TEST_ROOT
MARKETPLACE_ROOT="$TEST_ROOT/claude-marketplace"
mkdir -p "$MARKETPLACE_ROOT"
cp -R "$REPO_ROOT/.claude-plugin" "$MARKETPLACE_ROOT/.claude-plugin"
cp -R "$REPO_ROOT/spex" "$MARKETPLACE_ROOT/spex"

marketplace_name="$(jq -r .name "$MARKETPLACE_ROOT/.claude-plugin/marketplace.json")"
plugin_name="$(jq -r .name "$MARKETPLACE_ROOT/spex/.claude-plugin/plugin.json")"
plugin_version="$(jq -r .version "$MARKETPLACE_ROOT/spex/.claude-plugin/plugin.json")"
plugin_ref="$plugin_name@$marketplace_name"

echo "=== Claude baseline validation ==="
if claude plugin validate "$MARKETPLACE_ROOT" 2>&1 | grep -qi valid; then
  pass "Claude marketplace schema validates"
else
  fail "Claude marketplace schema validation failed"
fi
if claude plugin validate "$MARKETPLACE_ROOT/spex" 2>&1 | grep -qi valid; then
  pass "Claude plugin schema validates"
else
  fail "Claude plugin schema validation failed"
fi

if jq -e --arg name "$plugin_name" --arg version "$plugin_version" \
    '.plugins | any(.name == $name and .version == $version and .source == "./spex")' \
    "$MARKETPLACE_ROOT/.claude-plugin/marketplace.json" >/dev/null 2>&1 &&
   jq -e --arg name "$plugin_name" --arg version "$plugin_version" \
    '.name == $name and .version == $version and .hooks == "./hooks.json"' \
    "$MARKETPLACE_ROOT/spex/.claude-plugin/plugin.json" >/dev/null 2>&1; then
  pass "Claude marketplace and plugin preserve baseline identity, version, and hooks"
else
  fail "Claude marketplace baseline identity/version/hooks changed"
fi

echo "=== Disposable Claude marketplace install ==="
marketplace_output="$(claude plugin marketplace add "$MARKETPLACE_ROOT" 2>&1)"
marketplace_status=$?
if [[ $marketplace_status -eq 0 ]] &&
   claude plugin marketplace list 2>/dev/null | grep -qF "$marketplace_name"; then
  pass "Claude adds the disposable local marketplace"
else
  fail "Claude could not add the disposable marketplace: $marketplace_output"
fi

install_output="$(claude plugin install "$plugin_ref" 2>&1)"
install_status=$?
plugin_list="$(claude plugin list 2>&1)"
if [[ $install_status -eq 0 && "$plugin_list" == *"$plugin_ref"* ]]; then
  pass "Claude installs the plugin into the disposable home"
else
  fail "Claude could not install $plugin_ref: $install_output"
fi

CACHE_ROOT="$CLAUDE_CONFIG_DIR/plugins/cache/$marketplace_name/$plugin_name/$plugin_version"
if [[ -f "$CACHE_ROOT/hooks.json" && -x "$CACHE_ROOT/scripts/spex-init.sh" &&
      -d "$CACHE_ROOT/extensions/spex" && -d "$CACHE_ROOT/extensions/spex-gates" &&
      -d "$CACHE_ROOT/extensions/spex-worktrees" ]]; then
  pass "installed Claude cache preserves hooks, init, and baseline extensions"
else
  fail "installed Claude cache is missing baseline plugin content at $CACHE_ROOT"
fi

if find "$CACHE_ROOT" \( -path '*/.codex-plugin/*' -o -path '*/.codex/*' \) -print \
     2>/dev/null | grep -q . ||
   find "$CACHE_ROOT" -type f \( -name 'AGENTS.md' -o -name 'config.toml' \) -print \
     2>/dev/null | grep -q .; then
  fail "Claude installation leaks Codex manifest or configuration surfaces"
else
  pass "Claude installation contains no Codex manifest/configuration leakage"
fi

echo "=== Claude update and uninstall lifecycle ==="
update_output="$(claude plugin update "$plugin_ref" 2>&1)"
update_status=$?
updated_list="$(claude plugin list 2>&1)"
if [[ $update_status -eq 0 && "$updated_list" == *"$plugin_ref"* ]]; then
  pass "Claude update preserves the installed plugin inventory"
else
  fail "Claude plugin update failed: $update_output"
fi

uninstall_output="$(claude plugin uninstall "$plugin_ref" 2>&1)"
uninstall_status=$?
after_uninstall="$(claude plugin list 2>&1)"
if [[ $uninstall_status -eq 0 && "$after_uninstall" != *"$plugin_ref"* ]]; then
  pass "Claude uninstalls the plugin from the disposable home"
else
  fail "Claude plugin uninstall failed: $uninstall_output"
fi

remove_output="$(claude plugin marketplace remove "$marketplace_name" 2>&1)"
remove_status=$?
if [[ $remove_status -eq 0 ]] &&
   ! claude plugin marketplace list 2>/dev/null | grep -qF "$marketplace_name"; then
  pass "Claude removes the disposable marketplace"
else
  fail "Claude marketplace removal failed: $remove_output"
fi

if [[ "$(real_registry_digest)" == "$REAL_CLAUDE_DIGEST" ]]; then
  pass "real user Claude configuration remains byte-identical"
else
  fail "Claude integration journey mutated the real user configuration"
fi

summary
executed=$((PASSED + FAILED))
if [[ $executed -gt 0 ]]; then
  current_rate=$((PASSED * 100 / executed))
  if [[ $current_rate -lt $PRE_FEATURE_ACCEPTANCE_RATE ]]; then
    fail "Claude acceptance rate regressed: ${current_rate}% < ${PRE_FEATURE_ACCEPTANCE_RATE}% baseline"
  else
    pass "Claude acceptance rate meets the ${PRE_FEATURE_ACCEPTANCE_RATE}% pre-feature baseline"
  fi
fi
[[ $FAILED -eq 0 ]]
