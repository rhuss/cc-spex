#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPO_ROOT="${SPEX_TEST_REPO_ROOT:-$DEFAULT_REPO_ROOT}"
REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"

CODEX_PLUGIN_ROOT="$REPO_ROOT/plugins/codex"
CODEX_MANIFEST="$CODEX_PLUGIN_ROOT/.codex-plugin/plugin.json"
CODEX_HOOKS="$CODEX_PLUGIN_ROOT/hooks/hooks.json"
CODEX_MARKETPLACE="$REPO_ROOT/.codex-plugin/marketplace.json"
CLAUDE_MANIFEST="$REPO_ROOT/spex/.claude-plugin/plugin.json"
CLAUDE_MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"

PASSED=0
FAILED=0

pass() { printf 'PASS: %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=$((FAILED + 1)); }

assert_json_file() {
  local description="$1" path="$2"
  if [[ ! -f "$path" ]]; then
    fail "$description is missing: ${path#"$REPO_ROOT"/}"
    return 1
  fi
  if ! jq empty "$path" >/dev/null 2>&1; then
    fail "$description is not valid JSON: ${path#"$REPO_ROOT"/}"
    return 1
  fi
  pass "$description exists and is valid JSON"
}

assert_jq() {
  local description="$1" expression="$2" path="$3"
  if jq -e "$expression" "$path" >/dev/null 2>&1; then
    pass "$description"
  else
    fail "$description"
  fi
}

if ! command -v jq >/dev/null 2>&1; then
  printf 'ERROR: jq is required for Codex plugin contract tests.\n' >&2
  exit 2
fi

manifest_ready=false
hooks_ready=false
marketplace_ready=false
assert_json_file "Codex plugin manifest" "$CODEX_MANIFEST" && manifest_ready=true
assert_json_file "Codex bundled hooks" "$CODEX_HOOKS" && hooks_ready=true
assert_json_file "Codex personal marketplace" "$CODEX_MARKETPLACE" && marketplace_ready=true

if $manifest_ready; then
  assert_jq "manifest has a stable kebab-case identity" \
    '.name | type == "string" and test("^[a-z0-9]+(?:-[a-z0-9]+)*$")' "$CODEX_MANIFEST"
  assert_jq "manifest declares a semantic version" \
    '.version | type == "string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$")' "$CODEX_MANIFEST"
  assert_jq "manifest describes the plugin" \
    '.description | type == "string" and length > 0' "$CODEX_MANIFEST"
  assert_jq "manifest exposes bundled Spex skills" \
    '.skills == "./skills/"' "$CODEX_MANIFEST"
  assert_jq "manifest hook override, when present, is plugin-root relative" \
    'has("hooks") | not or
      (.hooks == "./hooks/hooks.json") or
      (.hooks | type == "array" and all(.[]; type == "string" and startswith("./") and (contains("..") | not)))' \
    "$CODEX_MANIFEST"
  assert_jq "manifest omits Claude-only metadata" \
    '([paths(scalars) as $p | getpath($p) | strings] | join("\n") |
      test("CLAUDE_PLUGIN_ROOT|\\.claude-plugin|statusline-command|spex-ship-statusline|AskUserQuestion"; "i") | not)' \
    "$CODEX_MANIFEST"
fi

if $hooks_ready; then
  command_count="$(jq '[.. | objects | select(.type? == "command") | .command] | length' "$CODEX_HOOKS")"
  if [[ "$command_count" -gt 0 ]]; then
    pass "hook declaration contains command hooks"
  else
    fail "hook declaration must contain at least one command hook"
  fi

  assert_jq "all hook commands resolve through PLUGIN_ROOT" \
    '[.. | objects | select(.type? == "command") | .command] |
      length > 0 and all(.[]; contains("${PLUGIN_ROOT}/"))' "$CODEX_HOOKS"
  assert_jq "hook paths remain inside the plugin root" \
    '[.. | objects | select(.type? == "command") | .command] |
      all(.[]; (contains("${PLUGIN_ROOT}/../") or contains("${PLUGIN_ROOT}/..\\")) | not)' "$CODEX_HOOKS"
  assert_jq "hooks omit absolute development paths and Claude-only surfaces" \
    '([paths(scalars) as $p | getpath($p) | strings] | join("\n") |
      test("CLAUDE_PLUGIN_ROOT|/Users/|/home/|/private/tmp/|\\.claude-plugin|statusline-command|spex-ship-statusline|AskUserQuestion"; "i") | not)' \
    "$CODEX_HOOKS"
