#!/usr/bin/env bash
# Tests for spex/scripts/spex-detach-config.sh (save | restore): the detach
# configuration survives an extension reinstall byte for byte.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_SCRIPT="$REPO_ROOT/spex/scripts/spex-detach-config.sh"

PASS=0
FAIL=0
TMPDIR=""

cleanup() {
  if [ -n "$TMPDIR" ] && [ -d "$TMPDIR" ]; then
    chmod -R u+w "$TMPDIR" 2>/dev/null || true
    rm -rf "$TMPDIR"
  fi
  TMPDIR=""
}
trap cleanup EXIT

setup_test_repo() {
  TMPDIR=$(mktemp -d)
  cd "$TMPDIR"
  git init -q test-repo
  cd test-repo
  mkdir -p .specify/extensions/spex-detach
}

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

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if printf '%s\n' "$haystack" | grep -qF -- "$needle"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected to contain '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

TEMPLATE="$REPO_ROOT/spex/extensions/spex-detach/config-template.yml"
CONFIG=".specify/extensions/spex-detach/spex-detach-config.yml"
SAVED=".specify/.spex-detach-config.saved.yml"

hash_of() { shasum "$1" | cut -d' ' -f1; }

# reinstall: what `specify extension remove` + `add` do to the config
reinstall() {
  rm -rf .specify/extensions/spex-detach
  mkdir -p .specify/extensions/spex-detach
  cp "$TEMPLATE" "$CONFIG"
}

write_custom_config() {
  cat > "$CONFIG" <<'EOF'
# my notes: archive to the sibling specs repo
archive:
  path: "../my-specs"   # keep this
  auto_commit: false
exclude:
  paths:
    - ".specify/"
    - "specs/"
    - "notes/"
extra_key: kept
EOF
}

echo "=== Test: save + restore keeps a customized config byte-identical ==="
setup_test_repo
write_custom_config
BEFORE=$(hash_of "$CONFIG")
RC=0; sh "$CONFIG_SCRIPT" save || RC=$?
assert_eq "save exits 0" "0" "$RC"
assert_eq "saved copy exists" "true" "$([ -f "$SAVED" ] && echo true || echo false)"
reinstall
assert_eq "reinstall replaced the config" "false" "$([ "$(hash_of "$CONFIG")" = "$BEFORE" ] && echo true || echo false)"
RC=0; sh "$CONFIG_SCRIPT" restore || RC=$?
assert_eq "restore exits 0" "0" "$RC"
assert_eq "config byte-identical" "$BEFORE" "$(hash_of "$CONFIG")"
assert_eq "restore removes the saved copy" "false" "$([ -e "$SAVED" ] && echo true || echo false)"
cleanup

echo "=== Test: no config: save and restore are no-ops, template stays ==="
setup_test_repo
RC=0; sh "$CONFIG_SCRIPT" save || RC=$?
assert_eq "save exits 0" "0" "$RC"
assert_eq "no saved copy" "false" "$([ -e "$SAVED" ] && echo true || echo false)"
reinstall
RC=0; sh "$CONFIG_SCRIPT" restore || RC=$?
assert_eq "restore exits 0" "0" "$RC"
assert_eq "template stays" "$(hash_of "$TEMPLATE")" "$(hash_of "$CONFIG")"
cleanup

echo "=== Test: a stale saved copy is kept when the config is missing ==="
setup_test_repo
write_custom_config
cp -p "$CONFIG" "$SAVED"
STALE=$(hash_of "$SAVED")
rm -rf .specify/extensions/spex-detach
RC=0; sh "$CONFIG_SCRIPT" save || RC=$?
assert_eq "save exits 0" "0" "$RC"
assert_eq "stale saved copy kept" "$STALE" "$(hash_of "$SAVED")"
reinstall
sh "$CONFIG_SCRIPT" restore
assert_eq "restore puts the stale copy back" "$STALE" "$(hash_of "$CONFIG")"
cleanup

echo "=== Test: a retry after a failed restore keeps the user's saved copy ==="
setup_test_repo
write_custom_config
USER_HASH=$(hash_of "$CONFIG")
sh "$CONFIG_SCRIPT" save
reinstall
# The restore never ran (interrupted or failed): template live, user config saved.
RC=0; ERR=$(sh "$CONFIG_SCRIPT" save 2>&1) || RC=$?
assert_eq "second save exits 0" "0" "$RC"
assert_eq "saved copy still holds the user config" "$USER_HASH" "$(hash_of "$SAVED")"
assert_contains "says the earlier copy is kept" "Keeping the detach configuration saved by an earlier run" "$ERR"
reinstall
sh "$CONFIG_SCRIPT" restore
assert_eq "restore brings the user config back" "$USER_HASH" "$(hash_of "$CONFIG")"
cleanup

echo "=== Test: an edited config replaces an older saved copy ==="
setup_test_repo
write_custom_config
sh "$CONFIG_SCRIPT" save
echo "new_key: edited" >> "$CONFIG"
EDITED=$(hash_of "$CONFIG")
sh "$CONFIG_SCRIPT" save
assert_eq "saved copy updated to the edited config" "$EDITED" "$(hash_of "$SAVED")"
cleanup

