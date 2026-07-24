#!/usr/bin/env bash
# Unit tests for the InitializationProfile command lifecycle.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROFILE_TOOL="$REPO_ROOT/spex/scripts/spex-init-profile.py"
PROFILE_FILE_RELATIVE=".specify/spex-profile.yml"

# T015 intentionally lands before T021. Make that red state explicit instead
# of allowing skipped assertions or a command-not-found cascade to pass.
if [[ ! -f "$PROFILE_TOOL" ]]; then
  echo "FAIL: InitializationProfile implementation is missing: $PROFILE_TOOL" >&2
  echo "T015 is test-first; implement T021 to make this suite pass." >&2
  exit 1
fi

# shellcheck source=../lib/test_helpers.sh
source "$REPO_ROOT/tests/lib/test_helpers.sh"
trap spex_test_cleanup EXIT

PASS=0
FAIL=0
COMMAND_OUTPUT=""
COMMAND_ERROR=""
COMMAND_STATUS=0

pass() {
  echo "  PASS: $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "  FAIL: $1${2:+ ($2)}" >&2
  FAIL=$((FAIL + 1))
}

run_profile() {
  local input="$1"
  shift
  local stderr_file
  spex_test_make_temp_dir stderr_file
  stderr_file="$stderr_file/stderr"
  if [[ -n "$input" ]]; then
    COMMAND_OUTPUT="$(printf '%s\n' "$input" | python3 "$PROFILE_TOOL" "$@" 2>"$stderr_file")"
    COMMAND_STATUS=$?
  else
    COMMAND_OUTPUT="$(python3 "$PROFILE_TOOL" "$@" 2>"$stderr_file")"
    COMMAND_STATUS=$?
  fi
  COMMAND_ERROR="$(<"$stderr_file")"
}

assert_status() {
  local description="$1" expected="$2"
  if [[ "$COMMAND_STATUS" -eq "$expected" ]]; then
    pass "$description"
  else
    fail "$description" "expected status $expected, got $COMMAND_STATUS: $COMMAND_ERROR"
  fi
}

assert_failure() {
  local description="$1"
  if [[ "$COMMAND_STATUS" -ne 0 ]]; then
    pass "$description"
  else
    fail "$description" "command unexpectedly succeeded"
  fi
}

assert_json() {
  local description="$1" expression="$2"
  if jq -e "$expression" >/dev/null 2>&1 <<<"$COMMAND_OUTPUT"; then
    pass "$description"
  else
    fail "$description" "unexpected JSON: $COMMAND_OUTPUT"
  fi
}

file_digest() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

propose_profile() {
  local root="$1" requested="$2" effective="$3"
  run_profile "" propose \
    --root "$root" \
    --harness codex \
    --extension spex \
    --extension spex-gates \
    --extension spex-worktrees \
    --requested-security "$requested" \
    --effective-security "$effective" \
    --capabilities-json '{"permissions":{"status":"adapted"}}'
}

echo "=== InitializationProfile lifecycle ==="
spex_test_make_repo TEST_REPO
PROFILE_FILE="$TEST_REPO/$PROFILE_FILE_RELATIVE"

run_profile "" load --root "$TEST_REPO"
assert_failure "load reports an absent profile"

propose_profile "$TEST_REPO" autonomous safe
assert_status "propose creates an initial profile" 0
assert_json "proposal records requested and safer effective security" \
  '.schema_version == "1.0.0" and .active_harness == "codex" and
   .requested_security == "autonomous" and .effective_security == "safe" and
   .config_revision == 1 and (.enabled_extensions | index("spex")) != null'
FALLBACK_PROPOSAL="$COMMAND_OUTPUT"

run_profile "$FALLBACK_PROPOSAL" validate --root "$TEST_REPO"
assert_status "validate accepts a schema-valid safer fallback proposal" 0
assert_json "validate returns the validated profile" \
  '.requested_security == "autonomous" and .effective_security == "safe"'

echo "=== Safer fallback confirmation and refusal ==="
run_profile "$FALLBACK_PROPOSAL" persist \
  --root "$TEST_REPO" --expected-revision 0 --fallback-confirmation decline
assert_failure "persist refuses a declined safer fallback"
if [[ ! -e "$PROFILE_FILE" ]]; then
  pass "declining fallback leaves an uninitialized repository unchanged"
else
  fail "declining fallback leaves an uninitialized repository unchanged" "profile was written"
fi

run_profile "$FALLBACK_PROPOSAL" persist \
  --root "$TEST_REPO" --expected-revision 0 --fallback-confirmation accept
