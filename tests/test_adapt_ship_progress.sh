#!/usr/bin/env bash
# Tests for the ship-progress harness marker: empty expansion support in
# spex-adapt-commands.sh and the per-harness expansion of the ship command.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ADAPT="$REPO_ROOT/spex/scripts/spex-adapt-commands.sh"
ADAPTERS="$REPO_ROOT/spex/scripts/adapters"
EXTENSIONS="$REPO_ROOT/spex/extensions"
SHIP_REL="spex/commands/speckit.spex.ship.md"

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

assert_contains() {
  local desc="$1" needle="$2" file="$3"
  if grep -qF -- "$needle" "$file"; then pass "$desc"; else fail "$desc (expected '$needle')"; fi
}

assert_not_contains() {
  local desc="$1" needle="$2" file="$3"
  if grep -qF -- "$needle" "$file"; then fail "$desc (did not expect '$needle')"; else pass "$desc"; fi
}

# section <file> <heading>: print the subsection starting at <heading> up to
# the next heading of the same or higher level
section() {
  awk -v h="$2" '
    $0 == h { on = 1; print; next }
    on && /^#{1,3} / { exit }
    on { print }
  ' "$1"
}

# adapt_copy <harness> <source-tree> <dest>: copy a command tree and adapt it
adapt_copy() {
  local harness="$1" src="$2" dest="$3"
  rm -rf "$dest"
  cp -R "$src" "$dest"
  "$ADAPT" "$harness" "$dest" "$ADAPTERS" >/dev/null 2>&1
}

# --- (a) empty expansion of block and inline markers ---
echo "Test: empty token expands to nothing (block and inline)"
FIX="$TMP/fixture"
FIX_ADAPTERS="$TMP/adapters"
mkdir -p "$FIX/demo/commands" "$FIX_ADAPTERS/demo"
cat > "$FIX/demo/commands/cmd.md" <<'EOF'
# Demo

First paragraph line.
**Last line of the section.**
{harness:demo}
{/harness:demo}

Inline before{harness:demo-inline} after.
Trailing line.
EOF
cat > "$TMP/expected.md" <<'EOF'
# Demo

First paragraph line.
**Last line of the section.**

Inline before after.
Trailing line.
EOF
cat > "$FIX_ADAPTERS/demo/command-map.json" <<'EOF'
{
  "harness": "demo",
  "tokens": { "demo": "", "demo-inline": "" },
  "fallback_note": "> **Note:** FALLBACK on {harness}. {fallback_text}"
}
EOF
"$ADAPT" demo "$FIX" "$FIX_ADAPTERS" >/dev/null 2>&1
if cmp -s "$TMP/expected.md" "$FIX/demo/commands/cmd.md"; then
  pass "adapted output equals input without markers"
else
  fail "adapted output differs from expected"
  diff "$TMP/expected.md" "$FIX/demo/commands/cmd.md" || true
fi
assert_not_contains "no fallback note" "FALLBACK" "$FIX/demo/commands/cmd.md"

# --- (a2) non-empty and missing tokens expand as before this feature ---
# Golden output produced by the pre-feature adapter (jq -r token extraction),
# so a whitespace change in token extraction is caught for every harness.
echo "Test: non-empty block, inline and missing tokens expand as before"
FIX2="$TMP/fixture2"
FIX2_ADAPTERS="$TMP/adapters2"
mkdir -p "$FIX2/demo/commands" "$FIX2_ADAPTERS/demo"
cat > "$FIX2/demo/commands/cmd.md" <<'EOF'
# Demo

Before the block.
{harness:demo-block}
neutral fallback text
{/harness:demo-block}
After the block.

Inline before {harness:demo-inline} after.
{harness:demo-missing}
neutral text for a missing token
{/harness:demo-missing}
Trailing line.
EOF
cat > "$FIX2_ADAPTERS/demo/command-map.json" <<'EOF'
{
  "harness": "demo",
  "tokens": { "demo-block": "Line one.\n\n- item with `code`\n- item two", "demo-inline": "**inline value**" },
  "fallback_note": "> **Note:** FALLBACK on {harness}. {fallback_text}"
}
EOF
cat > "$TMP/expected2.md" <<'EOF'
# Demo

