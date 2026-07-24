#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MATERIALIZE="$REPO_ROOT/spex/scripts/spex-materialize-plugin.sh"
VALIDATE="$REPO_ROOT/spex/scripts/spex-validate-materialized.sh"

source "$REPO_ROOT/tests/lib/test_helpers.sh"
trap spex_test_cleanup EXIT HUP INT TERM

PASSED=0
FAILED=0

pass() { printf 'PASS: %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=$((FAILED + 1)); }

assert_eq() {
  local description="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then pass "$description"; else
    fail "$description (expected '$expected', got '$actual')"
  fi
}

assert_file() {
  local description="$1" path="$2"
  if [[ -f "$path" ]]; then pass "$description"; else fail "$description (missing $path)"; fi
}

tree_digest() {
  local root="$1"
  (
    cd "$root" || exit 1
    find . -type f -print | LC_ALL=C sort | while IFS= read -r file; do
      hash_file "$file"
    done | hash_stream
  )
}

if command -v sha256sum >/dev/null 2>&1; then
  hash_file() { sha256sum "$1"; }
  hash_stream() { sha256sum | awk '{print $1}'; }
elif command -v shasum >/dev/null 2>&1; then
  hash_file() { shasum -a 256 "$1"; }
  hash_stream() { shasum -a 256 | awk '{print $1}'; }
else
  printf 'ERROR: sha256sum or shasum is required\n' >&2
  exit 2
fi

diagnostic_codes() {
  jq -r '.diagnostics[].code' <<< "$1"
}

assert_invalid_with() {
  local description="$1" harness="$2" input="$3" expected_code="$4"
  local output result
  output="$($VALIDATE --harness "$harness" --input "$input" 2>&1)"
  result=$?
  if [[ $result -ne 0 ]] && jq -e --arg code "$expected_code" \
      '.status == "invalid" and any(.diagnostics[]; .code == $code)' <<< "$output" >/dev/null; then
    pass "$description"
  else
    fail "$description (expected diagnostic '$expected_code')"
    printf '%s\n' "$output" >&2
  fi
}

make_synthetic_distribution() {
  local harness="$1" destination="$2" manifest_root config_root
  case "$harness" in
    claude) manifest_root=".claude-plugin"; config_root=".claude" ;;
    codex) manifest_root=".codex-plugin"; config_root=".codex" ;;
    opencode) manifest_root=".opencode"; config_root=".opencode" ;;
  esac
  mkdir -p "$destination/$manifest_root"
  jq -n \
    --arg id "$harness" \
    --arg manifest_root "$manifest_root" \
    --arg config_root "$config_root" \
    '{
      schema_version: "1.0.0",
      id: $id,
      version: "1.0.0",
      manifest_root: $manifest_root,
      config_root: $config_root,
      capabilities: {},
      permission_profiles: {safe: {}, autonomous: {}, yolo: {}}
    }' > "$destination/adapter.json"
  printf 'synthetic distribution\n' > "$destination/$manifest_root/manifest.txt"
}

make_repo_copy() {
  local destination="$1"
  mkdir -p "$destination"
  cp -R "$REPO_ROOT/spex" "$destination/spex"
  cp -R "$REPO_ROOT/plugins" "$destination/plugins"
}

for dependency in jq find; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    printf 'ERROR: required test dependency missing: %s\n' "$dependency" >&2
    exit 2
  fi
done

spex_test_make_temp_dir test_root
source_digest_before="$(tree_digest "$REPO_ROOT/spex")"

for harness in claude codex opencode; do
  output="$test_root/materialized-$harness"
  metadata="$($MATERIALIZE --harness "$harness" --output "$output")"
  result=$?
  if [[ $result -eq 0 ]] && jq -e --arg harness "$harness" \
      '.schema_version == "1.0.0" and .harness == $harness and
       (.digest | startswith("sha256:")) and (.inventory | length > 0)' \
      <<< "$metadata" >/dev/null; then
    pass "$harness materializes with inventory and digest"
  else
    fail "$harness materialization smoke test"
    continue
  fi
  assert_file "$harness stages its adapter" "$output/scripts/adapters/$harness/adapter.json"
  foreign_count="$(find "$output/scripts/adapters" -mindepth 1 -maxdepth 1 -type d ! -name "$harness" | wc -l | tr -d ' ')"
  assert_eq "$harness excludes foreign adapters" "0" "$foreign_count"

  validation="$($VALIDATE --harness "$harness" --input "$output" 2>&1)"
  validation_result=$?
  if [[ $validation_result -eq 0 || $validation_result -eq 1 ]] &&
      jq -e --arg harness "$harness" '.harness == $harness and
        (.status == "valid" or .status == "invalid") and (.inventory.file_count > 0)' \
        <<< "$validation" >/dev/null; then
    pass "$harness materialized output produces a structured validation result"
  else
    fail "$harness materialized output could not be validated"
  fi
done

source_digest_after="$(tree_digest "$REPO_ROOT/spex")"
assert_eq "materialization leaves canonical sources byte-identical" "$source_digest_before" "$source_digest_after"

