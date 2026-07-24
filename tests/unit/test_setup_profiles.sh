#!/usr/bin/env bash
# Contract tests for setup extension/security defaults and refresh behavior.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUP="$REPO_ROOT/spex/setup.yml"

PASSED=0
FAILED=0

pass() { printf 'PASS: %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAILED=$((FAILED + 1)); }

assert_eq() {
  local description="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$description"
  else
    fail "$description (expected '$expected', got '${actual:-<empty>}')"
  fi
}

assert_contains() {
  local description="$1" content="$2" expected="$3"
  if grep -qF -- "$expected" <<< "$content"; then
    pass "$description"
  else
    fail "$description (missing '$expected')"
  fi
}

assert_not_contains() {
  local description="$1" content="$2" unexpected="$3"
  if grep -qF -- "$unexpected" <<< "$content"; then
    fail "$description (unexpected '$unexpected')"
  else
    pass "$description"
  fi
}

if ! command -v yq >/dev/null 2>&1; then
  printf 'ERROR: yq is required to inspect spex/setup.yml\n' >&2
  exit 2
fi
if [[ ! -f "$SETUP" ]]; then
  printf 'ERROR: setup workflow not found: %s\n' "$SETUP" >&2
  exit 2
fi
if ! yq -e '.' "$SETUP" >/dev/null 2>&1; then
  printf 'ERROR: setup workflow is not valid YAML\n' >&2
  exit 2
fi

# A clean initialization recommends the core quality/isolation set. Optional
# workflow modes are available, but never selected without explicit consent.
extensions_default="$(yq -r '.inputs.extensions.default // ""' "$SETUP")"
assert_eq "clean setup uses recommended extension profile" "recommended" "$extensions_default"

recommended_case="$(yq -r '[.steps[] | select(.id == "select-extensions") | .cases.recommended[]? | .run // ""] | join("\n")' "$SETUP")"
if [[ -n "$recommended_case" ]]; then
  pass "recommended extension case is declared"
else
  fail "recommended extension case is declared"
fi
for extension in spex-gates spex-deep-review spex-worktrees; do
  assert_contains "recommended profile includes $extension" "$recommended_case" "$extension"
done

optional_policy="$(yq -r '[.steps[] | select(.id == "select-extensions") | .cases.recommended[]? | (.run // ""), (.prompt // "")] | join("\n")' "$SETUP")"
for extension in spex-teams spex-collab spex-detach; do
  assert_contains "recommended profile handles optional $extension" "$optional_policy" "$extension"
done
if [[ "$optional_policy" == *"specify extension disable"* ]]; then
  pass "recommended profile disables unselected optional extensions"
else
  fail "recommended profile disables unselected optional extensions"
fi

interactive_policy="$(yq -r '[.steps[] | select(.id == "select-extensions") | .cases.interactive[]? | (.run // ""), (.prompt // "")] | join("\n")' "$SETUP")"
for extension in spex-teams spex-collab spex-detach; do
  assert_contains "$extension can be explicitly selected" "$interactive_policy" "$extension"
done
if grep -qi 'experimental' <<< "$interactive_policy" && grep -qF 'spex-teams' <<< "$interactive_policy"; then
  pass "Teams opt-in is described as experimental"
else
  fail "Teams opt-in is described as experimental"
fi

# Dependency closure is part of selection, not an implicit opt-in: selecting a
# dependent enables gates, while unrelated optional extensions stay disabled.
selection_logic="$(yq -r '[.steps[] | select(.id == "select-extensions") | .. | select(tag == "!!str")] | join("\n")' "$SETUP")"
for dependent in spex-deep-review spex-teams spex-collab; do
  assert_contains "$dependent participates in gates dependency closure" "$selection_logic" "$dependent"
done
assert_contains "dependency closure names spex-gates" "$selection_logic" "spex-gates"
assert_not_contains "detach is not silently treated as a gates dependent" \
  "$(grep -E 'GATES_DEPENDENTS=' <<< "$selection_logic" || true)" "spex-detach"

# The user-facing security vocabulary is the neutral profile contract. Legacy
# standard/none values must not remain choices in the security input.
security_input="$(yq -o=json -I=0 '.inputs.security // {}' "$SETUP")"
security_default="$(yq -r '.inputs.security.default // ""' "$SETUP")"
assert_eq "Safe is the default security profile" "safe" "$security_default"
for profile in Safe Autonomous YOLO; do
  if grep -qi -- "$profile" <<< "$security_input"; then
    pass "security choices include $profile"
  else
    fail "security choices include $profile"
  fi
done
assert_not_contains "security choices omit legacy standard profile" "$security_input" "standard"
assert_not_contains "security choices omit legacy none profile" "$security_input" "none"

# Refresh must consult the persisted neutral profile before applying defaults,
# preserving both prior extension choices and requested security unless the
# user explicitly changes them.
setup_text="$(< "$SETUP")"
assert_contains "refresh reads the persisted initialization profile" "$setup_text" ".specify/spex-profile.yml"
assert_contains "refresh preserves enabled extension selections" "$setup_text" "enabled_extensions"
assert_contains "refresh preserves requested security" "$setup_text" "requested_security"

printf '\nSetup profile contract: %d passed, %d failed\n' "$PASSED" "$FAILED"
[[ "$FAILED" -eq 0 ]]
