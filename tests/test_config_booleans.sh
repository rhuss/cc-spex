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

# Stand-in yq: `yq [-r] '<path>' <file>` -> `jq -r '<path>' <file>`. Like real yq, it ignores
# whole-line comments, so a comment-only file parses as empty.
mkdir -p "$WORK/fakebin"
cat > "$WORK/fakebin/yq" <<'SHIM'
#!/usr/bin/env bash
if [ "$1" = "-r" ]; then
  shift
fi
grep -v '^[[:space:]]*#' "$2" | jq -r "$1"
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

echo "Test: YAML 1.1 spellings are accepted, other words use the default"
assert_eq "False / no / OFF mean false" "coderabbit=false copilot=false codex=false" \
  "$(run_with_config '{"external_tools":{"coderabbit":"False","copilot":"no","codex":"OFF"}}' "$WITH_YQ")"
assert_eq "Yes / ON / True mean true" "coderabbit=true copilot=true codex=true" \
  "$(run_with_config '{"external_tools":{"coderabbit":"Yes","copilot":"ON","codex":"True"}}' "$WITH_YQ")"
run_with_config '{"external_tools":{"copilot":"maybe"}}' "$WITH_YQ" >/dev/null
assert_eq "a non-boolean word does not warn" "" "$(cat "$WORK/stderr")"
run_with_config '{"external_tools":{}}' "$WITH_YQ" >/dev/null
assert_eq "a missing key does not warn" "" "$(cat "$WORK/stderr")"
assert_eq "a malformed config uses defaults" "coderabbit=true copilot=true codex=true" \
  "$(run_with_config '{"external_tools": {' "$WITH_YQ")"
assert_eq "a malformed config warns once" \
  "spex: .specify/extensions/spex-deep-review/deep-review-config.yml is not valid YAML; using defaults" \
  "$(cat "$WORK/stderr")"
run_with_config '# only a comment' "$WITH_YQ" >/dev/null
assert_eq "a comment-only config does not warn" "" "$(cat "$WORK/stderr")"

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
  "spex: yq not found; .specify/extensions/spex-deep-review/deep-review-config.yml ignored, using defaults (install: brew install yq | winget install MikeFarah.yq | https://github.com/mikefarah/yq)" \
  "$(cat "$WORK/stderr")"
assert_eq "no config and no yq: defaults" "coderabbit=true copilot=true codex=true" \
  "$(run_with_config '' "$NO_YQ_PATH")"
assert_eq "no config and no yq: stderr is empty" "" "$(cat "$WORK/stderr")"

# Run the first bash block of a command file that contains a marker, with a config file placed
# in the project. $1 = command file, $2 = marker regex (awk), $3 = config path inside the
# project, $4 = JSON config body ("" = none), $5 = line to print the result.
run_other_block() {
  local file="$1" marker="$2" config_path="$3" body="$4" echo_line="$5"
  # A block that has no closing fence (reviewers.md has one) ends where the next block opens.
  awk -v marker="$marker" '/^```bash/{if (inblock && block ~ marker) {printf "%s", block; exit} inblock=1; block=""; next}
       /^```/{if (inblock && block ~ marker) {printf "%s", block; exit} inblock=0; next}
       inblock{block = block $0 "\n"}' "$file" > "$WORK/other_block.sh"
  # Cut at the first `git push` so the test never runs the push or the prose after it.
  sed -i '/^git push/,$d' "$WORK/other_block.sh"
  if [ ! -s "$WORK/other_block.sh" ]; then
    echo "NO BLOCK FOUND"
    return 0
  fi
  echo "$echo_line" >> "$WORK/other_block.sh"
  local project="$WORK/project"
  rm -rf "$project"
  mkdir -p "$project/$(dirname "$config_path")"
  if [ -n "$body" ]; then
    printf '%s\n' "$body" > "$project/$config_path"
  fi
  (cd "$project" && PATH="$WITH_YQ" "$BASH_BIN" "$WORK/other_block.sh" 2>"$WORK/stderr")
}

echo "Test: two-stage auto_commit in review-plan and review-spec"
GIT_CFG=".specify/extensions/git/git-config.yml"
for stage_file in "review-plan:after_tasks" "review-spec:after_specify"; do
  command_name="${stage_file%%:*}"
  stage_key="${stage_file##*:}"
  md="$REPO_ROOT/spex/extensions/spex-gates/commands/speckit.spex-gates.$command_name.md"
  run_auto() {
    run_other_block "$md" 'AUTO_COMMIT=\\$\\(yq' "$GIT_CFG" "$1" 'echo "auto_commit=$AUTO_COMMIT"'
  }
  assert_eq "$command_name: stage false beats default true" "auto_commit=false" \
    "$(run_auto '{"auto_commit":{"default":true,"'"$stage_key"'":{"enabled":false}}}')"
  assert_eq "$command_name: stage missing uses default true" "auto_commit=true" \
    "$(run_auto '{"auto_commit":{"default":true}}')"
  assert_eq "$command_name: both missing means false" "auto_commit=false" \
    "$(run_auto '{"auto_commit":{}}')"
  assert_eq "$command_name: stage 'maybe' falls to default false" "auto_commit=false" \
    "$(run_auto '{"auto_commit":{"default":false,"'"$stage_key"'":{"enabled":"maybe"}}}')"
  assert_eq "$command_name: stage 'Yes' means true" "auto_commit=true" \
    "$(run_auto '{"auto_commit":{"default":false,"'"$stage_key"'":{"enabled":"Yes"}}}')"
done

echo "Test: labels.enabled in the collab reviewers command"
COLLAB_MD="$REPO_ROOT/spex/extensions/spex-collab/commands/speckit.spex-collab.reviewers.md"
COLLAB_CFG=".specify/extensions/spex-collab/collab-config.yml"
run_labels() {
  run_other_block "$COLLAB_MD" 'LABELS_ENABLED=\\$\\(yq' "$COLLAB_CFG" "$1" 'echo "labels=$LABELS_ENABLED"'
}
assert_eq "labels.enabled: false is honoured" "labels=false" "$(run_labels '{"labels":{"enabled":false}}')"
assert_eq "labels.enabled: missing means true" "labels=true" "$(run_labels '{"labels":{}}')"
assert_eq "labels.enabled: 'off' means false" "labels=false" "$(run_labels '{"labels":{"enabled":"off"}}')"

echo "Test: no command file reads a boolean with // true or // false"
# Only `// true` is the bug: it turns an explicit false into true. `// false` is harmless (false
# stays false). Matches single- or double-quoted yq/jq queries, with or without -r, any spacing.
LEFT=$(grep -rnE "(yq|jq)[^|]*['\"][^'\"]*//[[:space:]]*true\b" \
  "$REPO_ROOT/spex" --include='*.md' --include='*.sh' || true)
assert_eq "no // boolean reads remain" "" "$LEFT"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