# Replacing an existing output must be deterministic and remove stale content.
claude_output="$test_root/materialized-claude"
first_metadata="$($MATERIALIZE --harness claude --output "$claude_output")"
printf 'stale\n' > "$claude_output/stale-file"
second_metadata="$($MATERIALIZE --harness claude --output "$claude_output")"
assert_eq "repeated materialization has the same digest" \
  "$(jq -r .digest <<< "$first_metadata")" "$(jq -r .digest <<< "$second_metadata")"
assert_eq "repeated materialization has the same inventory" \
  "$(jq -cS .inventory <<< "$first_metadata")" "$(jq -cS .inventory <<< "$second_metadata")"
if [[ ! -e "$claude_output/stale-file" ]]; then pass "atomic replacement removes stale output"; else
  fail "atomic replacement retained stale output"
fi

# Force publication failure after the prior output has moved to its backup.
fake_bin="$test_root/fake-bin"
mkdir -p "$fake_bin"
real_mv="$(command -v mv)"
cat > "$fake_bin/mv" <<'EOF'
#!/usr/bin/env bash
if [[ "${2:-}" == *.stage.* ]]; then
  exit 73
fi
exec "$SPEX_TEST_REAL_MV" "$@"
EOF
chmod +x "$fake_bin/mv"
printf 'must survive\n' > "$claude_output/restoration-sentinel"
PATH="$fake_bin:$PATH" SPEX_TEST_REAL_MV="$real_mv" \
  "$MATERIALIZE" --harness claude --output "$claude_output" >/dev/null 2>&1
publish_result=$?
if [[ $publish_result -ne 0 && -f "$claude_output/restoration-sentinel" ]]; then
  pass "failed atomic publication restores the previous output"
else
  fail "failed atomic publication did not restore the previous output"
fi

# Adapter input errors are exercised in isolated repository copies.
malformed_root="$test_root/malformed-repo"
make_repo_copy "$malformed_root"
printf '{ malformed\n' > "$malformed_root/spex/scripts/adapters/claude/adapter.json"
malformed_message="$($malformed_root/spex/scripts/spex-materialize-plugin.sh \
  --harness claude --output "$test_root/malformed-output" 2>&1)"
malformed_result=$?
if [[ $malformed_result -ne 0 && "$malformed_message" == *"not valid JSON"* ]]; then
  pass "malformed adapter is rejected"
else
  fail "malformed adapter was not rejected clearly"
fi

missing_map_root="$test_root/missing-map-repo"
make_repo_copy "$missing_map_root"
missing_map="$missing_map_root/spex/scripts/adapters/claude/command-map.json"
mv "$missing_map" "$missing_map.absent"
missing_map_message="$($missing_map_root/spex/scripts/spex-materialize-plugin.sh \
  --harness claude --output "$test_root/missing-map-output" 2>&1)"
missing_map_result=$?
if [[ $missing_map_result -ne 0 && "$missing_map_message" == *"command map not found"* ]]; then
  pass "missing command map is rejected"
else
  fail "missing command map was not rejected clearly"
fi

# A clean synthetic distribution proves the positive validator path.
valid_stage="$test_root/valid-codex"
make_synthetic_distribution codex "$valid_stage"
valid_result="$($VALIDATE --harness codex --input "$valid_stage")"
if jq -e '.status == "valid" and .diagnostics == [] and .inventory.file_count > 0' \
    <<< "$valid_result" >/dev/null; then
  pass "clean synthetic distribution validates"
else
  fail "clean synthetic distribution should validate"
fi

marker_stage="$test_root/leak-marker"
make_synthetic_distribution codex "$marker_stage"
printf '{harness:interactive-choice}\n' > "$marker_stage/marker.md"
assert_invalid_with "unresolved harness marker is refused" codex "$marker_stage" unresolved_harness_marker

foreign_reference_stage="$test_root/leak-reference"
make_synthetic_distribution codex "$foreign_reference_stage"
printf 'Use AskUserQuestion for this choice.\n' > "$foreign_reference_stage/instructions.md"
assert_invalid_with "foreign harness reference is refused" codex "$foreign_reference_stage" foreign_harness_reference

absolute_path_stage="$test_root/leak-absolute"
make_synthetic_distribution codex "$absolute_path_stage"
printf 'Generated at /Users/example/cc-spex/output\n' > "$absolute_path_stage/build.txt"
assert_invalid_with "absolute development path is refused" codex "$absolute_path_stage" absolute_development_path

identity_stage="$test_root/leak-identity"
make_synthetic_distribution codex "$identity_stage"
jq '.manifest_root = ".claude-plugin"' "$identity_stage/adapter.json" > "$identity_stage/adapter.tmp"
mv "$identity_stage/adapter.tmp" "$identity_stage/adapter.json"
assert_invalid_with "cross-harness distribution identity is refused" codex "$identity_stage" distribution_identity_collision

inventory_stage="$test_root/leak-inventory"
make_synthetic_distribution codex "$inventory_stage"
mkdir -p "$inventory_stage/.claude"
printf '{}\n' > "$inventory_stage/.claude/settings.json"
assert_invalid_with "foreign harness inventory path is refused" codex "$inventory_stage" foreign_harness_path

printf '\nMaterialization validation: %d passed, %d failed\n' "$PASSED" "$FAILED"
[[ $FAILED -eq 0 ]]