fi

if $marketplace_ready; then
  assert_jq "marketplace has a nonempty identity and display name" \
    '.name | type == "string" and length > 0' "$CODEX_MARKETPLACE"
  assert_jq "marketplace exposes a display name" \
    '.interface.displayName | type == "string" and length > 0' "$CODEX_MARKETPLACE"
  assert_jq "marketplace plugin names are unique" \
    '(.plugins | type == "array") and
      ([.plugins[].name] | length == (unique | length))' "$CODEX_MARKETPLACE"
  assert_jq "marketplace entries use complete local-source metadata" \
    '.plugins | length > 0 and all(.[];
      (.name | type == "string" and length > 0) and
      .source.source == "local" and
      (.source.path | type == "string" and startswith("./") and (contains("..") | not)) and
      (.policy.installation | IN("NOT_AVAILABLE", "AVAILABLE", "INSTALLED_BY_DEFAULT")) and
      (.policy.authentication | IN("ON_INSTALL", "ON_USE")) and
      (.category | type == "string" and length > 0))' "$CODEX_MARKETPLACE"
  assert_jq "marketplace omits Claude-only paths and runtime names" \
    '([paths(scalars) as $p | getpath($p) | strings] | join("\n") |
      test("CLAUDE_PLUGIN_ROOT|\\.claude-plugin|\\./spex(?:/|$)|statusline-command|spex-ship-statusline|AskUserQuestion"; "i") | not)' \
    "$CODEX_MARKETPLACE"

  if $manifest_ready; then
    codex_name="$(jq -r .name "$CODEX_MANIFEST")"
    matching_entries="$(jq --arg name "$codex_name" '[.plugins[] | select(.name == $name)] | length' "$CODEX_MARKETPLACE")"
    if [[ "$matching_entries" -eq 1 ]]; then
      pass "marketplace contains exactly one entry for the manifest identity"
    else
      fail "marketplace must contain exactly one entry for '$codex_name'"
    fi
    if jq -e --arg name "$codex_name" \
        '.plugins[] | select(.name == $name) | .source.path == "./plugins/codex"' \
        "$CODEX_MARKETPLACE" >/dev/null 2>&1; then
      pass "Codex marketplace entry points to the Codex descriptor"
    else
      fail "Codex marketplace entry must use source.path ./plugins/codex"
    fi
  fi
fi

if $manifest_ready && [[ -f "$CLAUDE_MANIFEST" ]]; then
  codex_name="$(jq -r .name "$CODEX_MANIFEST")"
  claude_name="$(jq -r .name "$CLAUDE_MANIFEST")"
  if [[ "$codex_name" != "$claude_name" ]]; then
    pass "Codex and Claude plugin identities are collision-free"
  else
    fail "Codex plugin identity '$codex_name' collides with Claude"
  fi
fi

if $marketplace_ready && [[ -f "$CLAUDE_MARKETPLACE" ]]; then
  codex_marketplace_name="$(jq -r .name "$CODEX_MARKETPLACE")"
  claude_marketplace_name="$(jq -r .name "$CLAUDE_MARKETPLACE")"
  if [[ "$codex_marketplace_name" != "$claude_marketplace_name" ]]; then
    pass "Codex and Claude marketplace identities are collision-free"
  else
    fail "Codex marketplace identity '$codex_marketplace_name' collides with Claude"
  fi
fi

printf '\nCodex plugin manifest contract: %d passed, %d failed\n' "$PASSED" "$FAILED"
[[ $FAILED -eq 0 ]]
