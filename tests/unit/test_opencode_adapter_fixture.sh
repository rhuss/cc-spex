#!/usr/bin/env bash
# Representative minimal OpenCode adapter reuse contract (T064).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
FIXTURE_ROOT="$REPO_ROOT/tests/fixtures/adapters/opencode-minimal"
FIXTURE_ADAPTER="$FIXTURE_ROOT/adapter.json"
MATERIALIZER_REL="spex/scripts/spex-materialize-plugin.sh"
VALIDATOR_REL="spex/scripts/spex-validate-materialized.sh"

for dependency in jq find git; do
  command -v "$dependency" >/dev/null 2>&1 || {
    echo "ERROR: required unit-test dependency is missing: $dependency" >&2
    exit 2
  }
done
[[ -f "$FIXTURE_ADAPTER" ]] || {
  echo "ERROR: minimal OpenCode adapter fixture is missing: $FIXTURE_ADAPTER" >&2
  exit 2
}

# shellcheck source=../lib/test_helpers.sh
source "$REPO_ROOT/tests/lib/test_helpers.sh"
trap spex_test_cleanup EXIT HUP INT TERM

PASSED=0
FAILED=0
pass() { printf 'PASS: %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=$((FAILED + 1)); }

echo "=== Minimal adapter declaration ==="
if jq -e '
    .schema_version == "1.0.0" and .id == "opencode" and
    (.version | type == "string" and length > 0) and
    .manifest_root == ".opencode" and .config_root == ".opencode" and
    (.command_map | type == "string" and length > 0) and
    (.hook_adapter | type == "string" and length > 0) and
    ((.progress_adapter == null) or (.progress_adapter | type == "string")) and
    ((.subagent_adapter == null) or (.subagent_adapter | type == "string")) and
    (.permission_profiles | keys | sort) == ["autonomous","safe","yolo"] and
    ([.capabilities[].status] |
      all(. == "native" or . == "adapted" or . == "degraded" or . == "unavailable")) and
    ((keys - ["schema_version","id","version","manifest_root","config_root",
      "command_map","hook_adapter","progress_adapter","subagent_adapter",
      "capabilities","permission_profiles"]) | length) == 0
  ' "$FIXTURE_ADAPTER" >/dev/null 2>&1; then
  pass "minimal OpenCode adapter satisfies the HarnessAdapter schema shape"
else
  fail "minimal OpenCode adapter does not satisfy the HarnessAdapter schema shape"
fi

if jq -e '
    [.capabilities | to_entries[] |
      select(.value.status == "degraded" or .value.status == "unavailable")] as $reduced |
    ($reduced | length) > 0 and
    all($reduced[];
      (.value.reason | type == "string" and length > 0) and
      (.value.fallback | type == "string" and length > 0)) and
    .capabilities.permissions.status == "degraded" and
    .capabilities.progress.status == "degraded" and
    .capabilities.subagents.status == "unavailable"
  ' "$FIXTURE_ADAPTER" >/dev/null 2>&1; then
  pass "every reduced OpenCode capability has an explicit reason and safe fallback"
else
  fail "OpenCode degradation summary is incomplete or implicit"
fi

fixture_files="$(find "$FIXTURE_ROOT" -type f | LC_ALL=C sort)"
fixture_file_count="$(wc -l <<<"$fixture_files" | tr -d '[:space:]')"
if [[ "$fixture_file_count" -eq 1 && "$fixture_files" == "$FIXTURE_ADAPTER" ]] &&
   [[ ! -d "$FIXTURE_ROOT/extensions" && ! -d "$FIXTURE_ROOT/commands" &&
      ! -d "$FIXTURE_ROOT/skills" && ! -d "$FIXTURE_ROOT/workflows" ]]; then
  pass "minimal adapter fixture does not copy or fork the shared workflow tree"
else
  fail "minimal adapter fixture contains harness-local workflow copies: $fixture_files"
fi

echo "=== Canonical workflow reuse during materialization ==="
spex_test_make_temp_dir TEST_ROOT
FIXTURE_REPO="$TEST_ROOT/fixture-repository"
mkdir -p "$FIXTURE_REPO"
cp -R "$REPO_ROOT/spex" "$FIXTURE_REPO/spex"
cp -R "$REPO_ROOT/plugins" "$FIXTURE_REPO/plugins"

# Install only the fixture declaration. Its command map and hook references are
# deliberately resolved from the canonical OpenCode specialization beside it;
# all workflows continue to come from the one shared spex/extensions tree.
cp "$FIXTURE_ADAPTER" "$FIXTURE_REPO/spex/scripts/adapters/opencode/adapter.json"

OUTPUT="$TEST_ROOT/materialized-opencode"
MATERIALIZE_STDERR="$TEST_ROOT/materialize.stderr"
metadata="$("$FIXTURE_REPO/$MATERIALIZER_REL" --harness opencode --output "$OUTPUT" 2>"$MATERIALIZE_STDERR")"
materialize_status=$?
if [[ "$materialize_status" -eq 0 ]] &&
   jq -e '.harness == "opencode" and
     (.digest | startswith("sha256:")) and (.inventory | length > 0)' \
     <<<"$metadata" >/dev/null 2>&1; then
  pass "minimal adapter materializes by reusing the canonical OpenCode specialization"
else
  fail "minimal adapter could not materialize from canonical sources: $metadata $(<"$MATERIALIZE_STDERR")"
fi

SOURCE_COMMANDS="$TEST_ROOT/source-commands.txt"
OUTPUT_COMMANDS="$TEST_ROOT/output-commands.txt"
(
  cd "$FIXTURE_REPO/spex" || exit 1
  find extensions -path '*/commands/*.md' -type f | LC_ALL=C sort
) >"$SOURCE_COMMANDS"
(
  cd "$OUTPUT" || exit 1
  find extensions -path '*/commands/*.md' -type f | LC_ALL=C sort
) >"$OUTPUT_COMMANDS"

if cmp -s "$SOURCE_COMMANDS" "$OUTPUT_COMMANDS" &&
   [[ -s "$OUTPUT_COMMANDS" ]] &&
   [[ -f "$OUTPUT/extensions/spex/commands/speckit.spex.ship.md" ]]; then
  pass "materialization reuses the complete shared canonical workflow inventory"
else
  fail "materialized OpenCode workflow inventory diverges from the shared canonical tree"
fi

fixture_relative="${FIXTURE_ROOT#"$REPO_ROOT/"}"
if ! find "$OUTPUT" -type f -print0 |
    xargs -0 grep -IlF "$fixture_relative" 2>/dev/null |
    grep -q .; then
  pass "materialized workflows do not retain fixture paths or copied fixture ownership"
else
  fail "materialized output leaks the fixture path instead of shared workflow ownership"
fi

echo "=== Release validation ==="
validation="$("$FIXTURE_REPO/$VALIDATOR_REL" --harness opencode --input "$OUTPUT" 2>&1)"
validation_status=$?
if [[ "$validation_status" -eq 0 ]] &&
   jq -e '.status == "valid" and .harness == "opencode" and
     .diagnostics == [] and (.inventory.file_count > 0)' \
     <<<"$validation" >/dev/null 2>&1; then
  pass "minimal OpenCode adapter materialization is release-valid"
else
  codes="$(jq -r '[.diagnostics[].code] | unique | join(",")' \
    <<<"$validation" 2>/dev/null || printf 'unstructured-validator-output')"
  fail "minimal OpenCode adapter materialization is not release-valid (diagnostics: $codes)"
fi

printf '\nOpenCode adapter fixture: %d passed, %d failed\n' "$PASSED" "$FAILED"
[[ "$FAILED" -eq 0 ]]
