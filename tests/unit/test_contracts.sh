#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCHEMA_DIR="$REPO_ROOT/specs/047-codex-plugin-support/contracts"
FIXTURE_ROOT="$REPO_ROOT/tests/fixtures/contracts"

# Accept a command plus arguments so callers can use an isolated runner such as
# `JSON_SCHEMA_VALIDATOR="uvx check-jsonschema"` without installing globally.
read -r -a VALIDATOR_CMD <<< "${JSON_SCHEMA_VALIDATOR:-check-jsonschema}"

PASSED=0
FAILED=0

pass() {
  printf 'PASS: %s\n' "$1"
  PASSED=$((PASSED + 1))
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  FAILED=$((FAILED + 1))
}

run_validator() {
  "${VALIDATOR_CMD[@]}" "$@"
}

if [[ ${#VALIDATOR_CMD[@]} -eq 0 ]] || ! command -v "${VALIDATOR_CMD[0]}" >/dev/null 2>&1; then
  printf 'ERROR: JSON Schema validator not found: %s\n' "${VALIDATOR_CMD[0]:-<empty>}" >&2
  printf 'Install check-jsonschema or set JSON_SCHEMA_VALIDATOR to a compatible command.\n' >&2
  exit 2
fi

if [[ ! -d "$SCHEMA_DIR" || ! -d "$FIXTURE_ROOT" ]]; then
  printf 'ERROR: contract schemas or fixtures are missing.\n' >&2
  exit 2
fi

shopt -s nullglob
schemas=("$SCHEMA_DIR"/*.schema.json)
if [[ ${#schemas[@]} -eq 0 ]]; then
  printf 'ERROR: no contract schemas found in %s\n' "$SCHEMA_DIR" >&2
  exit 2
fi

for schema in "${schemas[@]}"; do
  contract="$(basename "$schema" .schema.json)"
  fixture_dir="$FIXTURE_ROOT/$contract"

  schema_output="$(run_validator --check-metaschema "$schema" 2>&1)"
  schema_status=$?
  if [[ $schema_status -eq 0 ]]; then
    pass "$contract schema satisfies its metaschema"
  else
    fail "$contract schema failed metaschema validation"
    printf '%s\n' "$schema_output" >&2
    continue
  fi

  if [[ ! -d "$fixture_dir" ]]; then
    fail "$contract has no fixture directory"
    continue
  fi

  valid_fixtures=("$fixture_dir"/valid*.json)
  invalid_fixtures=("$fixture_dir"/invalid*.json)
  if [[ ${#valid_fixtures[@]} -eq 0 ]]; then
    fail "$contract has no valid fixtures"
  fi
  if [[ ${#invalid_fixtures[@]} -eq 0 ]]; then
    fail "$contract has no invalid fixtures"
  fi

  for fixture in "${valid_fixtures[@]}"; do
    fixture_output="$(run_validator --base-uri "file://$SCHEMA_DIR/" --schemafile "$schema" "$fixture" 2>&1)"
    fixture_status=$?
    if [[ $fixture_status -eq 0 ]]; then
      pass "$contract/$(basename "$fixture") accepted"
    else
      fail "$contract/$(basename "$fixture") should be valid"
      printf '%s\n' "$fixture_output" >&2
    fi
  done

  for fixture in "${invalid_fixtures[@]}"; do
    fixture_output="$(run_validator --base-uri "file://$SCHEMA_DIR/" --schemafile "$schema" "$fixture" 2>&1)"
    fixture_status=$?
    if [[ $fixture_status -ne 0 ]] && grep -q "Schema validation errors were encountered" <<< "$fixture_output"; then
      pass "$contract/$(basename "$fixture") rejected"
    elif [[ $fixture_status -ne 0 ]]; then
      fail "$contract/$(basename "$fixture") could not be validated"
      printf '%s\n' "$fixture_output" >&2
    else
      fail "$contract/$(basename "$fixture") should be invalid"
      printf 'Validator output:\n%s\n' "$fixture_output" >&2
    fi
  done
done

for fixture_dir in "$FIXTURE_ROOT"/*; do
  [[ -d "$fixture_dir" ]] || continue
  contract="$(basename "$fixture_dir")"
  if [[ ! -f "$SCHEMA_DIR/$contract.schema.json" ]]; then
    fail "$contract fixtures have no matching schema"
  fi
done

printf '\nContract validation: %d passed, %d failed\n' "$PASSED" "$FAILED"
[[ $FAILED -eq 0 ]]