Before the block.
Line one.

- item with `code`
- item two
After the block.

Inline before **inline value** after.
> **Note:** FALLBACK on demo. This feature requires harness-specific support.
Trailing line.
EOF
"$ADAPT" demo "$FIX2" "$FIX2_ADAPTERS" >/dev/null 2>&1
if cmp -s "$TMP/expected2.md" "$FIX2/demo/commands/cmd.md"; then
  pass "adapted output equals the pre-feature golden output"
else
  fail "adapted output differs from the pre-feature golden output"
  diff "$TMP/expected2.md" "$FIX2/demo/commands/cmd.md" || true
fi

# --- (b) Claude adaptation is unchanged by the ship-progress marker ---
echo "Test: Claude adaptation ignores the ship-progress marker"
adapt_copy claude "$EXTENSIONS" "$TMP/claude-with"
cp -R "$EXTENSIONS" "$TMP/claude-src-without"
grep -vxF -e '{harness:ship-progress}' -e '{/harness:ship-progress}' \
  "$EXTENSIONS/$SHIP_REL" > "$TMP/claude-src-without/$SHIP_REL"
adapt_copy claude "$TMP/claude-src-without" "$TMP/claude-without"
rm -rf "$TMP/claude-src-without"
if diff -r "$TMP/claude-with" "$TMP/claude-without" >/dev/null; then
  pass "Claude adaptation identical with and without marker lines"
else
  fail "Claude adaptation differs"
  diff -r "$TMP/claude-with" "$TMP/claude-without" | head -20 || true
fi

# --- (c) Codex adaptation carries the banner and plan rule ---
echo "Test: Codex adaptation of the ship command"
adapt_copy codex "$EXTENSIONS" "$TMP/codex"
CODEX_SHIP="$TMP/codex/$SHIP_REL"
CODEX_SEC="$TMP/codex-section.md"
section "$CODEX_SHIP" "### Progress Reporting (Codex)" > "$CODEX_SEC"
if [ -s "$CODEX_SEC" ]; then pass "has Progress Reporting (Codex) subsection"; else fail "missing Progress Reporting (Codex) subsection"; fi
assert_contains "mentions progress command" '"$SHIP_STATE" progress' "$CODEX_SEC"
assert_contains "mentions BANNER" "BANNER" "$CODEX_SEC"
assert_contains "mentions PLAN" "PLAN" "$CODEX_SEC"
assert_contains "mentions update_plan" "update_plan" "$CODEX_SEC"
assert_contains "inline stage skill rule" 'do not call `update_plan`' "$CODEX_SEC"
assert_contains "pause before progress" '"$SHIP_STATE" pause' "$CODEX_SEC"
assert_contains "fail before progress" '"$SHIP_STATE" fail' "$CODEX_SEC"
assert_contains "PIPELINE_COMPLETE timing" "PIPELINE_COMPLETE" "$CODEX_SEC"
assert_not_contains "no raw marker" "{harness:ship-progress}" "$CODEX_SHIP"
assert_not_contains "no raw closing marker" "{/harness:ship-progress}" "$CODEX_SHIP"

# --- (d) OpenCode adaptation carries the banner rule only ---
echo "Test: OpenCode adaptation of the ship command"
adapt_copy opencode "$EXTENSIONS" "$TMP/opencode"
OC_SHIP="$TMP/opencode/$SHIP_REL"
OC_SEC="$TMP/opencode-section.md"
section "$OC_SHIP" "### Progress Reporting (OpenCode)" > "$OC_SEC"
if [ -s "$OC_SEC" ]; then pass "has Progress Reporting (OpenCode) subsection"; else fail "missing Progress Reporting (OpenCode) subsection"; fi
assert_contains "mentions progress command" '"$SHIP_STATE" progress' "$OC_SEC"
assert_contains "mentions BANNER" "BANNER" "$OC_SEC"
assert_contains "pause before progress" '"$SHIP_STATE" pause' "$OC_SEC"
assert_contains "fail before progress" '"$SHIP_STATE" fail' "$OC_SEC"
assert_not_contains "no update_plan" "update_plan" "$OC_SHIP"
assert_not_contains "no raw marker" "{harness:ship-progress}" "$OC_SHIP"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
