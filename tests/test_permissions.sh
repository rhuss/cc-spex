#!/usr/bin/env bash
# Tests for spex/scripts/spex-permissions.sh (spec 061: modernize generated
# permission rules).
#
# Every case runs in a fresh temporary project. HOME points at a temporary
# directory so the user-level settings are never read or written.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PERMS="$REPO_ROOT/spex/scripts/spex-permissions.sh"

PASS=0
FAIL=0
TMPROOT=""
PROJ=""
RC=0
OUT=""
ERR=""

cleanup() {
  if [ -n "$TMPROOT" ] && [ -d "$TMPROOT" ]; then
    chmod -R u+w "$TMPROOT" 2>/dev/null || true
    rm -rf "$TMPROOT"
  fi
  TMPROOT=""
}
trap cleanup EXIT

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected '$expected', got '$actual')"; FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    echo "  PASS: $desc"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (missing '$needle' in output:"; printf '%s\n' "$haystack" | sed 's/^/      /'; echo "    )"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if ! printf '%s' "$haystack" | grep -qF -- "$needle"; then
    echo "  PASS: $desc"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (unexpected '$needle' in output:"; printf '%s\n' "$haystack" | sed 's/^/      /'; echo "    )"
    FAIL=$((FAIL + 1))
  fi
}

# make_project: fresh temp project at $PROJ with a fake $TMPROOT/home.
make_project() {
  cleanup
  local raw
  raw=$(mktemp -d) || exit 1
  TMPROOT=$(cd "$raw" && pwd -P) || exit 1
  [ -n "$TMPROOT" ] && [ -d "$TMPROOT" ] && [ "$TMPROOT" != "$(pwd -P)" ] || { echo "cannot create a temporary directory" >&2; exit 1; }
  PROJ="$TMPROOT/proj"
  mkdir -p "$PROJ" "$TMPROOT/home"
}

# put <relpath> <content>: write a settings file into the project verbatim.
put() {
  mkdir -p "$(dirname "$PROJ/$1")"
  printf '%s' "$2" > "$PROJ/$1"
}

# run_perms <args...>: run the script from the project root.
run_perms() {
  RC=0
  (cd "$PROJ" && HOME="$TMPROOT/home" sh "$PERMS" "$@" \
    > "$TMPROOT/out" 2> "$TMPROOT/err") || RC=$?
  OUT=$(cat "$TMPROOT/out")
  ERR=$(cat "$TMPROOT/err")
}

# allow <relpath>: the allow list in compact JSON.
allow() {
  jq -c '.permissions.allow' "$PROJ/$1"
}

# sum <path>: checksum of a file, for byte-identity checks.
sum() {
  cksum < "$1"
}

[ -f "$PERMS" ] || { echo "FAIL: $PERMS not found"; exit 1; }

# ===================================================================
# migrate (User Story 2)
# ===================================================================

echo "Test: migrate rewrites the four legacy rules (US2-1)"
make_project
put .claude/settings.json '{"permissions":{"defaultMode":"bypassPermissions","allow":["Bash(*)","Read(*)","Edit(*)","Write(*)","Bash(npm test)"]},"hooks":{"Stop":[]}}'
run_perms migrate
assert_eq "exit code 0" "0" "$RC"
assert_eq "allow list rewritten" '["Bash","Read","Edit","Write","Bash(npm test)"]' "$(allow .claude/settings.json)"
assert_eq "exact Migrated line" "Migrated: .claude/settings.json permissions: Bash(*) -> Bash, Read(*) -> Read, Edit(*) -> Edit, Write(*) -> Write" "$ERR"
assert_eq "stdout empty" "" "$OUT"
assert_eq "hooks kept" '{"Stop":[]}' "$(jq -c .hooks "$PROJ/.claude/settings.json")"
assert_eq "2-space indentation" '  "permissions": {' "$(sed -n 2p "$PROJ/.claude/settings.json")"

echo "Test: settings.local.json is migrated with its own line (US2-2)"
make_project
put .claude/settings.json '{"permissions":{"allow":["Read(*)"]}}'
put .claude/settings.local.json '{"permissions":{"allow":["Skill","Edit(*)"]}}'
run_perms migrate
assert_eq "settings.json migrated" '["Read"]' "$(allow .claude/settings.json)"
assert_eq "settings.local.json migrated" '["Skill","Edit"]' "$(allow .claude/settings.local.json)"
assert_contains "line for settings.json" "Migrated: .claude/settings.json permissions: Read(*) -> Read" "$ERR"
assert_contains "line for settings.local.json" "Migrated: .claude/settings.local.json permissions: Edit(*) -> Edit" "$ERR"
assert_eq "one line per file" "2" "$(printf '%s\n' "$ERR" | grep -c '^Migrated:')"

echo "Test: only settings.local.json present"
make_project
put .claude/settings.local.json '{"permissions":{"allow":["Write(*)"]}}'
run_perms migrate
assert_eq "local file migrated" '["Write"]' "$(allow .claude/settings.local.json)"
assert_eq "settings.json not created" "no" "$([ -e "$PROJ/.claude/settings.json" ] && echo yes || echo no)"

echo "Test: Read plus Read(*) collapses into one Read at the first position (US2-3)"
make_project
put .claude/settings.json '{"permissions":{"allow":["Skill","Read","Bash(ls)","Read(*)"]}}'
run_perms migrate
assert_eq "one Read" '["Skill","Read","Bash(ls)"]' "$(allow .claude/settings.json)"
assert_eq "Migrated line" "Migrated: .claude/settings.json permissions: Read(*) -> Read" "$ERR"

echo "Test: legacy rule before the bare one keeps the first position"
make_project
put .claude/settings.json '{"permissions":{"allow":["Read(*)","Skill","Read"]}}'
run_perms migrate
assert_eq "Read at first position" '["Read","Skill"]' "$(allow .claude/settings.json)"

echo "Test: user rules are kept in their relative order (US2-4)"
make_project
put .claude/settings.json '{"permissions":{"allow":["Bash(npm test)","Read(*)","Read(~/notes/**)","Agent(*)","Write(*)","WebFetch"]}}'
run_perms migrate
assert_eq "user rules in place" '["Bash(npm test)","Read","Read(~/notes/**)","Agent(*)","Write","WebFetch"]' "$(allow .claude/settings.json)"

