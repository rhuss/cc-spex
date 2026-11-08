#!/bin/sh
# spex-permissions.sh - Owns every Claude Code permission write spex makes in a
# project (spec 061).
#
# Usage:
#   spex-permissions.sh migrate [--root DIR]
#   spex-permissions.sh apply [--root DIR] [--default-mode MODE] RULE...
#
#   migrate  Rewrite the legacy allow rules Bash(*), Read(*), Edit(*) and
#            Write(*) to their bare tool names in .claude/settings.json and
#            .claude/settings.local.json under DIR, when those files exist.
#   apply    Append each RULE that is missing to permissions.allow in
#            .claude/settings.json (created when missing), keeping the order
#            of the existing entries, optionally set permissions.defaultMode,
#            then migrate legacy rules in the same file.
#
#   --root          Project root (default: current directory). Paths in the
#                   output are relative to it.
#   --default-mode  Value for permissions.defaultMode (apply only).
#
# Only the project settings files are touched, never the user-level settings
# (~/.claude/settings.json, ~/.claude/settings.local.json, and the same files
# under $CLAUDE_CONFIG_DIR). A project settings path that resolves to one of
# them (through a symlink, a symlinked .claude directory, or a project root
# that is the home directory) is left alone with a warning.
# A file is written only when its content changes; otherwise its bytes are
# kept. Settings files that are not valid JSON or have an unexpected shape
# are left alone.
#
# Output goes to stderr (stdout stays empty):
#   Migrated: <file> permissions: <old> -> <new>[, <old> -> <new>...]
#   Default mode set to <mode> in <file>
#   Permissions configured in <file> (<n> rules added)
#   WARNING: <file> ...
#
# Exit codes: 0 success (including no-op and every WARNING case), 1 jq is not
# installed (apply only; migrate warns and exits 0), 2 usage error.

set -u
# Rules such as Bash(*) must never expand as globs.
set -f
# cd must resolve paths exactly as given, never through CDPATH.
unset CDPATH

SETTINGS_FILES=".claude/settings.json .claude/settings.local.json"

usage_text() {
  echo "Usage: spex-permissions.sh migrate [--root DIR]"
  echo "       spex-permissions.sh apply [--root DIR] [--default-mode MODE] RULE..."
}

usage() {
  usage_text >&2
  exit 2
}

warn() {
  printf 'WARNING: %s\n' "$*" >&2
}

