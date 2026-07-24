#!/usr/bin/env bash
# Combined Claude and Codex coexistence contract (T063).
# Uses disposable homes/repositories and local materialization; no client or
# network access is required.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
MATERIALIZE="$REPO_ROOT/spex/scripts/spex-materialize-plugin.sh"
CLAUDE_DESCRIPTOR="$REPO_ROOT/plugins/claude/adapter.json"
CLAUDE_MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"
CODEX_MARKETPLACE="$REPO_ROOT/.codex-plugin/marketplace.json"
CODEX_CONFIGURE="$REPO_ROOT/spex/scripts/adapters/codex/configure-project.py"

for dependency in git jq python3; do
  command -v "$dependency" >/dev/null 2>&1 || {
    echo "ERROR: required integration dependency is missing: $dependency" >&2
    exit 2
  }
done

# Fail once at the missing US6 packaging boundary. The remaining assertions
# become meaningful after T066 gives Claude an explicit distribution owner.
if [[ ! -f "$CLAUDE_DESCRIPTOR" ]]; then
  echo "FAIL: combined installation requires the thin Claude distribution descriptor." >&2
  echo "T063 requires plugins/claude/adapter.json from T066 before coexistence can be verified." >&2
  exit 1
fi

# shellcheck source=../lib/test_helpers.sh
source "$REPO_ROOT/tests/lib/test_helpers.sh"
trap spex_test_cleanup EXIT HUP INT TERM

PASSED=0
FAILED=0
pass() { printf 'PASS: %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=$((FAILED + 1)); }

digest() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  else
    shasum -a 256 "$path" | awk '{print $1}'
  fi
}

copy_distribution() {
  local source="$1" destination="$2"
  mkdir -p "$(dirname "$destination")"
  cp -R "$source" "$destination"
}

spex_test_make_home TEST_HOME
spex_test_use_home "$TEST_HOME"
spex_test_make_temp_dir TEST_ROOT
spex_test_make_repo TEST_REPO

CLAUDE_OUTPUT="$TEST_ROOT/distributions/claude"
CODEX_OUTPUT="$TEST_ROOT/distributions/codex"
mkdir -p "$TEST_ROOT/distributions"

echo "=== Materialize collision-free harness distributions ==="
claude_metadata="$("$MATERIALIZE" --harness claude --output "$CLAUDE_OUTPUT")"
claude_status=$?
codex_metadata="$("$MATERIALIZE" --harness codex --output "$CODEX_OUTPUT")"
codex_status=$?
if [[ $claude_status -eq 0 && $codex_status -eq 0 ]] &&
   jq -e '.harness == "claude" and (.inventory | length > 0)' \
     <<<"$claude_metadata" >/dev/null 2>&1 &&
   jq -e '.harness == "codex" and (.inventory | length > 0)' \
     <<<"$codex_metadata" >/dev/null 2>&1; then
  pass "Claude and Codex materialize independently with inventories"
else
  fail "combined materialization failed"
fi

CLAUDE_MANIFEST="$CLAUDE_OUTPUT/.claude-plugin/plugin.json"
CODEX_MANIFEST="$CODEX_OUTPUT/.codex-plugin/plugin.json"
CLAUDE_ADAPTER="$CLAUDE_OUTPUT/scripts/adapters/claude/adapter.json"
CODEX_ADAPTER="$CODEX_OUTPUT/scripts/adapters/codex/adapter.json"

claude_plugin="$(jq -r '.name // empty' "$CLAUDE_MANIFEST")"
codex_plugin="$(jq -r '.name // empty' "$CODEX_MANIFEST")"
claude_market="$(jq -r '.name // empty' "$CLAUDE_MARKETPLACE")"
codex_market="$(jq -r '.name // empty' "$CODEX_MARKETPLACE")"
if [[ -n "$claude_plugin" && -n "$codex_plugin" &&
      "$claude_plugin" != "$codex_plugin" &&
      -n "$claude_market" && -n "$codex_market" &&
      "$claude_market" != "$codex_market" ]] &&
   jq -e '.id == "claude" and .manifest_root == ".claude-plugin" and
          .config_root == ".claude"' "$CLAUDE_ADAPTER" >/dev/null &&
   jq -e '.id == "codex" and .manifest_root == ".codex-plugin" and
          .config_root == ".codex"' "$CODEX_ADAPTER" >/dev/null; then
  pass "manifest, marketplace, adapter, and config-root identities are disjoint"
else
  fail "combined distribution identities collide"
fi

if [[ ! -e "$CLAUDE_OUTPUT/.codex-plugin" && ! -e "$CLAUDE_OUTPUT/.codex" &&
      ! -e "$CODEX_OUTPUT/.claude-plugin" && ! -e "$CODEX_OUTPUT/.claude" ]]; then
  pass "each generated distribution excludes the other harness roots"
else
  fail "generated distribution artifacts contain foreign harness roots"
fi