echo "Test: data-model example"
make_project
put .claude/settings.json '{"permissions":{"allow":["Skill","Read(*)","Bash(npm test)","Read","Edit(*)","Skill"]}}'
run_perms migrate
assert_eq "example result" '["Skill","Read","Bash(npm test)","Edit","Skill"]' "$(allow .claude/settings.json)"
assert_eq "example output" "Migrated: .claude/settings.json permissions: Read(*) -> Read, Edit(*) -> Edit" "$ERR"

echo "Test: a second run changes nothing and prints nothing (US2-5, SC-003)"
make_project
put .claude/settings.json '{"permissions":{"allow":["Bash(*)","Read(*)"]}}'
put .claude/settings.local.json '{"permissions":{"allow":["Edit(*)"]}}'
run_perms migrate
BEFORE_MAIN=$(sum "$PROJ/.claude/settings.json")
BEFORE_LOCAL=$(sum "$PROJ/.claude/settings.local.json")
run_perms migrate
assert_eq "exit code 0" "0" "$RC"
assert_eq "no output" "" "$ERR$OUT"
assert_eq "settings.json bytes kept" "$BEFORE_MAIN" "$(sum "$PROJ/.claude/settings.json")"
assert_eq "settings.local.json bytes kept" "$BEFORE_LOCAL" "$(sum "$PROJ/.claude/settings.local.json")"

echo "Test: other keys stay unchanged (US2-6, FR-007)"
make_project
ORIG='{"permissions":{"defaultMode":"bypassPermissions","allow":["Read(*)"],"deny":["Read(*)","Bash(rm *)"],"ask":["Write(*)"]},"hooks":{"PostToolUse":[{"matcher":"Edit","hooks":[{"type":"command","command":"memory-sync"}]}]},"statusLine":{"type":"command","command":"cc-deck status"},"env":{"A":"1"}}'
put .claude/settings.json "$ORIG"
run_perms migrate
assert_eq "allow migrated" '["Read"]' "$(allow .claude/settings.json)"
assert_eq "everything else equal" "$(printf '%s' "$ORIG" | jq -cS 'del(.permissions.allow)')" "$(jq -cS 'del(.permissions.allow)' "$PROJ/.claude/settings.json")"
assert_eq "deny untouched" '["Read(*)","Bash(rm *)"]' "$(jq -c .permissions.deny "$PROJ/.claude/settings.json")"
assert_eq "ask untouched" '["Write(*)"]' "$(jq -c .permissions.ask "$PROJ/.claude/settings.json")"

echo "Test: duplicate non-legacy rules without legacy rules stay byte-identical"
make_project
put .claude/settings.json '{"permissions": {"allow": ["Skill", "Skill", "Read", "Read"]}}'
BEFORE=$(sum "$PROJ/.claude/settings.json")
run_perms migrate
assert_eq "bytes kept" "$BEFORE" "$(sum "$PROJ/.claude/settings.json")"
assert_eq "no output" "" "$ERR"

echo "Test: duplicate non-legacy rules survive a migration"
make_project
put .claude/settings.json '{"permissions":{"allow":["Skill","Skill","Write(*)"]}}'
run_perms migrate
assert_eq "Skill twice kept" '["Skill","Skill","Write"]' "$(allow .claude/settings.json)"

echo "Test: a repeated legacy rule collapses into one entry"
make_project
put .claude/settings.json '{"permissions":{"allow":["Edit(*)","Skill","Edit(*)","Edit(*)"]}}'
run_perms migrate
assert_eq "one Edit at first position" '["Edit","Skill"]' "$(allow .claude/settings.json)"
assert_eq "rule listed once" "Migrated: .claude/settings.json permissions: Edit(*) -> Edit" "$ERR"

echo "Test: look-alike rules are not touched"
make_project
put .claude/settings.json '{"permissions":{"allow":["Read(./*)","Bash(* )","bash(*)","Read(**)","Write(* )"," Edit(*)"]}}'
BEFORE=$(sum "$PROJ/.claude/settings.json")
run_perms migrate
assert_eq "bytes kept" "$BEFORE" "$(sum "$PROJ/.claude/settings.json")"
assert_eq "no output" "" "$ERR"

echo "Test: user-level settings are never touched (FR-012)"
make_project
put .claude/settings.json '{"permissions":{"allow":["Read(*)"]}}'
mkdir -p "$TMPROOT/home/.claude"
printf '%s' '{"permissions":{"allow":["Read(*)"]}}' > "$TMPROOT/home/.claude/settings.json"
BEFORE=$(sum "$TMPROOT/home/.claude/settings.json")
run_perms migrate
assert_eq "project migrated" '["Read"]' "$(allow .claude/settings.json)"
assert_eq "user settings bytes kept" "$BEFORE" "$(sum "$TMPROOT/home/.claude/settings.json")"
assert_not_contains "no output for user settings" "home" "$ERR"

echo "Test: --root selects the project when run from another directory"
make_project
mkdir -p "$TMPROOT/elsewhere"
put .claude/settings.json '{"permissions":{"allow":["Bash(*)"]}}'
RC=0
(cd "$TMPROOT/elsewhere" && HOME="$TMPROOT/home" sh "$PERMS" migrate --root "$PROJ" 2> "$TMPROOT/err") || RC=$?
ERR=$(cat "$TMPROOT/err")
assert_eq "--root migrates the project" '["Bash"]' "$(allow .claude/settings.json)"
assert_eq "path relative to root" "Migrated: .claude/settings.json permissions: Bash(*) -> Bash" "$ERR"

echo "Test: a symlinked settings file stays a symlink"
make_project
mkdir -p "$PROJ/.claude" "$TMPROOT/shared"
printf '%s' '{"permissions":{"allow":["Read(*)","Skill"]}}' > "$TMPROOT/shared/settings.json"
ln -s ../../shared/settings.json "$PROJ/.claude/settings.json"
run_perms migrate
assert_eq "still a symlink" "yes" "$([ -L "$PROJ/.claude/settings.json" ] && echo yes || echo no)"
assert_eq "target migrated" '["Read","Skill"]' "$(jq -c .permissions.allow "$TMPROOT/shared/settings.json")"
assert_contains "Migrated line" "Migrated: .claude/settings.json permissions: Read(*) -> Read" "$ERR"
assert_eq "no temp file left" "" "$(ls -A "$TMPROOT/shared" | grep -v '^settings.json$' || true)"

echo "Test: a migrated file keeps its file mode"
make_project
put .claude/settings.json '{"permissions":{"allow":["Read(*)"]}}'
chmod 600 "$PROJ/.claude/settings.json"
run_perms migrate
assert_eq "file migrated" '["Read"]' "$(allow .claude/settings.json)"
assert_eq "mode 600 kept" "-rw-------" "$(ls -l "$PROJ/.claude/settings.json" | cut -c1-10)"
assert_eq "no temp file left" "settings.json" "$(ls -A "$PROJ/.claude")"

