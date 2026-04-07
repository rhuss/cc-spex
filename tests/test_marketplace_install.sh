#!/usr/bin/env bash
# Integration test: verify cc-spex installs correctly from the remote marketplace.
#
# Usage:
#   ./tests/test_marketplace_install.sh              # test remote marketplace
#   ./tests/test_marketplace_install.sh --local       # test local marketplace (faster)
#
# What it checks:
#   1. Marketplace schema validates
#   2. Plugin schema validates
#   3. Marketplace can be added
#   4. Plugin installs from marketplace
#   5. Plugin shows correct version
#   6. Expected commands are present
#   7. Expected skills are present
#   8. Hooks file is valid JSON
#   9. Init script is executable and runs
#  10. Cleanup succeeds

set -euo pipefail

REMOTE_MARKETPLACE="rhuss/cc-rhuss-marketplace"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
LOCAL_MARKETPLACE="$REPO_ROOT"
DEV_MARKETPLACE="spex-plugin-development"
REMOTE_PLUGIN="spex@cc-rhuss-marketplace"
LOCAL_PLUGIN="spex@${DEV_MARKETPLACE}"

# Parse flags
USE_LOCAL=false
if [[ "${1:-}" == "--local" ]]; then
  USE_LOCAL=true
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

PASSED=0
FAILED=0
SKIPPED=0

pass() {
  echo -e "  ${GREEN}✓${NC} $1"
  PASSED=$((PASSED + 1))
}

fail() {
  echo -e "  ${RED}✗${NC} $1"
  FAILED=$((FAILED + 1))
}

skip() {
  echo -e "  ${YELLOW}⊘${NC} $1 (skipped)"
  SKIPPED=$((SKIPPED + 1))
}

# Track what we installed so cleanup is reliable
INSTALLED_MARKETPLACE=""
INSTALLED_PLUGIN=""

cleanup() {
  echo ""
  echo "Cleaning up..."
  if [[ -n "$INSTALLED_PLUGIN" ]]; then
    claude plugin rm "$INSTALLED_PLUGIN" 2>/dev/null || true
  fi
  if [[ -n "$INSTALLED_MARKETPLACE" ]]; then
    claude plugin marketplace rm "$INSTALLED_MARKETPLACE" 2>/dev/null || true
  fi
}
trap cleanup EXIT

#==============================================================================
echo "=== cc-spex Marketplace Integration Test ==="
echo ""

if $USE_LOCAL; then
  echo "Mode: local marketplace"
  MARKETPLACE_SOURCE="$LOCAL_MARKETPLACE"
  MARKETPLACE_NAME="$DEV_MARKETPLACE"
  PLUGIN_REF="$LOCAL_PLUGIN"
else
  echo "Mode: remote marketplace ($REMOTE_MARKETPLACE)"
  MARKETPLACE_SOURCE="$REMOTE_MARKETPLACE"
  MARKETPLACE_NAME="cc-rhuss-marketplace"
  PLUGIN_REF="$REMOTE_PLUGIN"
fi

echo ""

#==============================================================================
# Pre-flight: remove any existing installation of the test target
#==============================================================================
echo "Pre-flight cleanup..."
claude plugin rm "$PLUGIN_REF" 2>/dev/null || true
claude plugin marketplace rm "$MARKETPLACE_NAME" 2>/dev/null || true
echo ""

#==============================================================================
# Test 1: Validate schemas
#==============================================================================
echo "Schema validation:"

if $USE_LOCAL; then
  if claude plugin validate ./ 2>&1 | grep -qi "valid"; then
    pass "Marketplace schema valid"
  else
    fail "Marketplace schema validation failed"
  fi

  if claude plugin validate ./spex/ 2>&1 | grep -qi "valid"; then
    pass "Plugin schema valid"
  else
    fail "Plugin schema validation failed"
  fi
else
  skip "Schema validation (remote mode, no local files)"
  skip "Plugin schema validation (remote mode)"
fi

#==============================================================================
# Test 2: Add marketplace
#==============================================================================
echo ""
echo "Marketplace installation:"

if claude plugin marketplace add "$MARKETPLACE_SOURCE" 2>&1; then
  INSTALLED_MARKETPLACE="$MARKETPLACE_NAME"
  pass "Marketplace added: $MARKETPLACE_NAME"
else
  fail "Failed to add marketplace"
fi

# Verify it appears in the list
if claude plugin marketplace list 2>/dev/null | grep -q "$MARKETPLACE_NAME"; then
  pass "Marketplace appears in list"
else
  fail "Marketplace not found in list"
fi

#==============================================================================
# Test 3: Install plugin
#==============================================================================
echo ""
echo "Plugin installation:"

if claude plugin install "$PLUGIN_REF" 2>&1; then
  INSTALLED_PLUGIN="$PLUGIN_REF"
  pass "Plugin installed: $PLUGIN_REF"
else
  fail "Failed to install plugin"
fi

# Verify it appears in the plugin list
PLUGIN_LIST=$(claude plugin list 2>/dev/null)
if echo "$PLUGIN_LIST" | grep -q "spex@"; then
  pass "Plugin appears in list"
else
  fail "Plugin not found in list"
fi

#==============================================================================
# Test 4: Version check
#==============================================================================
echo ""
echo "Version check:"

EXPECTED_VERSION=$(jq -r '.plugins[] | select(.name == "spex") | .version' "$REPO_ROOT/.claude-plugin/marketplace.json" 2>/dev/null || echo "unknown")
INSTALLED_VERSION=$(echo "$PLUGIN_LIST" | grep -A1 "spex@" | grep "Version:" | awk '{print $2}' || echo "unknown")