# phys_dir <dir>: print the physical path of <dir> (symlinks resolved, ".."
# applied after them, as the kernel does). A directory that does not exist yet
# is resolved through its nearest existing ancestor.
phys_dir() {
  if [ -d "$1" ]; then
    # "./" keeps a relative name such as "-" from being read as an option.
    case "$1" in
      /*) (cd -P "$1" 2>/dev/null && pwd -P) ;;
      *) (cd -P "./$1" 2>/dev/null && pwd -P) ;;
    esac
  else
    # "." or ".." after a missing directory cannot be resolved physically.
    case "$(basename "$1")" in
      .|..) return 1 ;;
    esac
    _pd=$(phys_dir "$(dirname "$1")") || return 1
    printf '%s/%s\n' "${_pd%/}" "$(basename "$1")"
  fi
}

# canon <path>: print the physical path that a write to <path> lands on:
# symlinks in the directories and in the last component are followed (relative
# link targets against the link's directory), so the file stays a link and its
# target is updated. Fails after 40 hops, and fails whenever the result is
# not the file the kernel opens for <path> (for example names that end in a
# newline, which command substitution would strip), so callers can rely on it.
canon() {
  _c=$1
  _ch=0
  while :; do
    _cd=$(phys_dir "$(dirname "$_c")") || return 1
    _c="${_cd%/}/$(basename "$_c")"
    [ -L "$_c" ] || break
    _ch=$((_ch + 1))
    [ "$_ch" -le 40 ] || return 1
    # The trailing "x" keeps newlines at the end of the link target.
    _cl=$(readlink "$_c" && echo x) || return 1
    _cl=${_cl%?x}
    case "$_cl" in
      /*) _c=$_cl ;;
      *) _c="${_cd%/}/$_cl" ;;
    esac
  done
  if [ -e "$1" ] && ! [ "$1" -ef "$_c" ]; then
    return 1
  fi
  # Callers read the result through command substitution, which would strip
  # a trailing newline and silently change the path.
  case "$_c" in
    *'
') return 1 ;;
  esac
  printf '%s\n' "$_c"
}

# same_file <a> <b>: true when the canonical paths <a> and <b> name the same
# file. Existing files are compared by identity (-ef: device and inode), which
# also catches hard links and case-insensitive file systems. A file that does
# not exist yet matches when its directory is the same directory and the
# names are equal ignoring case.
same_file() {
  [ "$1" = "$2" ] && return 0
  if [ -e "$1" ] && [ -e "$2" ]; then
    [ "$1" -ef "$2" ]
    return
  fi
  _ad=$(dirname "$1")
  _bd=$(dirname "$2")
  [ -d "$_ad" ] && [ -d "$_bd" ] && [ "$_ad" -ef "$_bd" ] || return 1
  [ "$(basename "$1" | tr '[:upper:]' '[:lower:]')" = "$(basename "$2" | tr '[:upper:]' '[:lower:]')" ]
}

# is_user_settings <canonical-path>: true when the path names one of the
# user-level Claude settings files (FR-012) in ~/.claude or in
# $CLAUDE_CONFIG_DIR. The user side is canonicalized too, so a user settings
# file that is itself a symlink (dotfile managers) is still recognized. Both
# directories count, because either can hold the user's settings.
is_user_settings() {
  for _udir in "${HOME:+$HOME/.claude}" "${CLAUDE_CONFIG_DIR:-}"; do
    [ -n "$_udir" ] || continue
    for _un in settings.json settings.local.json; do
      _up=$(canon "$_udir/$_un") || continue
      same_file "$1" "$_up" && return 0
    done
  done
  return 1
}

# project_target <relpath>: print the canonical path of a project settings
# file under $ROOT. Fails (after a warning) when the path cannot be resolved
# or resolves to the user-level settings; every read and write then uses the
# printed path, so the checked file and the used file are the same.
project_target() {
  if ! _pt=$(canon "$ROOT/$1"); then
    warn "$1 cannot be resolved safely; left unchanged"
    return 1
  fi
  if is_user_settings "$_pt"; then
    warn "$1 resolves to the user-level Claude settings; left unchanged"
    return 1
  fi
  printf '%s\n' "$_pt"
}

# safe_write <target>: replace <target> with the content read from stdin.
# The content goes to a temporary file next to the resolved target, which then
# takes the target's place with mv, so a failure at any point leaves the
# original file intact. An existing target keeps its file mode. Returns
# non-zero on failure, after removing the temporary file. A trap removes the
# temporary file when the script is interrupted while it exists.
safe_write() {
  # Callers pass the canonical path from project_target. Resolve it again and
  # re-check it, so a link swapped in the meantime cannot redirect the write
  # to the user-level settings.
  _target=$(canon "$1") || return 1
  is_user_settings "$_target" && return 1
  _dir=$(dirname "$_target")
  _tmp="$_dir/.$(basename "$_target").spex-tmp.$$"
  # noclobber: create the temporary file exclusively, with the umask's mode.
  if ! (set -C; : > "$_tmp") 2>/dev/null; then
    return 1
  fi
  trap 'rm -f "$_tmp"' EXIT
  trap 'rm -f "$_tmp"; exit 130' INT HUP TERM
  # Braces: a failing redirection reports on the group's stderr, which is
  # silenced, so only the caller's WARNING line reaches the user.
  if { [ -e "$_target" ] && ! cp -p "$_target" "$_tmp"; } 2>/dev/null ||
     ! { cat > "$_tmp"; } 2>/dev/null ||
     ! mv -f "$_tmp" "$_target" 2>/dev/null; then
    rm -f "$_tmp"
    trap - EXIT INT HUP TERM
    return 1
  fi
  trap - EXIT INT HUP TERM
  return 0
}

# jq definitions shared by migrate and apply.
#   mig: allow list -> {list, pairs}. Maps the exact legacy strings to their
#        bare names. pairs lists each legacy string found once, in order of
#        first occurrence. Only when pairs is non-empty, later occurrences of
#        the four bare names are dropped (the first one keeps its position);
#        every other entry, duplicates and non-strings included, stays put.
# shellcheck disable=SC2016
JQ_DEFS='
def legacy_map: {"Bash(*)": "Bash", "Read(*)": "Read", "Edit(*)": "Edit", "Write(*)": "Write"};
def is_legacy: if type == "string" then legacy_map[.] != null else false end;
def is_bare: . as $x | any(("Bash", "Read", "Edit", "Write"); . == $x);
def mig:
  . as $a
  | (reduce ($a[] | select(is_legacy)) as $x ([]; if any(.[]; . == $x) then . else . + [$x] end)) as $p
  | if ($p | length) == 0 then {list: $a, pairs: []}
    else {
      list: (reduce ($a[] | if is_legacy then legacy_map[.] else . end) as $x ({out: [], seen: []};
               if ($x | is_bare) then
                 (if any(.seen[]; . == $x) then . else .out += [$x] | .seen += [$x] end)
               else .out += [$x] end)
             | .out),
      pairs: [$p[] | "\(.) -> \(legacy_map[.])"]
    }
    end;
'

# migrate program: settings document -> {status, pairs, doc}.
#   status "skip"      unexpected shape (silent no-op)
#   status "unchanged" no legacy rule
#   status "migrated"  doc holds the new document, pairs the rewrites
# shellcheck disable=SC2016
JQ_MIGRATE='
if type != "object" then {status: "skip"}
elif (.permissions | type) != "object" then {status: "skip"}
elif (.permissions.allow | type) != "array" then {status: "skip"}
else
  (.permissions.allow | mig) as $m
  | if ($m.pairs | length) == 0 then {status: "unchanged"}
    else {status: "migrated", pairs: ($m.pairs | join(", ")), doc: (.permissions.allow = $m.list)}
    end
end
'

# is_json_document <file>: true when the file holds exactly one JSON value.
is_json_document() {
  jq -e -s 'length == 1' "$1" >/dev/null 2>&1
}

# migrate_file <relpath>: migrate one settings file under $ROOT.
# Never fails the run; problems are reported as warnings.
migrate_file() {
  _rel=$1
  [ -f "$ROOT/$_rel" ] || return 0
  # From here on, every read and write uses the checked canonical path.
  _file=$(project_target "$_rel") || return 0
  if ! is_json_document "$_file"; then
    warn "$_rel is not valid JSON; permission rules not migrated"
    return 0
  fi
  # Shape guard inside JQ_MIGRATE: anything but an object with a
  # permissions object holding an allow array is a silent no-op.
  _res=$(jq -c "$JQ_DEFS $JQ_MIGRATE" "$_file" 2>/dev/null) || return 0
  [ "$(printf '%s' "$_res" | jq -r '.status')" = migrated ] || return 0
  _pairs=$(printf '%s' "$_res" | jq -r '.pairs') || return 0
  _doc=$(printf '%s' "$_res" | jq '.doc') || return 0
  if ! printf '%s\n' "$_doc" | safe_write "$_file"; then
    warn "could not write $_rel; permission rules not migrated"
    return 0
  fi
  printf 'Migrated: %s permissions: %s\n' "$_rel" "$_pairs" >&2
}

do_migrate() {
  for _f in $SETTINGS_FILES; do
    migrate_file "$_f"
  done
}

# apply program: settings document -> {status, n, pairs, doc}.
#   $rules  allow rules to append when missing (JSON array, argument order)
#   $mode   value for permissions.defaultMode, or "" to leave it alone
#   status "shape"     unexpected structure (nothing is applied)
#   status "unchanged" nothing to add, mode already set, no legacy rule
#   status "changed"   doc holds the new document
# A missing permissions object or allow list is created. The merged list is
# migrated (see mig), so legacy rules collapse into the bare forms. n counts
# the entries of the result that the migrated original list did not hold.
# shellcheck disable=SC2016
JQ_APPLY='
if type != "object" then {status: "shape"}
elif has("permissions") and ((.permissions | type) != "object") then {status: "shape"}
elif ((.permissions // {}) | has("allow")) and ((.permissions.allow | type) != "array") then {status: "shape"}
else
  (.permissions.allow // []) as $orig
  | ($orig | mig) as $before
  | (reduce $rules[] as $r ($orig; if any(.[]; . == $r) then . else . + [$r] end) | mig) as $after
  | ([$after.list[] | . as $e | select(($before.list | any(.[]; . == $e)) | not)] | length) as $n
  | ((if $mode == "" then . else .permissions.defaultMode = $mode end) | .permissions.allow = $after.list) as $doc
  | {
      status: (if $doc == . then "unchanged" else "changed" end),
      mode_set: ($mode != "" and ((.permissions // {}).defaultMode != $mode)),
      n: $n,
      pairs: ($after.pairs | join(", ")),
      doc: $doc
    }
end
'

# do_apply RULE...: merge the rules into .claude/settings.json under $ROOT.
# Never fails the run; problems are reported as warnings.
do_apply() {
  _rel=".claude/settings.json"
  # From here on, every read and write uses the checked canonical path.
  _file=$(project_target "$_rel") || return 0
  # One JSON string per argument, in argument order, with argument boundaries
  # kept even for rules that contain a newline (works with jq 1.5, unlike
  # $ARGS.positional).
  _rules='[]'
  for _r in "$@"; do
    _rules=$(jq -cn --argjson a "$_rules" --arg r "$_r" '$a + [$r]') || { warn "could not read the rules; permissions not applied"; return 0; }
  done

  if [ -e "$_file" ]; then
    if ! is_json_document "$_file"; then
      warn "$_rel is not valid JSON; permissions not applied"
      return 0
    fi
    _res=$(jq -c --argjson rules "$_rules" --arg mode "$DEFAULT_MODE" "$JQ_DEFS $JQ_APPLY" "$_file" 2>/dev/null)
  else
    _res=$(printf '{}' | jq -c --argjson rules "$_rules" --arg mode "$DEFAULT_MODE" "$JQ_DEFS $JQ_APPLY" 2>/dev/null)
  fi
  [ -n "$_res" ] || { warn "could not process $_rel; permissions not applied"; return 0; }

  _status=$(printf '%s' "$_res" | jq -r '.status')
  if [ "$_status" = shape ]; then
    warn "$_rel has an unexpected structure; permissions not applied"
    return 0
  fi
  _n=$(printf '%s' "$_res" | jq -r '.n')
  _pairs=$(printf '%s' "$_res" | jq -r '.pairs')

  if [ "$_status" = changed ]; then
    _doc=$(printf '%s' "$_res" | jq '.doc') || { warn "could not process $_rel; permissions not applied"; return 0; }
    if ! mkdir -p "$ROOT/.claude" 2>/dev/null || ! printf '%s\n' "$_doc" | safe_write "$_file"; then
      warn "could not write $_rel; permissions not applied"
      return 0
    fi
    if [ -n "$_pairs" ]; then
      printf 'Migrated: %s permissions: %s\n' "$_rel" "$_pairs" >&2
    fi
    if [ "$(printf '%s' "$_res" | jq -r '.mode_set')" = true ]; then
      printf 'Default mode set to %s in %s\n' "$DEFAULT_MODE" "$_rel" >&2
    fi
  fi
  printf 'Permissions configured in %s (%s rules added)\n' "$_rel" "$_n" >&2
}

# --- Argument parsing ---

[ $# -gt 0 ] || usage
SUBCOMMAND=$1
shift
case "$SUBCOMMAND" in
  migrate|apply) ;;
  --help|-h)
    usage_text
    exit 0
    ;;
  *)
    echo "ERROR: unknown subcommand '$SUBCOMMAND'" >&2
    usage
    ;;
esac

ROOT="."
DEFAULT_MODE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      [ $# -ge 2 ] || { echo "ERROR: --root needs a directory" >&2; usage; }
      ROOT=$2
      shift 2
      ;;
    --default-mode)
      [ "$SUBCOMMAND" = apply ] || { echo "ERROR: --default-mode is only valid for apply" >&2; usage; }
      [ $# -ge 2 ] && [ -n "$2" ] || { echo "ERROR: --default-mode needs a value" >&2; usage; }
      DEFAULT_MODE=$2
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "ERROR: unknown option '$1'" >&2
      usage
      ;;
    *)
      break
      ;;
  esac
done

[ -d "$ROOT" ] || { echo "ERROR: --root '$ROOT' is not a directory" >&2; usage; }

if [ "$SUBCOMMAND" = migrate ]; then
  [ $# -eq 0 ] || { echo "ERROR: migrate takes no rules" >&2; usage; }
else
  [ $# -gt 0 ] || { echo "ERROR: apply needs at least one rule" >&2; usage; }
fi

if ! command -v jq >/dev/null 2>&1; then
  if [ "$SUBCOMMAND" = migrate ]; then
    # Never fail or print an ERROR for refresh: without settings files there
    # is nothing to do, and with them the files stay as they are.
    for _f in $SETTINGS_FILES; do
      if [ -f "$ROOT/$_f" ]; then
        warn "jq is not installed; permission rules in $_f not migrated"
      fi
    done
    exit 0
  fi
  echo "ERROR: jq is required" >&2
  exit 1
fi

case "$SUBCOMMAND" in
  migrate) do_migrate ;;
  apply) do_apply "$@" ;;
esac
exit 0