# ===================================================================
# migrate never damages settings it cannot handle (User Story 3)
# ===================================================================

echo "Test: no settings files: nothing created, no output (US3-1)"
make_project
run_perms migrate
assert_eq "exit code 0" "0" "$RC"
assert_eq "no output" "" "$ERR$OUT"
assert_eq ".claude not created" "no" "$([ -e "$PROJ/.claude" ] && echo yes || echo no)"

# expect_untouched <desc> <content>: settings.json with <content> stays
# byte-identical after migrate, with exit 0 and no output.
expect_untouched() {
  make_project
  put .claude/settings.json "$2"
  local before
  before=$(sum "$PROJ/.claude/settings.json")
  run_perms migrate
  assert_eq "$1: exit code 0" "0" "$RC"
  assert_eq "$1: bytes kept" "$before" "$(sum "$PROJ/.claude/settings.json")"
  assert_eq "$1: no output" "" "$ERR"
}

echo "Test: partial or unexpected shapes are left alone (US3-2, US3-4, FR-011)"
expect_untouched "no permissions" '{"hooks":{"Stop":[]}}'
expect_untouched "no allow" '{"permissions":{"defaultMode":"bypassPermissions","deny":["Read(*)"]}}'
expect_untouched "allow is a string" '{"permissions":{"allow":"Read(*)"}}'
expect_untouched "allow is an object" '{"permissions":{"allow":{"Read(*)":true}}}'
expect_untouched "allow is null" '{"permissions":{"allow":null}}'
expect_untouched "top level is an array" '["Read(*)"]'
expect_untouched "top level is null" 'null'
expect_untouched "permissions is an array" '{"permissions":["Read(*)"]}'
expect_untouched "permissions is a string" '{"permissions":"Read(*)"}'

echo "Test: invalid JSON is left alone with a warning (US3-3)"
make_project
put .claude/settings.json '{"permissions":{"allow":["Read(*)"]'
put .claude/settings.local.json '{"permissions":{"allow":["Edit(*)"]}}'
BEFORE=$(sum "$PROJ/.claude/settings.json")
run_perms migrate
assert_eq "exit code 0" "0" "$RC"
assert_eq "bytes kept" "$BEFORE" "$(sum "$PROJ/.claude/settings.json")"
assert_contains "warning names the file" "WARNING: .claude/settings.json is not valid JSON; permission rules not migrated" "$ERR"
assert_eq "the other file is still migrated" '["Edit"]' "$(allow .claude/settings.local.json)"
assert_contains "Migrated line for the other file" "Migrated: .claude/settings.local.json permissions: Edit(*) -> Edit" "$ERR"

echo "Test: empty and multi-document files count as invalid JSON"
make_project
put .claude/settings.json ''
put .claude/settings.local.json '{"permissions":{"allow":["Read(*)"]}} {}'
BEFORE_MAIN=$(sum "$PROJ/.claude/settings.json")
BEFORE_LOCAL=$(sum "$PROJ/.claude/settings.local.json")
run_perms migrate
assert_eq "exit code 0" "0" "$RC"
assert_eq "empty file kept" "$BEFORE_MAIN" "$(sum "$PROJ/.claude/settings.json")"
assert_eq "multi-document file kept" "$BEFORE_LOCAL" "$(sum "$PROJ/.claude/settings.local.json")"
assert_contains "warning for empty file" "WARNING: .claude/settings.json is not valid JSON" "$ERR"
assert_contains "warning for multi-document file" "WARNING: .claude/settings.local.json is not valid JSON" "$ERR"

echo "Test: non-string entries are kept when migrating (FR-011)"
make_project
put .claude/settings.json '{"permissions":{"allow":[1,"Read(*)",null,{"x":"Read(*)"},["Edit(*)"],true]}}'
run_perms migrate
assert_eq "exit code 0" "0" "$RC"
assert_eq "non-strings kept" '[1,"Read",null,{"x":"Read(*)"},["Edit(*)"],true]' "$(allow .claude/settings.json)"

echo "Test: a write failure keeps the original and warns (FR-011a)"
if [ "$(id -u)" -eq 0 ]; then
  echo "  SKIP: running as root, directory permissions are not enforced"
else
  make_project
  put .claude/settings.json '{"permissions":{"allow":["Read(*)"]}}'
  BEFORE=$(sum "$PROJ/.claude/settings.json")
  chmod 555 "$PROJ/.claude"
  run_perms migrate
  chmod 755 "$PROJ/.claude"
  assert_eq "exit code 0" "0" "$RC"
  assert_eq "original intact" "$BEFORE" "$(sum "$PROJ/.claude/settings.json")"
  assert_contains "write warning" "WARNING: could not write .claude/settings.json; permission rules not migrated" "$ERR"
  assert_not_contains "no Migrated line" "Migrated:" "$ERR"
  assert_eq "no temp file left" "settings.json" "$(ls -A "$PROJ/.claude")"

  echo "Test: a read-only settings file warns without raw shell errors"
  make_project
  put .claude/settings.json '{"permissions":{"allow":["Read(*)"]}}'
  chmod 444 "$PROJ/.claude/settings.json"
  BEFORE=$(sum "$PROJ/.claude/settings.json")
  run_perms migrate
  assert_eq "exit code 0" "0" "$RC"
  assert_eq "original intact" "$BEFORE" "$(sum "$PROJ/.claude/settings.json")"
  assert_eq "only the warning" "WARNING: could not write .claude/settings.json; permission rules not migrated" "$ERR"
  assert_eq "no temp file left" "settings.json" "$(ls -A "$PROJ/.claude")"
fi

