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
  (cd "$project" && PATH="$2" bash "$WORK/read_config.sh" 2>"$WORK/stderr")
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
# The normal PATH minus every folder that holds a yq (CI runners ship one).
NO_YQ_PATH=""
IFS=':' read -r -a path_parts <<< "$PATH"
for part in "${path_parts[@]}"; do
  if [ -n "$part" ] && [ ! -x "$part/yq" ] && [ ! -x "$part/yq.exe" ]; then
    NO_YQ_PATH="${NO_YQ_PATH:+$NO_YQ_PATH:}$part"
  fi
done
assert_eq "defaults are used" "coderabbit=true copilot=true codex=true" \
  "$(run_with_config '{"external_tools":{"copilot":false}}' "$NO_YQ_PATH")"
if grep -q "yq not found" "$WORK/stderr"; then
  echo "  PASS: one line says the config cannot be read"
  PASS=$((PASS + 1))
else
  echo "  FAIL: no warning when yq is missing (stderr: $(cat "$WORK/stderr"))"
  FAIL=$((FAIL + 1))
fi

echo "Test: no command file reads a boolean with // true or // false"
LEFT=$(grep -rnE "yq -r '[^']*// (true|false)'" "$REPO_ROOT/spex/extensions" --include='*.md' || true)
assert_eq "no // boolean reads remain" "" "$LEFT"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