echo "=== Install into disposable marketplace and cache namespaces ==="
CLAUDE_MARKET_INSTALL="$CLAUDE_CONFIG_DIR/plugins/marketplaces/$claude_market/marketplace.json"
CODEX_MARKET_INSTALL="$CODEX_HOME/plugins/marketplaces/$codex_market/marketplace.json"
mkdir -p "$(dirname "$CLAUDE_MARKET_INSTALL")" "$(dirname "$CODEX_MARKET_INSTALL")"
cp "$CLAUDE_MARKETPLACE" "$CLAUDE_MARKET_INSTALL"
cp "$CODEX_MARKETPLACE" "$CODEX_MARKET_INSTALL"

claude_version="$(jq -r '.version' "$CLAUDE_MANIFEST")"
codex_version="$(jq -r '.version' "$CODEX_MANIFEST")"
CLAUDE_CACHE="$CLAUDE_CONFIG_DIR/plugins/cache/$claude_market/$claude_plugin/$claude_version"
CODEX_CACHE="$CODEX_HOME/plugins/cache/$codex_market/$codex_plugin/$codex_version"
copy_distribution "$CLAUDE_OUTPUT" "$CLAUDE_CACHE"
copy_distribution "$CODEX_OUTPUT" "$CODEX_CACHE"

if [[ "$CLAUDE_CACHE" != "$CODEX_CACHE" &&
      -f "$CLAUDE_CACHE/.claude-plugin/plugin.json" &&
      -f "$CODEX_CACHE/.codex-plugin/plugin.json" ]] &&
   [[ "$(jq -r .name "$CLAUDE_CACHE/.claude-plugin/plugin.json")" == "$claude_plugin" ]] &&
   [[ "$(jq -r .name "$CODEX_CACHE/.codex-plugin/plugin.json")" == "$codex_plugin" ]]; then
  pass "marketplace and plugin cache installations use separate namespaces"
else
  fail "combined cache installation overwrote or misidentified a plugin"
fi

CLAUDE_HOOKS="$CLAUDE_CACHE/hooks.json"
CODEX_HOOKS="$CODEX_CACHE/hooks/hooks.json"
if [[ -f "$CLAUDE_HOOKS" && -f "$CODEX_HOOKS" ]] &&
   grep -qF 'CLAUDE_PLUGIN_ROOT' "$CLAUDE_HOOKS" &&
   ! grep -qF 'CLAUDE_PLUGIN_ROOT' "$CODEX_HOOKS" &&
   grep -qF 'PLUGIN_ROOT' "$CODEX_HOOKS" &&
   ! grep -qF 'scripts/adapters/codex' "$CLAUDE_HOOKS"; then
  pass "hook registrations resolve only through their owning plugin roots"
else
  fail "combined hook identities or command roots collide"
fi

echo "=== Coexist in one disposable project ==="
mkdir -p "$TEST_REPO/.claude"
cat >"$TEST_REPO/.claude/settings.json" <<EOF
{
  "enabledPlugins": {"$claude_plugin@$claude_market": true},
  "hooks": "$CLAUDE_CACHE/hooks.json"
}
EOF
CLAUDE_CONFIG_BEFORE="$(digest "$TEST_REPO/.claude/settings.json")"
mkdir -p "$TEST_REPO/.codex"
printf '[project]\nharness = "codex"\n' >"$TEST_REPO/.codex/config.toml"

codex_configured="$(python3 "$CODEX_CONFIGURE" configure \
  --root "$TEST_REPO" --security safe \
  --capabilities-json '{"codex_available":true,"native_task_progress":true}' 2>&1)"
codex_config_status=$?
if [[ $codex_config_status -eq 0 ]] &&
   jq -e '.status == "configured" and .effective_security == "safe"' \
     <<<"$codex_configured" >/dev/null 2>&1 &&
   [[ "$(digest "$TEST_REPO/.claude/settings.json")" == "$CLAUDE_CONFIG_BEFORE" ]] &&
   grep -qF 'harness = "codex"' "$TEST_REPO/.codex/config.toml"; then
  pass "Codex project configuration coexists without changing Claude settings"
else
  fail "project configuration namespaces overwrite or misidentify each other"
fi

printf 'claude-generated\n' >"$TEST_REPO/.claude/spex-generated.txt"
printf 'codex-generated\n' >"$TEST_REPO/.codex/spex-generated.txt"
if [[ "$(<"$TEST_REPO/.claude/spex-generated.txt")" == "claude-generated" &&
      "$(<"$TEST_REPO/.codex/spex-generated.txt")" == "codex-generated" ]] &&
   grep -qF "$claude_plugin@$claude_market" "$TEST_REPO/.claude/settings.json" &&
   grep -qF 'harness = "codex"' "$TEST_REPO/.codex/config.toml"; then
  pass "generated artifacts retain harness-specific identity in one repository"
else
  fail "generated project artifacts collide across harnesses"
fi

if [[ -f "$CLAUDE_MARKET_INSTALL" && -f "$CODEX_MARKET_INSTALL" &&
      -f "$CLAUDE_CACHE/.claude-plugin/plugin.json" &&
      -f "$CODEX_CACHE/.codex-plugin/plugin.json" ]]; then
  pass "combined installation leaves both marketplaces and caches intact"
else
  fail "one harness installation removed the other harness state"
fi

printf '\nCombined installation: %d passed, %d failed\n' "$PASSED" "$FAILED"
[[ $FAILED -eq 0 ]]