echo "Test: migrate without jq warns and exits 0"
make_project
NOJQ="$TMPROOT/nojq-bin"
mkdir -p "$NOJQ"
RC=0
(cd "$PROJ" && PATH="$NOJQ" /bin/sh "$PERMS" migrate > "$TMPROOT/out" 2> "$TMPROOT/err") || RC=$?
assert_eq "no settings: exit code 0" "0" "$RC"
assert_eq "no settings: no output" "" "$(cat "$TMPROOT/err")"
put .claude/settings.json '{"permissions":{"allow":["Read(*)"]}}'
BEFORE=$(sum "$PROJ/.claude/settings.json")
RC=0
(cd "$PROJ" && PATH="$NOJQ" /bin/sh "$PERMS" migrate > "$TMPROOT/out" 2> "$TMPROOT/err") || RC=$?
assert_eq "with settings: exit code 0" "0" "$RC"
assert_eq "with settings: warning only" "WARNING: jq is not installed; permission rules in .claude/settings.json not migrated" "$(cat "$TMPROOT/err")"
assert_eq "with settings: bytes kept" "$BEFORE" "$(sum "$PROJ/.claude/settings.json")"
RC=0
(cd "$PROJ" && PATH="$NOJQ" /bin/sh "$PERMS" apply Skill > "$TMPROOT/out" 2> "$TMPROOT/err") || RC=$?
assert_eq "apply without jq exits 1" "1" "$RC"

# ===================================================================
# user-level settings are out of bounds (FR-012)
# ===================================================================

# expect_user_untouched <desc> <subcommand args...>: the fake user-level
# settings keep their bytes and a user-level WARNING is printed.
expect_user_untouched() {
  local desc="$1"; shift
  local before_main before_local
  before_main=$(sum "$TMPROOT/home/.claude/settings.json")
  before_local=$(sum "$TMPROOT/home/.claude/settings.local.json")
  run_perms "$@"
  assert_eq "$desc: exit code 0" "0" "$RC"
  assert_eq "$desc: user settings.json bytes kept" "$before_main" "$(sum "$TMPROOT/home/.claude/settings.json")"
  assert_eq "$desc: user settings.local.json bytes kept" "$before_local" "$(sum "$TMPROOT/home/.claude/settings.local.json")"
  assert_contains "$desc: warning" "resolves to the user-level Claude settings" "$ERR"
  assert_not_contains "$desc: no Migrated line" "Migrated:" "$ERR"
}

# user_settings: legacy rules in the fake user-level settings files.
user_settings() {
  mkdir -p "$TMPROOT/home/.claude"
  printf '%s' '{"permissions":{"allow":["Read(*)","Bash(*)"]}}' > "$TMPROOT/home/.claude/settings.json"
  printf '%s' '{"permissions":{"allow":["Write(*)"]}}' > "$TMPROOT/home/.claude/settings.local.json"
}

echo "Test: a settings file symlinked to the user-level settings is left alone"
make_project
user_settings
mkdir -p "$PROJ/.claude"
ln -s ../../home/.claude/settings.json "$PROJ/.claude/settings.json"
ln -s ../../home/.claude/settings.local.json "$PROJ/.claude/settings.local.json"
expect_user_untouched "file symlink, migrate" migrate
expect_user_untouched "file symlink, YOLO apply" apply --default-mode bypassPermissions Bash Read Edit Write

echo "Test: a .claude directory symlinked to ~/.claude is left alone"
make_project
user_settings
ln -s ../home/.claude "$PROJ/.claude"
expect_user_untouched "directory symlink, migrate" migrate
expect_user_untouched "directory symlink, apply" apply Skill

echo "Test: running from the home directory never touches the user-level settings"
make_project
user_settings
BEFORE=$(sum "$TMPROOT/home/.claude/settings.json")
RC=0
(cd "$TMPROOT/home" && HOME="$TMPROOT/home" sh "$PERMS" migrate 2> "$TMPROOT/err") || RC=$?
assert_eq "home as root: exit code 0" "0" "$RC"
assert_eq "home as root: bytes kept" "$BEFORE" "$(sum "$TMPROOT/home/.claude/settings.json")"
assert_contains "home as root: warning" "resolves to the user-level Claude settings" "$(cat "$TMPROOT/err")"
rm -rf "$TMPROOT/home/.claude"
RC=0
(cd "$TMPROOT/home" && HOME="$TMPROOT/home" sh "$PERMS" apply Skill 2> "$TMPROOT/err") || RC=$?
assert_eq "home as root, no ~/.claude: exit code 0" "0" "$RC"
assert_eq "home as root, no ~/.claude: apply creates nothing" "no" "$([ -e "$TMPROOT/home/.claude" ] && echo yes || echo no)"
assert_contains "home as root, no ~/.claude: warning" "resolves to the user-level Claude settings" "$(cat "$TMPROOT/err")"

# dotfile_user_settings: user-level settings that are symlinks into a dotfiles
# directory, as GNU stow, home-manager or chezmoi create them.
dotfile_user_settings() {
  mkdir -p "$TMPROOT/home/.claude" "$TMPROOT/home/dotfiles/claude"
  printf '%s' '{"permissions":{"allow":["Read(*)","Bash(*)"]}}' > "$TMPROOT/home/dotfiles/claude/settings.json"
  printf '%s' '{"permissions":{"allow":["Write(*)"]}}' > "$TMPROOT/home/dotfiles/claude/settings.local.json"
  ln -s ../dotfiles/claude/settings.json "$TMPROOT/home/.claude/settings.json"
  ln -s ../dotfiles/claude/settings.local.json "$TMPROOT/home/.claude/settings.local.json"
}

# expect_dotfiles_untouched <desc> <cwd> <subcommand args...>
expect_dotfiles_untouched() {
  local desc="$1" cwd="$2"; shift 2
  local before_main before_local
  before_main=$(sum "$TMPROOT/home/dotfiles/claude/settings.json")
  before_local=$(sum "$TMPROOT/home/dotfiles/claude/settings.local.json")
  RC=0
  (cd "$cwd" && HOME="$TMPROOT/home" sh "$PERMS" "$@" 2> "$TMPROOT/err") || RC=$?
  ERR=$(cat "$TMPROOT/err")
  assert_eq "$desc: exit code 0" "0" "$RC"
  assert_eq "$desc: dotfiles settings.json bytes kept" "$before_main" "$(sum "$TMPROOT/home/dotfiles/claude/settings.json")"
  assert_eq "$desc: dotfiles settings.local.json bytes kept" "$before_local" "$(sum "$TMPROOT/home/dotfiles/claude/settings.local.json")"
  assert_contains "$desc: warning" "resolves to the user-level Claude settings" "$ERR"
  assert_not_contains "$desc: no Migrated line" "Migrated:" "$ERR"
}