echo "=== Test: save does not write through a symlinked saved copy ==="
setup_test_repo
write_custom_config
echo "victim" > ../victim.txt
ln -s ../../victim.txt "$SAVED"
sh "$CONFIG_SCRIPT" save
assert_eq "symlink target untouched" "victim" "$(cat ../victim.txt)"
assert_eq "saved copy is a regular file" "false" "$([ -L "$SAVED" ] && echo true || echo false)"
assert_eq "saved copy holds the config" "$(hash_of "$CONFIG")" "$(hash_of "$SAVED")"
cleanup

echo "=== Test: restore does not move a symlinked saved copy into place ==="
setup_test_repo
echo "victim" > ../victim.txt
ln -s ../../victim.txt "$SAVED"
reinstall
RC=0; sh "$CONFIG_SCRIPT" restore 2>/dev/null || RC=$?
assert_eq "restore exits 0" "0" "$RC"
assert_eq "config is not a symlink" "false" "$([ -L "$CONFIG" ] && echo true || echo false)"
assert_eq "template stays" "$(hash_of "$TEMPLATE")" "$(hash_of "$CONFIG")"
cleanup

echo "=== Test: save failure exits 1, names the file, leaves the config ==="
if [ "$(id -u)" = 0 ]; then
  echo "  SKIP: running as root, a read-only directory cannot make save fail"
else
  setup_test_repo
  write_custom_config
  BEFORE=$(hash_of "$CONFIG")
  chmod a-w .specify
  RC=0; ERR=$(sh "$CONFIG_SCRIPT" save 2>&1) || RC=$?
  chmod u+w .specify
  assert_eq "save exits 1" "1" "$RC"
  assert_contains "error names the config file" "ERROR: cannot save $CONFIG" "$ERR"
  assert_contains "error says nothing changed" "nothing was changed" "$ERR"
  assert_eq "config untouched" "$BEFORE" "$(hash_of "$CONFIG")"
  assert_eq "no saved copy" "false" "$([ -e "$SAVED" ] && echo true || echo false)"
  cleanup
fi

echo "=== Test: a failed save keeps an existing saved copy ==="
if [ "$(id -u)" = 0 ]; then
  echo "  SKIP: running as root, an unreadable file cannot make save fail"
else
  setup_test_repo
  write_custom_config
  sh "$CONFIG_SCRIPT" save
  SAVED_HASH=$(hash_of "$SAVED")
  echo "edited: true" >> "$CONFIG"
  chmod 000 "$CONFIG"
  RC=0; sh "$CONFIG_SCRIPT" save 2>/dev/null || RC=$?
  chmod 644 "$CONFIG"
  assert_eq "save exits 1" "1" "$RC"
  assert_eq "earlier saved copy kept" "$SAVED_HASH" "$(hash_of "$SAVED")"
  assert_eq "no staging file left" "" "$(ls -A .specify | grep -F '.spex-detach-config.' | grep -vxF '.spex-detach-config.saved.yml' || true)"
  cleanup
fi

echo "=== Test: restore failure keeps the saved copy ==="
if [ "$(id -u)" = 0 ]; then
  echo "  SKIP: running as root"
else
  setup_test_repo
  write_custom_config
  sh "$CONFIG_SCRIPT" save
  reinstall
  chmod a-w .specify/extensions/spex-detach .specify
  RC=0; ERR=$(sh "$CONFIG_SCRIPT" restore 2>&1) || RC=$?
  chmod u+w .specify/extensions/spex-detach .specify
  assert_eq "restore exits 1" "1" "$RC"
  assert_contains "error names the saved copy" "your configuration is kept in $SAVED" "$ERR"
  assert_eq "saved copy kept" "true" "$([ -f "$SAVED" ] && echo true || echo false)"
  cleanup
fi

echo "=== Test: pending reports a saved copy waiting for an installed spex-detach ==="
setup_test_repo
write_custom_config
RC=0; sh "$CONFIG_SCRIPT" pending || RC=$?
assert_eq "no saved copy: pending exits 1" "1" "$RC"
sh "$CONFIG_SCRIPT" save
touch .specify/extensions/spex-detach/extension.yml
RC=0; sh "$CONFIG_SCRIPT" pending || RC=$?
assert_eq "saved copy and installed extension: pending exits 0" "0" "$RC"
rm -f .specify/extensions/spex-detach/extension.yml
RC=0; sh "$CONFIG_SCRIPT" pending || RC=$?
assert_eq "extension not installed: pending exits 1" "1" "$RC"
assert_eq "pending changes nothing" "true" "$([ -f "$SAVED" ] && echo true || echo false)"
cleanup

echo "=== Test: a directory at the saved-copy name makes save fail ==="
setup_test_repo
write_custom_config
mkdir "$SAVED"
RC=0; ERR=$(sh "$CONFIG_SCRIPT" save 2>&1) || RC=$?
assert_eq "save exits 1" "1" "$RC"
assert_contains "error names the config file" "ERROR: cannot save $CONFIG" "$ERR"
assert_eq "directory left empty" "" "$(ls -A "$SAVED")"
cleanup

echo "=== Test: usage errors exit 2 ==="
setup_test_repo
RC=0; sh "$CONFIG_SCRIPT" >/dev/null 2>&1 || RC=$?
assert_eq "no argument exits 2" "2" "$RC"
RC=0; sh "$CONFIG_SCRIPT" bogus >/dev/null 2>&1 || RC=$?
assert_eq "unknown action exits 2" "2" "$RC"
cleanup

# ─── Summary ───
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
