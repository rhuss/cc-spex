#!/usr/bin/env bash
# Released runtime inventory must be harness-specialized and marker-free (T065).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
MATERIALIZE="$REPO_ROOT/spex/scripts/spex-materialize-plugin.sh"

# shellcheck source=../lib/test_helpers.sh
source "$REPO_ROOT/tests/lib/test_helpers.sh"
trap spex_test_cleanup EXIT HUP INT TERM

PASSED=0
FAILED=0
pass() { printf 'PASS: %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=$((FAILED + 1)); }

for dependency in jq grep find sort; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    printf 'ERROR: required unit-test dependency missing: %s\n' "$dependency" >&2
    exit 2
  fi
done

# These files inspect or transform a staged distribution and are not runtime
# surfaces. Excluding them prevents a scanner from matching its own patterns;
# every other materialized file is release/runtime inventory and is scanned.
is_build_time_file() {
  case "$1" in
    scripts/spex-materialize-plugin.sh|\
    scripts/spex-validate-materialized.sh|\
    scripts/spex-adapt-commands.sh) return 0 ;;
    *) return 1 ;;
  esac
}

foreign_path_pattern() {
  case "$1" in
    claude) printf '%s\n' '(^|/)(\.codex-plugin|\.codex|\.opencode)(/|$)' ;;
    codex) printf '%s\n' '(^|/)(\.claude-plugin|\.claude|\.opencode)(/|$)' ;;
    opencode) printf '%s\n' '(^|/)(\.claude-plugin|\.claude|\.codex-plugin|\.codex)(/|$)' ;;
  esac
}

foreign_content_pattern() {
  case "$1" in
    claude)
      printf '%s\n' 'request_user_input|update_plan|CODEX_HOME|\.codex-plugin|\.codex/config\.toml|codex plugin|OPENCODE_|\.opencode/'
      ;;
    codex)
      printf '%s\n' 'AskUserQuestion|(^|[^[:alnum:]_])Agent tool|CLAUDE_CODE_|CLAUDE_PLUGIN_ROOT|\.claude-plugin|\.claude/settings|statusline-command|spex-ship-statusline|EnterWorktree|ExitWorktree|OPENCODE_|\.opencode/'
      ;;
    opencode)
      printf '%s\n' 'AskUserQuestion|request_user_input|update_plan|(^|[^[:alnum:]_])Agent tool|CLAUDE_CODE_|CLAUDE_PLUGIN_ROOT|CODEX_HOME|\.claude-plugin|\.claude/settings|\.codex-plugin|\.codex/config\.toml|statusline-command|spex-ship-statusline|EnterWorktree|ExitWorktree'
      ;;
  esac
}

scan_release() {
  local harness="$1" output="$2" metadata="$3"
  local inventory="$output/.runtime-inventory" markers="$output/.marker-findings"
  local references="$output/.reference-findings" path_findings="$output/.path-findings"
  local relative path_pattern content_pattern adapter_count

  : > "$inventory"
  while IFS= read -r relative; do
    is_build_time_file "$relative" || printf '%s\n' "$relative" >> "$inventory"
  done < <(jq -r '.inventory[].path' <<< "$metadata")

  # Scanner output lives beside the release only during this test and is never
  # added to the inventory, so findings cannot recursively match themselves.
  : > "$markers"
  : > "$references"
  : > "$path_findings"
  path_pattern="$(foreign_path_pattern "$harness")"
  content_pattern="$(foreign_content_pattern "$harness")"

  while IFS= read -r relative; do
    [[ -f "$output/$relative" ]] || {
      printf '%s: inventory path is missing\n' "$relative" >> "$path_findings"
      continue
    }
    if grep -Eq "$path_pattern" <<< "$relative"; then
      printf '%s\n' "$relative" >> "$path_findings"
    fi
    grep -InIH -E '\{harness:[^}]+\}|<!--[[:space:]]*/?harness:[^>]+-->' \
      "$output/$relative" >> "$markers" 2>/dev/null || true
    grep -InIH -E "$content_pattern" "$output/$relative" \
      >> "$references" 2>/dev/null || true
  done < "$inventory"

  if [[ -s "$markers" ]]; then
    fail "$harness release contains unresolved harness markers"
    sed -n '1,8p' "$markers" >&2
  else
    pass "$harness runtime inventory contains no unresolved harness markers"
  fi

  if [[ -s "$path_findings" ]]; then
    fail "$harness release contains foreign or missing runtime paths"
    sed -n '1,8p' "$path_findings" >&2
  else
    pass "$harness runtime inventory contains no foreign harness paths"
  fi

  if [[ -s "$references" ]]; then
    fail "$harness release contains foreign harness tools or references"
    sed -n '1,8p' "$references" >&2
  else
    pass "$harness runtime inventory contains no foreign harness tools or references"
  fi

  adapter_count="$(find "$output/scripts/adapters" -mindepth 1 -maxdepth 1 \
    -type d | wc -l | tr -d ' ')"
  if [[ "$adapter_count" == 1 && -f "$output/scripts/adapters/$harness/adapter.json" ]]; then
    pass "$harness release contains exactly its selected adapter"
  else
    fail "$harness release adapter inventory is ambiguous"
  fi

  rm -f -- "$inventory" "$markers" "$references" "$path_findings"
}

spex_test_make_temp_dir TEST_ROOT

for harness in claude codex opencode; do
  output="$TEST_ROOT/materialized-$harness"
  metadata="$($MATERIALIZE --harness "$harness" --output "$output" 2>/dev/null)"
  status=$?
  if [[ $status -ne 0 ]] || ! jq -e --arg harness "$harness" \
      '.harness == $harness and (.inventory | length > 0)' <<< "$metadata" >/dev/null 2>&1; then
    fail "$harness release did not materialize with a runtime inventory"
    continue
  fi
  pass "$harness release materializes for leakage scanning"
  scan_release "$harness" "$output" "$metadata"
done

printf '\nHarness leakage: %d passed, %d failed\n' "$PASSED" "$FAILED"
[[ $FAILED -eq 0 ]]