echo "Test: user-level settings that are symlinks themselves are still recognized"
make_project
dotfile_user_settings
mkdir -p "$PROJ/.claude"
ln -s ../../home/.claude/settings.json "$PROJ/.claude/settings.json"
ln -s ../../home/.claude/settings.local.json "$PROJ/.claude/settings.local.json"
expect_dotfiles_untouched "file symlink, migrate" "$PROJ" migrate
expect_dotfiles_untouched "file symlink, YOLO apply" "$PROJ" apply --default-mode bypassPermissions Bash Read
make_project
dotfile_user_settings
ln -s ../home/.claude "$PROJ/.claude"
expect_dotfiles_untouched "directory symlink, migrate" "$PROJ" migrate
make_project
dotfile_user_settings
expect_dotfiles_untouched "home as root, migrate" "$TMPROOT/home" migrate
expect_dotfiles_untouched "home as root, YOLO apply" "$TMPROOT/home" apply --default-mode bypassPermissions Bash Read

echo "Test: a relative .. link behind a symlinked directory is resolved physically"
make_project
user_settings
mkdir -p "$TMPROOT/shared/a"
ln -s ../../home/.claude/settings.json "$TMPROOT/shared/a/settings.json"
ln -s ../shared/a "$PROJ/.claude"
expect_user_untouched "dot-dot link, migrate" migrate

echo "Test: hard links, case variants and newline link names cannot reach user settings"
make_project
user_settings
mkdir -p "$PROJ/.claude"
ln "$TMPROOT/home/.claude/settings.json" "$PROJ/.claude/settings.json"
expect_user_untouched "hard link, migrate" migrate
make_project
user_settings
mkdir -p "$PROJ/.claude"
NL='
'
ln -s "foo$NL" "$PROJ/.claude/settings.local.json"
ln -s ../../home/.claude/settings.json "$PROJ/.claude/foo$NL"
BEFORE=$(sum "$TMPROOT/home/.claude/settings.json")
run_perms apply Bash Read
assert_eq "newline link: exit code 0" "0" "$RC"
assert_eq "newline link: user settings bytes kept" "$BEFORE" "$(sum "$TMPROOT/home/.claude/settings.json")"
assert_eq "newline link: no copy of user settings in the project" "no" "$([ -e "$PROJ/.claude/foo" ] && echo yes || echo no)"
assert_not_contains "newline link: nothing configured" "Permissions configured" "$ERR"
if [ -e "$TMPROOT/home/.CLAUDE/SETTINGS.JSON" ]; then
  make_project
  user_settings
  mkdir -p "$PROJ/.claude"
  ln -s ../../home/.claude/SETTINGS.JSON "$PROJ/.claude/settings.json"
  expect_user_untouched "case variant file link, migrate" migrate
  make_project
  user_settings
  ln -s ../home/.CLAUDE "$PROJ/.claude"
  expect_user_untouched "case variant directory link, migrate" migrate
else
  echo "  SKIP: case-sensitive file system, case variants are different files"
fi

echo "Test: a link to a file whose name ends in a newline is refused"
make_project
mkdir -p "$PROJ/.claude"
printf '%s' '{"permissions":{"allow":["Read(*)"]}}' > "$PROJ/.claude/data$NL"
ln -s "data$NL" "$PROJ/.claude/settings.json"
BEFORE=$(sum "$PROJ/.claude/data$NL")
run_perms migrate
assert_eq "newline target: exit code 0" "0" "$RC"
assert_eq "newline target: bytes kept" "$BEFORE" "$(sum "$PROJ/.claude/data$NL")"
assert_eq "newline target: no truncated file created" "no" "$([ -e "$PROJ/.claude/data" ] && echo yes || echo no)"
assert_contains "newline target: warning" "WARNING: .claude/settings.json cannot be resolved safely; left unchanged" "$ERR"

echo "Test: CDPATH does not redirect --root"
make_project
user_settings
mkdir -p "$TMPROOT/cdp/proj/.claude" "$TMPROOT/elsewhere/proj"
ln -s "$TMPROOT/home/.claude/settings.json" "$TMPROOT/cdp/proj/.claude/settings.json"
BEFORE=$(sum "$TMPROOT/home/.claude/settings.json")
RC=0
(cd "$TMPROOT/elsewhere" && CDPATH="$TMPROOT/cdp" HOME="$TMPROOT/home" sh "$PERMS" migrate --root proj 2> "$TMPROOT/err") || RC=$?
assert_eq "CDPATH: exit code 0" "0" "$RC"
assert_eq "CDPATH: user settings bytes kept" "$BEFORE" "$(sum "$TMPROOT/home/.claude/settings.json")"
assert_eq "CDPATH: nothing to do in the real root" "" "$(cat "$TMPROOT/err")"

echo "Test: CLAUDE_CONFIG_DIR settings are user-level too"
make_project
mkdir -p "$TMPROOT/config"
printf '%s' '{"permissions":{"allow":["Read(*)"]}}' > "$TMPROOT/config/settings.json"
mkdir -p "$PROJ/.claude"
ln -s ../../config/settings.json "$PROJ/.claude/settings.json"
BEFORE=$(sum "$TMPROOT/config/settings.json")
RC=0
(cd "$PROJ" && HOME="$TMPROOT/home" CLAUDE_CONFIG_DIR="$TMPROOT/config" sh "$PERMS" migrate 2> "$TMPROOT/err") || RC=$?
assert_eq "config dir: bytes kept" "$BEFORE" "$(sum "$TMPROOT/config/settings.json")"
assert_contains "config dir: warning" "resolves to the user-level Claude settings" "$(cat "$TMPROOT/err")"

# ===================================================================
# apply (User Story 1)
# ===================================================================

# The YOLO and Standard lists setup.yml passes. The init skill's own lists are
# checked against their real source in "rule lists in setup.yml and the init
# skill" below.
YOLO=(Bash Read Edit Write Skill 'Agent(*)' WebFetch WebSearch EnterPlanMode ExitPlanMode EnterWorktree ExitWorktree)
YOLO_JSON='["Bash","Read","Edit","Write","Skill","Agent(*)","WebFetch","WebSearch","EnterPlanMode","ExitPlanMode","EnterWorktree","ExitWorktree"]'
STANDARD=(Skill 'Bash(specify *)' 'Bash(/*/spex-init.sh*)' 'Bash(*spex-ship-statusline.sh*)')
STANDARD_JSON='["Skill","Bash(specify *)","Bash(/*/spex-init.sh*)","Bash(*spex-ship-statusline.sh*)"]'
# The YOLO list as earlier spex versions left it (merged with `unique`, so sorted).
OLD_YOLO_JSON='["Agent(*)","Bash(*)","Edit(*)","EnterPlanMode","EnterWorktree","ExitPlanMode","ExitWorktree","Read(*)","Skill","WebFetch","WebSearch","Write(*)"]'

