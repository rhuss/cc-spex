#!/usr/bin/env bash
# Boolean config keys must honour `false` (issue #56).
#
# `yq -r '.key // true'` returns true when the key is set to false, because `//` treats false
# like a missing key. This test runs the REAL config-reading block from the deep-review command
# against configs with the key true, false, missing, and with no yq on PATH at all. A stand-in
# `yq` that hands the query to `jq` keeps it runnable without yq (the configs are written as
# JSON, which is valid YAML). It also checks no `// true` / `// false` boolean read is left in
# any command file.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_MD="$REPO_ROOT/spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md"

BASH_BIN=$(command -v bash)
PASS=0
FAIL=0
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq is needed for the stand-in yq"
  exit 0
fi

# The first ```bash block in run.md that reads the copilot setting.
awk '/^```bash/{inblock=1; block=""; next}
     /^```/{if (inblock && block ~ /DEFAULT_COPILOT=\$\(yq/) {printf "%s", block; exit} inblock=0; next}
     inblock{block = block $0 "\n"}' "$RUN_MD" > "$WORK/read_config.sh"
echo 'echo "coderabbit=$DEFAULT_CODERABBIT copilot=$DEFAULT_COPILOT codex=$DEFAULT_CODEX"' >> "$WORK/read_config.sh"

# Stand-in yq: `yq -r '<path>' <file>` -> `jq -r '<path>' <file>`.
mkdir -p "$WORK/fakebin"
cat > "$WORK/fakebin/yq" <<'SHIM'
#!/usr/bin/env bash
shift            # drop -r
exec jq -r "$1" "$2"
SHIM
chmod +x "$WORK/fakebin/yq"

run_with_config() {
  # $1 = JSON config body ("" = no config file); $2 = PATH to use
  local project="$WORK/project"
  rm -rf "$project"
  mkdir -p "$project/.specify/extensions/spex-deep-review"
  if [ -n "$1" ]; then
    printf '%s\n' "$1" > "$project/.specify/extensions/spex-deep-review/deep-review-config.yml"
  fi
  # BASH_BIN was resolved before PATH was filtered, so removing a folder that holds both yq and
  # bash (for example /usr/bin) cannot make bash disappear.
  (cd "$project" && PATH="$2" "$BASH_BIN" "$WORK/read_config.sh" 2>"$WORK/stderr")
}

echo "Test: the real config block from the deep-review command"
WITH_YQ="$WORK/fakebin:$PATH"
assert_eq "copilot: false is honoured" "coderabbit=true copilot=false codex=true" \
  "$(run_with_config '{"external_tools":{"copilot":false}}' "$WITH_YQ")"
assert_eq "all three false are honoured" "coderabbit=false copilot=false codex=false" \
  "$(run_with_config '{"external_tools":{"coderabbit":false,"copilot":false,"codex":false}}' "$WITH_YQ")"
assert_eq "true stays true" "coderabbit=true copilot=true codex=true" \
  "$(run_with_config '{"external_tools":{"copilot":true}}' "$WITH_YQ")"
assert_eq "a missing key falls back to true" "coderabbit=true copilot=true codex=true" \
  "$(run_with_config '{"external_tools":{}}' "$WITH_YQ")"
assert_eq "a non-boolean value falls back to true" "coderabbit=true copilot=true codex=true" \
  "$(run_with_config '{"external_tools":{"copilot":"maybe"}}' "$WITH_YQ")"
assert_eq "no config file: defaults, no warning" "coderabbit=true copilot=true codex=true" \
  "$(run_with_config '' "$WITH_YQ")"
assert_eq "no config file: stderr is empty" "" "$(cat "$WORK/stderr")"

echo "Test: config present but yq missing"
# A PATH that holds only the tools the config block needs (tr), so no yq can be found even where
# yq and the system tools share a folder (CI runners ship yq in /usr/bin).
mkdir -p "$WORK/toolbin"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$(command -v tr)" > "$WORK/toolbin/tr"
chmod +x "$WORK/toolbin/tr"
NO_YQ_PATH="$WORK/toolbin"
assert_eq "defaults are used" "coderabbit=true copilot=true codex=true" \
  "$(run_with_config '{"external_tools":{"copilot":false}}' "$NO_YQ_PATH")"
assert_eq "stderr is exactly the one warning line" \
  "spex: yq not found, so .specify/extensions/spex-deep-review/deep-review-config.yml cannot be read; using defaults" \
  "$(cat "$WORK/stderr")"
assert_eq "no config and no yq: defaults" "coderabbit=true copilot=true codex=true" \
  "$(run_with_config '' "$NO_YQ_PATH")"
assert_eq "no config and no yq: stderr is empty" "" "$(cat "$WORK/stderr")"

echo "Test: no command file reads a boolean with // true or // false"
# Only `// true` is the bug: it turns an explicit false into true. `// false` is harmless (false
# stays false). Matches single- or double-quoted yq/jq queries, with or without -r, any spacing.
LEFT=$(grep -rnE "(yq|jq)[^|]*['\"][^'\"]*//[[:space:]]*true\b" \
  "$REPO_ROOT/spex" --include='*.md' --include='*.sh' || true)
assert_eq "no // boolean reads remain" "" "$LEFT"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