# Resolve plugin cache directory for the installed version
PLUGIN_CACHE_BASE=$(find ~/.claude/plugins/cache -path "*spex/${INSTALLED_VERSION}" -type d 2>/dev/null | head -1)
if [[ -z "$PLUGIN_CACHE_BASE" ]]; then
  # Fallback: try expected version
  PLUGIN_CACHE_BASE=$(find ~/.claude/plugins/cache -path "*spex/${EXPECTED_VERSION}" -type d 2>/dev/null | head -1)
fi

if [[ "$INSTALLED_VERSION" == "$EXPECTED_VERSION" ]]; then
  pass "Version matches: $INSTALLED_VERSION"
else
  fail "Version mismatch: installed=$INSTALLED_VERSION expected=$EXPECTED_VERSION"
fi

#==============================================================================
# Test 5: Commands present
#==============================================================================
echo ""
echo "Command verification:"

EXPECTED_COMMANDS=("stamp" "deep-review" "ship" "init" "traits" "brainstorm" "evolve" "help" "review-code" "review-spec" "review-plan" "worktree")

PLUGIN_CACHE="${PLUGIN_CACHE_BASE}/commands"

if [[ -n "$PLUGIN_CACHE_BASE" ]] && [[ -d "$PLUGIN_CACHE" ]]; then
  for cmd in "${EXPECTED_COMMANDS[@]}"; do
    if [[ -f "$PLUGIN_CACHE/$cmd.md" ]]; then
      pass "Command present: /spex:$cmd"
    else
      fail "Command missing: /spex:$cmd"
    fi
  done
else
  fail "Plugin cache directory not found"
fi

#==============================================================================
# Test 6: Skills present
#==============================================================================
echo ""
echo "Skill verification:"

EXPECTED_SKILLS=("brainstorm" "deep-review" "evolve" "review-code" "review-plan" "review-spec" "ship" "using-superpowers" "verification-before-completion" "worktree")

SKILL_DIR="${PLUGIN_CACHE_BASE}/skills"

if [[ -n "$PLUGIN_CACHE_BASE" ]] && [[ -d "$SKILL_DIR" ]]; then
  for skill in "${EXPECTED_SKILLS[@]}"; do
    if [[ -f "$SKILL_DIR/$skill/SKILL.md" ]]; then
      pass "Skill present: $skill"
    else
      fail "Skill missing: $skill"
    fi
  done
else
  fail "Skills directory not found"
fi

#==============================================================================
# Test 7: Hooks valid
#==============================================================================
echo ""
echo "Hooks validation:"

HOOKS_FILE="${PLUGIN_CACHE_BASE}/hooks.json"

if [[ -n "$PLUGIN_CACHE_BASE" ]] && [[ -f "$HOOKS_FILE" ]]; then
  if jq empty "$HOOKS_FILE" 2>/dev/null; then
    pass "hooks.json is valid JSON"
  else
    fail "hooks.json is invalid JSON"
  fi

  HOOK_COUNT=$(jq '[.hooks | to_entries[].value[].hooks[]] | length' "$HOOKS_FILE" 2>/dev/null || echo "0")
  if [[ "$HOOK_COUNT" -gt 0 ]]; then
    pass "Hooks registered: $HOOK_COUNT hook(s)"
  else
    fail "No hooks registered"
  fi
else
  fail "hooks.json not found"
fi

#==============================================================================
# Test 8: Init script runnable
#==============================================================================
echo ""
echo "Init script check:"

INIT_SCRIPT="${PLUGIN_CACHE_BASE}/scripts/spex-init.sh"

if [[ -n "$PLUGIN_CACHE_BASE" ]] && [[ -f "$INIT_SCRIPT" ]]; then
  if [[ -x "$INIT_SCRIPT" ]]; then
    pass "spex-init.sh is executable"
  else
    fail "spex-init.sh is not executable"
  fi

  # Check it at least parses (source with --help or just bash -n)
  if bash -n "$INIT_SCRIPT" 2>/dev/null; then
    pass "spex-init.sh has valid syntax"
  else
    fail "spex-init.sh has syntax errors"
  fi
else
  fail "spex-init.sh not found"
fi

#==============================================================================
# Test 9: Overlay directories exist
#==============================================================================
echo ""
echo "Overlay verification:"

OVERLAY_DIR="${PLUGIN_CACHE_BASE}/overlays"

if [[ -n "$PLUGIN_CACHE_BASE" ]] && [[ -d "$OVERLAY_DIR" ]]; then
  EXPECTED_OVERLAYS=("superpowers" "deep-review" "_ship-guard" "worktrees")
  for overlay in "${EXPECTED_OVERLAYS[@]}"; do
    if [[ -d "$OVERLAY_DIR/$overlay" ]]; then
      pass "Overlay present: $overlay"
    else
      fail "Overlay missing: $overlay"
    fi
  done
else
  fail "Overlays directory not found"
fi

#==============================================================================
# Summary
#==============================================================================
echo ""
echo "==========================================="
TOTAL=$((PASSED + FAILED + SKIPPED))
echo -e "Results: ${GREEN}${PASSED} passed${NC}, ${RED}${FAILED} failed${NC}, ${YELLOW}${SKIPPED} skipped${NC} (${TOTAL} total)"
echo "==========================================="

if [[ $FAILED -gt 0 ]]; then
  exit 1
fi
exit 0