echo "Test: YOLO apply on a project without settings (US1-1, US1-2)"
make_project
run_perms apply --default-mode bypassPermissions "${YOLO[@]}"
assert_eq "exit code 0" "0" "$RC"
assert_eq "allow list in argument order" "$YOLO_JSON" "$(allow .claude/settings.local.json)"
assert_eq "defaultMode set" "bypassPermissions" "$(jq -r .permissions.defaultMode "$PROJ/.claude/settings.local.json")"
assert_eq "output" "Default mode set to bypassPermissions in .claude/settings.local.json
Permissions configured in .claude/settings.local.json (12 rules added)" "$ERR"
assert_eq "stdout empty" "" "$OUT"
assert_eq "no legacy form written" "0" "$(jq '[.permissions.allow[] | select(. == "Bash(*)" or . == "Read(*)" or . == "Edit(*)" or . == "Write(*)")] | length' "$PROJ/.claude/settings.local.json")"
assert_eq "only settings.local.json created" "settings.local.json" "$(ls -A "$PROJ/.claude")"

echo "Test: Standard apply on a project without settings"
make_project
run_perms apply "${STANDARD[@]}"
assert_eq "allow list" "$STANDARD_JSON" "$(allow .claude/settings.local.json)"
assert_eq "no defaultMode" "false" "$(jq '.permissions | has("defaultMode")' "$PROJ/.claude/settings.local.json")"
assert_eq "output" "Permissions configured in .claude/settings.local.json (4 rules added)" "$ERR"

echo "Test: YOLO apply over the legacy rules leaves each bare form once (US1-3, FR-003)"
make_project
put .claude/settings.local.json "{\"permissions\":{\"defaultMode\":\"bypassPermissions\",\"allow\":$OLD_YOLO_JSON}}"
run_perms apply --default-mode bypassPermissions "${YOLO[@]}"
assert_eq "exit code 0" "0" "$RC"
assert_eq "legacy forms replaced in place" '["Agent(*)","Bash","Edit","EnterPlanMode","EnterWorktree","ExitPlanMode","ExitWorktree","Read","Skill","WebFetch","WebSearch","Write"]' "$(allow .claude/settings.local.json)"
for t in Bash Read Edit Write; do
  assert_eq "$t exactly once" "1" "$(jq --arg t "$t" '[.permissions.allow[] | select(. == $t)] | length' "$PROJ/.claude/settings.local.json")"
done
assert_contains "Migrated line" "Migrated: .claude/settings.local.json permissions: Bash(*) -> Bash, Edit(*) -> Edit, Read(*) -> Read, Write(*) -> Write" "$ERR"
assert_contains "no new rules counted" "Permissions configured in .claude/settings.local.json (0 rules added)" "$ERR"

echo "Test: existing user rules keep their order, new rules are appended (FR-017)"
make_project
put .claude/settings.local.json '{"permissions":{"allow":["Zeta","Bash(npm test)","Alpha","Skill"]}}'
run_perms apply "${STANDARD[@]}"
assert_eq "no sorting, Skill not duplicated" '["Zeta","Bash(npm test)","Alpha","Skill","Bash(specify *)","Bash(/*/spex-init.sh*)","Bash(*spex-ship-statusline.sh*)"]' "$(allow .claude/settings.local.json)"
assert_eq "output" "Permissions configured in .claude/settings.local.json (3 rules added)" "$ERR"

echo "Test: a repeated rule argument is added once"
make_project
run_perms apply Skill Skill WebFetch
assert_eq "allow list" '["Skill","WebFetch"]' "$(allow .claude/settings.local.json)"
assert_eq "output" "Permissions configured in .claude/settings.local.json (2 rules added)" "$ERR"

echo "Test: settings with other keys but no permissions"
make_project
ORIG='{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"memory-sync"}]}]},"statusLine":{"type":"command","command":"cc-deck status"}}'
put .claude/settings.local.json "$ORIG"
run_perms apply "${STANDARD[@]}"
assert_eq "rules added" "$STANDARD_JSON" "$(allow .claude/settings.local.json)"
assert_eq "other keys unchanged" "$(printf '%s' "$ORIG" | jq -cS .)" "$(jq -cS 'del(.permissions)' "$PROJ/.claude/settings.local.json")"

echo "Test: settings with permissions but no allow"
make_project
put .claude/settings.local.json '{"permissions":{"deny":["Bash(rm *)"],"ask":["Write(*)"]},"env":{"A":"1"}}'
run_perms apply --default-mode bypassPermissions "${YOLO[@]}"
assert_eq "rules added" "$YOLO_JSON" "$(allow .claude/settings.local.json)"
assert_eq "deny kept" '["Bash(rm *)"]' "$(jq -c .permissions.deny "$PROJ/.claude/settings.local.json")"
assert_eq "ask kept" '["Write(*)"]' "$(jq -c .permissions.ask "$PROJ/.claude/settings.local.json")"
assert_eq "env kept" '{"A":"1"}' "$(jq -c .env "$PROJ/.claude/settings.local.json")"

echo "Test: re-applying the same level is byte-identical"
make_project
put .claude/settings.local.json '{"permissions": {"allow": ["Skill"]}, "hooks": {}}'
run_perms apply --default-mode bypassPermissions "${YOLO[@]}"
BEFORE=$(sum "$PROJ/.claude/settings.local.json")
run_perms apply --default-mode bypassPermissions "${YOLO[@]}"
assert_eq "exit code 0" "0" "$RC"
assert_eq "bytes kept" "$BEFORE" "$(sum "$PROJ/.claude/settings.local.json")"
assert_eq "output" "Permissions configured in .claude/settings.local.json (0 rules added)" "$ERR"

echo "Test: an unchanged file in its own layout is not rewritten"
make_project
put .claude/settings.local.json '{"permissions":{"allow":["Skill"]}}'
BEFORE=$(sum "$PROJ/.claude/settings.local.json")
run_perms apply Skill
assert_eq "bytes kept" "$BEFORE" "$(sum "$PROJ/.claude/settings.local.json")"
assert_eq "output" "Permissions configured in .claude/settings.local.json (0 rules added)" "$ERR"

echo "Test: a changed defaultMode alone is written"
make_project
put .claude/settings.local.json "{\"permissions\":{\"defaultMode\":\"default\",\"allow\":$YOLO_JSON}}"
run_perms apply --default-mode bypassPermissions "${YOLO[@]}"
assert_eq "defaultMode updated" "bypassPermissions" "$(jq -r .permissions.defaultMode "$PROJ/.claude/settings.local.json")"
assert_eq "output names the mode change" "Default mode set to bypassPermissions in .claude/settings.local.json
Permissions configured in .claude/settings.local.json (0 rules added)" "$ERR"

