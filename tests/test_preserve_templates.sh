#!/usr/bin/env bash
# Tests for spex-preserve-templates.sh and its use in spex-init.sh: core
# spec-kit templates edited in the project are copied to
# .specify/templates/overrides/ before `specify init --force` rewrites them.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GUARD="$REPO_ROOT/spex/scripts/spex-preserve-templates.sh"
INIT_SCRIPT="$REPO_ROOT/spex/scripts/spex-init.sh"

PASS=0
FAIL=0
TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

assert_eq() {
  if [ "$2" = "$3" ]; then
    echo "  PASS: $1"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $1 (expected '$2', got '$3')"; FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  if printf '%s' "$3" | grep -qF -- "$2"; then
    echo "  PASS: $1"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $1 (missing '$2' in: $3)"; FAIL=$((FAIL + 1))
  fi
}

sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

# make_project: stock templates plus a manifest recording their hashes, the
# way `specify init` leaves a project.
make_project() {
  PROJ="$TMPROOT/proj-$RANDOM$RANDOM"
  mkdir -p "$PROJ/.specify/templates" "$PROJ/.specify/integrations"
  printf '# Plan\n\n## Summary\n' > "$PROJ/.specify/templates/plan-template.md"
  printf '# Spec\n' > "$PROJ/.specify/templates/spec-template.md"
  (cd "$PROJ" && jq -n \
    --arg plan "$(sha .specify/templates/plan-template.md)" \
    --arg spec "$(sha .specify/templates/spec-template.md)" \
    '{integration: "speckit", files: {
       ".specify/templates/plan-template.md": $plan,
       ".specify/templates/spec-template.md": $spec,
       ".specify/scripts/bash/common.sh": "0000"}}' \
    > .specify/integrations/speckit.manifest.json)
}

run_guard() {
  RC=0
  OUT=$(cd "$PROJ" && sh "$GUARD" 2>&1) || RC=$?
}

OVR=".specify/templates/overrides/plan-template.md"

echo "Test: stock templates are left alone"
make_project
run_guard
assert_eq "exit 0" "0" "$RC"
assert_eq "no output" "" "$OUT"
assert_eq "no overrides dir" "false" "$([ -d "$PROJ/.specify/templates/overrides" ] && echo true || echo false)"

echo "Test: an edited core template is copied to overrides/"
make_project
printf '\n## Screenshots and website\n' >> "$PROJ/.specify/templates/plan-template.md"
run_guard
assert_eq "exit 0" "0" "$RC"
assert_contains "reported" "Preserved: .specify/templates/plan-template.md" "$OUT"
assert_eq "override is the edited file" "$(sha "$PROJ/.specify/templates/plan-template.md")" "$(sha "$PROJ/$OVR")"
assert_eq "unedited spec template not copied" "false" "$([ -e "$PROJ/.specify/templates/overrides/spec-template.md" ] && echo true || echo false)"

echo "Test: a second run with the identical override is silent"
run_guard
assert_eq "exit 0" "0" "$RC"
assert_eq "no output" "" "$OUT"

echo "Test: an edit that differs from an existing override stops the refresh"
make_project
mkdir -p "$PROJ/.specify/templates/overrides"
printf 'override\n' > "$PROJ/$OVR"
printf 'core edit\n' >> "$PROJ/.specify/templates/plan-template.md"
run_guard
assert_eq "exit 1" "1" "$RC"
assert_contains "error names the file" "ERROR: .specify/templates/plan-template.md has local edits" "$OUT"
assert_eq "override untouched" "override" "$(cat "$PROJ/$OVR")"

echo "Test: no manifest warns and lets the refresh go on"
make_project
rm "$PROJ/.specify/integrations/speckit.manifest.json"
run_guard
assert_eq "exit 0" "0" "$RC"
assert_contains "warning" "WARNING: cannot check .specify/templates/ for local edits" "$OUT"

echo "Test: no .specify/templates is a no-op"
PROJ="$TMPROOT/empty"; mkdir -p "$PROJ"
run_guard
assert_eq "exit 0" "0" "$RC"
assert_eq "no output" "" "$OUT"

# spex-init.sh --refresh with a stub specify that overwrites the core
# templates the way `specify init --force` does.
mkdir -p "$TMPROOT/bin"
cat > "$TMPROOT/bin/specify" <<'EOF'
#!/bin/sh
echo "specify $*" >> "$STUB_LOG"
if [ "$1" = init ]; then
  printf '# Plan\n\n## Summary\n' > .specify/templates/plan-template.md
fi
exit 0
EOF
chmod +x "$TMPROOT/bin/specify"

run_refresh() {
  RC=0
  : > "$TMPROOT/specify.log"
  OUT=$(cd "$PROJ" && STUB_LOG="$TMPROOT/specify.log" PATH="$TMPROOT/bin:$PATH" bash "$INIT_SCRIPT" --refresh 2>&1) || RC=$?
}

echo "Test: --refresh keeps an edited plan template as an override"
make_project
printf '\n## Screenshots and website\n' >> "$PROJ/.specify/templates/plan-template.md"
EDITED=$(cat "$PROJ/.specify/templates/plan-template.md")
run_refresh
assert_contains "init ran" "specify init --here" "$(cat "$TMPROOT/specify.log")"
assert_contains "reported" "Preserved: .specify/templates/plan-template.md" "$OUT"
assert_eq "override keeps the edit" "$EDITED" "$(cat "$PROJ/$OVR")"

echo "Test: --refresh stops before init on a conflicting override"
make_project
mkdir -p "$PROJ/.specify/templates/overrides"
printf 'override\n' > "$PROJ/$OVR"
printf 'core edit\n' >> "$PROJ/.specify/templates/plan-template.md"
run_refresh
assert_eq "exit 1" "1" "$RC"
assert_eq "init not run" "" "$(cat "$TMPROOT/specify.log")"
assert_contains "core edit kept" "core edit" "$(cat "$PROJ/.specify/templates/plan-template.md")"
assert_contains "refresh stopped" "ERROR: refresh stopped to keep local template edits" "$OUT"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