assert_status "persist accepts an explicitly confirmed safer fallback" 0
assert_json "first persistence uses revision one" '.config_revision == 1'
if [[ -f "$PROFILE_FILE" ]]; then
  pass "persist creates the project-owned profile"
else
  fail "persist creates the project-owned profile" "missing $PROFILE_FILE"
fi

run_profile "" load --root "$TEST_REPO"
assert_status "load reads the persisted profile" 0
assert_json "load preserves selected extensions and security intent" \
  '.config_revision == 1 and .requested_security == "autonomous" and
   .effective_security == "safe" and (.enabled_extensions | index("spex-worktrees")) != null'

echo "=== Revisioning, CAS, and unchanged-on-failure ==="
BASELINE_DIGEST="$(file_digest "$PROFILE_FILE")"

propose_profile "$TEST_REPO" safe safe
assert_status "refresh proposal loads the next revision" 0
assert_json "refresh proposal increments the persisted revision" '.config_revision == 2'
REFRESH_PROPOSAL="$COMMAND_OUTPUT"

run_profile "$REFRESH_PROPOSAL" persist --root "$TEST_REPO" --expected-revision 0
assert_failure "persist rejects a stale expected revision"
if [[ "$(file_digest "$PROFILE_FILE")" == "$BASELINE_DIGEST" ]]; then
  pass "CAS failure leaves the profile byte-identical"
else
  fail "CAS failure leaves the profile byte-identical"
fi

INVALID_PROPOSAL="$(jq '.enabled_extensions = ["spex-gates"]' <<<"$REFRESH_PROPOSAL")"
run_profile "$INVALID_PROPOSAL" validate --root "$TEST_REPO"
assert_failure "validate rejects a profile without the required spex extension"
run_profile "$INVALID_PROPOSAL" persist --root "$TEST_REPO" --expected-revision 1
assert_failure "persist refuses invalid input"
if [[ "$(file_digest "$PROFILE_FILE")" == "$BASELINE_DIGEST" ]]; then
  pass "validation failure leaves the profile byte-identical"
else
  fail "validation failure leaves the profile byte-identical"
fi

run_profile "$REFRESH_PROPOSAL" persist --root "$TEST_REPO" --expected-revision 1
assert_status "persist commits a valid compare-and-swap refresh" 0
assert_json "successful refresh advances revision exactly once" '.config_revision == 2'

echo "=== Atomic replacement under concurrent reads ==="
READER_FAILURE="$TEST_REPO/reader-failure"
(
  for _ in $(seq 1 80); do
    loaded="$(python3 "$PROFILE_TOOL" load --root "$TEST_REPO" 2>/dev/null)" || {
      touch "$READER_FAILURE"
      exit
    }
    jq -e '.schema_version == "1.0.0" and (.config_revision | type == "number")' \
      >/dev/null 2>&1 <<<"$loaded" || {
      touch "$READER_FAILURE"
      exit
    }
  done
) &
READER_PID=$!

CURRENT_REVISION=2
for _ in $(seq 1 8); do
  propose_profile "$TEST_REPO" safe safe
  if [[ "$COMMAND_STATUS" -ne 0 ]]; then
    fail "atomic refresh proposal succeeds" "$COMMAND_ERROR"
    break
  fi
  NEXT_PROFILE="$COMMAND_OUTPUT"
  run_profile "$NEXT_PROFILE" persist --root "$TEST_REPO" --expected-revision "$CURRENT_REVISION"
  if [[ "$COMMAND_STATUS" -ne 0 ]]; then
    fail "atomic refresh persistence succeeds" "$COMMAND_ERROR"
    break
  fi
  CURRENT_REVISION=$((CURRENT_REVISION + 1))
done
wait "$READER_PID" || true

if [[ ! -e "$READER_FAILURE" ]]; then
  pass "concurrent readers never observe a partial profile"
else
  fail "concurrent readers never observe a partial profile"
fi

run_profile "" load --root "$TEST_REPO"
assert_status "profile remains loadable after repeated atomic refreshes" 0
assert_json "revisions remain monotonic after repeated refreshes" \
  ".config_revision == $CURRENT_REVISION"

TEMP_FILES="$(find "$TEST_REPO/.specify" -maxdepth 1 -type f ! -name 'spex-profile.yml' -print 2>/dev/null)"
if [[ -z "$TEMP_FILES" ]]; then
  pass "atomic persistence leaves no temporary profile files"
else
  fail "atomic persistence leaves no temporary profile files" "$TEMP_FILES"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