echo "Test: apply never writes the committed settings.json (issue 62)"
make_project
put .claude/settings.json '{"hooks":{"Stop":[]},"permissions":{"allow":["Bash(npm test)"]}}'
BEFORE=$(sum "$PROJ/.claude/settings.json")
run_perms apply --default-mode bypassPermissions "${YOLO[@]}"
assert_eq "committed settings.json bytes kept (YOLO)" "$BEFORE" "$(sum "$PROJ/.claude/settings.json")"
assert_eq "YOLO rules in settings.local.json" "$YOLO_JSON" "$(allow .claude/settings.local.json)"
assert_not_contains "apply output never names settings.json" "settings.json" "$ERR"
run_perms apply "${STANDARD[@]}"
assert_eq "committed settings.json bytes kept (Standard)" "$BEFORE" "$(sum "$PROJ/.claude/settings.json")"
make_project
run_perms apply "${STANDARD[@]}"
assert_eq "no settings.json created" "settings.local.json" "$(ls -A "$PROJ/.claude")"

echo "Test: the Standard list anchors the init rule to an absolute path"
assert_eq "init rule is prefix-anchored" "1" "$(printf '%s\n' "${STANDARD[@]}" | grep -cxF 'Bash(/*/spex-init.sh*)')"
assert_eq "broad init rule is gone" "0" "$(printf '%s\n' "${STANDARD[@]}" | grep -cxF 'Bash(*spex-init.sh*)')"

echo "Test: apply then migrate repairs both files (init Step 2 sequence)"
make_project
put .claude/settings.json '{"permissions":{"allow":["Edit(*)","Bash(team rule)"]}}'
put .claude/settings.local.json '{"permissions":{"allow":["Read(*)","Bash(*)","Bash(make *)"]}}'
run_perms apply "${STANDARD[@]}"
APPLY_ERR=$ERR
assert_not_contains "apply leaves settings.json alone" "settings.json" "$APPLY_ERR"
assert_eq "apply merged into settings.local.json (legacy rules collapse)" '["Read","Bash","Bash(make *)","Skill","Bash(specify *)","Bash(/*/spex-init.sh*)","Bash(*spex-ship-statusline.sh*)"]' "$(allow .claude/settings.local.json)"
run_perms migrate
assert_eq "settings.json migrated" '["Edit","Bash(team rule)"]' "$(allow .claude/settings.json)"
assert_eq "Migrated line" "Migrated: .claude/settings.json permissions: Edit(*) -> Edit" "$ERR"

echo "Test: a rule argument with a newline stays one rule"
make_project
run_perms apply "Read(notes
Bash
archive/**)" Skill
assert_eq "argument boundaries kept" '["Read(notes\nBash\narchive/**)","Skill"]' "$(allow .claude/settings.local.json)"
assert_eq "no bare Bash smuggled in" "0" "$(jq '[.permissions.allow[] | select(. == "Bash")] | length' "$PROJ/.claude/settings.local.json")"

echo "Test: apply with --root from another directory"
make_project
mkdir -p "$TMPROOT/elsewhere"
RC=0
(cd "$TMPROOT/elsewhere" && HOME="$TMPROOT/home" sh "$PERMS" apply --root "$PROJ" Skill 2> "$TMPROOT/err") || RC=$?
assert_eq "exit code 0" "0" "$RC"
assert_eq "written under root" '["Skill"]' "$(allow .claude/settings.local.json)"
assert_eq "nothing written in cwd" "" "$(ls -A "$TMPROOT/elsewhere")"

echo "Test: apply never touches user-level settings (FR-012)"
make_project
mkdir -p "$TMPROOT/home/.claude"
printf '%s' '{"permissions":{"allow":["Read(*)"]}}' > "$TMPROOT/home/.claude/settings.local.json"
BEFORE=$(sum "$TMPROOT/home/.claude/settings.local.json")
run_perms apply --default-mode bypassPermissions "${YOLO[@]}"
assert_eq "user settings bytes kept" "$BEFORE" "$(sum "$TMPROOT/home/.claude/settings.local.json")"

# expect_not_applied <desc> <content> <warning>: apply leaves settings.local.json
# with <content> byte-identical, warns, and exits 0.
expect_not_applied() {
  make_project
  put .claude/settings.local.json "$2"
  local before
  before=$(sum "$PROJ/.claude/settings.local.json")
  run_perms apply --default-mode bypassPermissions "${YOLO[@]}"
  assert_eq "$1: exit code 0" "0" "$RC"
  assert_eq "$1: bytes kept" "$before" "$(sum "$PROJ/.claude/settings.local.json")"
  assert_contains "$1: warning" "$3" "$ERR"
  assert_not_contains "$1: no configured line" "Permissions configured" "$ERR"
}

echo "Test: invalid JSON or an unexpected shape is never overwritten"
expect_not_applied "invalid JSON" '{"permissions":' "WARNING: .claude/settings.local.json is not valid JSON; permissions not applied"
expect_not_applied "empty file" '' "WARNING: .claude/settings.local.json is not valid JSON; permissions not applied"
expect_not_applied "top level array" '["Skill"]' "WARNING: .claude/settings.local.json has an unexpected structure; permissions not applied"
expect_not_applied "top level null" 'null' "WARNING: .claude/settings.local.json has an unexpected structure; permissions not applied"
expect_not_applied "permissions is a string" '{"permissions":"yolo"}' "WARNING: .claude/settings.local.json has an unexpected structure; permissions not applied"
expect_not_applied "allow is an object" '{"permissions":{"allow":{}}}' "WARNING: .claude/settings.local.json has an unexpected structure; permissions not applied"
expect_not_applied "allow is null" '{"permissions":{"allow":null}}' "WARNING: .claude/settings.local.json has an unexpected structure; permissions not applied"

echo "Test: a write failure in apply keeps the original and warns"
if [ "$(id -u)" -eq 0 ]; then
  echo "  SKIP: running as root, directory permissions are not enforced"
else
  make_project
  put .claude/settings.local.json '{"permissions":{"allow":["Read(*)"]}}'
  BEFORE=$(sum "$PROJ/.claude/settings.local.json")
  chmod 555 "$PROJ/.claude"
  run_perms apply Skill
  chmod 755 "$PROJ/.claude"
  assert_eq "exit code 0" "0" "$RC"
  assert_eq "original intact" "$BEFORE" "$(sum "$PROJ/.claude/settings.local.json")"
  assert_contains "write warning" "WARNING: could not write .claude/settings.local.json; permissions not applied" "$ERR"
  assert_not_contains "no Migrated line" "Migrated:" "$ERR"

  make_project
  chmod 555 "$PROJ"
  run_perms apply Skill
  chmod 755 "$PROJ"
  assert_eq "missing .claude, unwritable root: exit code 0" "0" "$RC"
  assert_contains "missing .claude, unwritable root: warning" "WARNING: could not write .claude/settings.local.json; permissions not applied" "$ERR"
fi

# ===================================================================
# rule lists in setup.yml and the init skill (FR-001, FR-002, FR-014, FR-016)
# ===================================================================

SKILL_MD="$REPO_ROOT/spex/skills/init/SKILL.md"
SETUP_YML="$REPO_ROOT/spex/setup.yml"

# skill_block <level>: the fenced bash block that follows "- **<level>**:" in
# the Permissions part of the init skill.
skill_block() {
  awk -v hdr="- **$1**:" '
    index($0, hdr) == 1 { found = 1; next }
    found && /^  ```bash$/ { inblock = 1; next }
    inblock && /^  ```$/ { exit }
    inblock { sub(/^  /, ""); print }
  ' "$SKILL_MD"
}

# setup_apply_lines: the spex-permissions.sh apply calls in setup.yml,
# with their continuation lines.
setup_apply_lines() {
  awk '/sh "\$PERMS" apply/ { on = 1 } on { print } on && !/\\$/ { on = 0 }' "$SETUP_YML"
}

LEGACY_RE='(^|[[:space:]])'"'"'?(Bash|Read|Edit|Write)\(\*\)'"'"'?([[:space:]]|$)'

echo "Test: rule lists in setup.yml and the init skill"
for level in Standard YOLO None; do
  block=$(skill_block "$level")
  assert_contains "skill $level block calls the script" "spex-permissions.sh" "$block"
  assert_contains "skill $level block migrates" "spex-permissions.sh\" migrate" "$block"
  if printf '%s\n' "$block" | grep -Eq "$LEGACY_RE"; then
    echo "  FAIL: skill $level block passes a legacy Tool(*) rule"; FAIL=$((FAIL + 1))
  else
    echo "  PASS: skill $level block passes no legacy Tool(*) rule"; PASS=$((PASS + 1))
  fi
done
applies=$(setup_apply_lines)
assert_eq "setup.yml has two apply calls" "2" "$(printf '%s\n' "$applies" | grep -c 'apply')"
if printf '%s\n' "$applies" | grep -Eq "$LEGACY_RE"; then
  echo "  FAIL: setup.yml passes a legacy Tool(*) rule"; FAIL=$((FAIL + 1))
else
  echo "  PASS: setup.yml passes no legacy Tool(*) rule"; PASS=$((PASS + 1))
fi
assert_contains "setup.yml migrate step" 'spex-permissions.sh" migrate' "$(cat "$SETUP_YML")"

echo "Test: the init skill's YOLO block writes bare rules once each (US1-1)"
make_project
put .claude/settings.json '{"permissions":{"allow":["Bash(*)","Read(*)","Edit(*)","Write(*)","Bash(npm test)"]}}'
put .claude/settings.local.json '{"permissions":{"allow":["Read(*)"]}}'
YOLO_BLOCK=$(skill_block YOLO | sed "s#<scripts>#$REPO_ROOT/spex/scripts#g")
RC=0
(cd "$PROJ" && HOME="$TMPROOT/home" sh -c "$YOLO_BLOCK" > "$TMPROOT/out" 2> "$TMPROOT/err") || RC=$?
ERR=$(cat "$TMPROOT/err")
assert_eq "exit code 0" "0" "$RC"
for t in Bash Read Edit Write; do
  assert_eq "$t exactly once in settings.local.json" "1" "$(jq --arg t "$t" '[.permissions.allow[] | select(. == $t)] | length' "$PROJ/.claude/settings.local.json")"
done
assert_eq "no legacy form left in settings.local.json" "0" "$(jq '[.permissions.allow[] | select(. == "Bash(*)" or . == "Read(*)" or . == "Edit(*)" or . == "Write(*)")] | length' "$PROJ/.claude/settings.local.json")"
assert_eq "defaultMode set in settings.local.json" "bypassPermissions" "$(jq -r .permissions.defaultMode "$PROJ/.claude/settings.local.json")"
assert_eq "committed settings.json only migrated, no YOLO rules or mode added" '["Bash","Read","Edit","Write","Bash(npm test)"]|false' "$(allow .claude/settings.json)|$(jq '.permissions | has("defaultMode")' "$PROJ/.claude/settings.json")"
assert_contains "Migrated line for settings.json" "Migrated: .claude/settings.json permissions:" "$ERR"
assert_contains "Migrated line for settings.local.json" "Migrated: .claude/settings.local.json permissions: Read(*) -> Read" "$ERR"
assert_contains "apply result names settings.local.json" "Permissions configured in .claude/settings.local.json" "$ERR"

echo "Test: usage errors exit 2 and change nothing"
make_project
put .claude/settings.json '{"permissions":{"allow":["Read(*)"]}}'
BEFORE=$(sum "$PROJ/.claude/settings.json")
run_perms
assert_eq "no subcommand exits 2" "2" "$RC"
assert_contains "usage printed" "Usage: spex-permissions.sh" "$ERR"
run_perms bogus
assert_eq "unknown subcommand exits 2" "2" "$RC"
run_perms apply
assert_eq "apply without rules exits 2" "2" "$RC"
run_perms apply --default-mode
assert_eq "--default-mode without value exits 2" "2" "$RC"
run_perms apply --bogus Skill
assert_eq "unknown option exits 2" "2" "$RC"
run_perms migrate --default-mode bypassPermissions
assert_eq "--default-mode on migrate exits 2" "2" "$RC"
run_perms migrate Skill
assert_eq "migrate with rules exits 2" "2" "$RC"
run_perms migrate --root "$TMPROOT/missing"
assert_eq "missing --root exits 2" "2" "$RC"
run_perms apply --root
assert_eq "--root without value exits 2" "2" "$RC"
assert_eq "usage errors change nothing" "$BEFORE" "$(sum "$PROJ/.claude/settings.json")"
assert_eq "stdout stays empty" "" "$OUT"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
