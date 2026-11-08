#!/bin/sh
# spex-apply-extensions.sh - Make the enabled optional spex extensions match a
# resolved selection (FR-003, FR-006, FR-018).
#
# Usage:
#   spex-apply-extensions.sh [--before <registry-snapshot.json>] <selection>
#
#   <selection>  Comma-separated, already resolved list (core spex and
#                dependencies included), for example
#                "spex,spex-gates,spex-worktrees,spex-deep-review".
#   --before     Copy of .specify/extensions/.registry taken before the
#                extensions were reinstalled. Changes are reported against it.
#
# Runs from the project root. State changes go only through
# `specify extension enable/disable`. The core `spex` extension and every
# extension spex does not ship are never disabled; the spec-kit `git`
# extension is enabled (never disabled) when spex-worktrees is selected.
#
# When spex-detach ends up enabled, its exclude entries are written (or
# repaired) and verified through `spex-detach.sh ensure` (stealth mode). That
# step reports `Stealth mode: ...`, `Repaired stealth mode: ...` or a
# `WARNING: stealth mode is NOT fully active` block (also when `ensure` itself
# fails, for example without Python) and never changes the exit code.
# Without an enabled spex-detach nothing is written or printed.
#
# Output goes to stderr: one `Enabled: <ext>` / `Disabled: <ext>` line per
# change, the stealth-mode lines, then
# `Extensions: <n> enabled, <m> disabled, <k> unchanged`.
#
# Exit codes: 0 success, 1 a required change failed or a selected extension
# is not installed, 2 usage error.

set -u
# Word splitting of the selection must never expand globs.
set -f

# The optional spex extensions this script enforces. Keep in sync with
# EXTENSIONS in spex-setup-profile.py, the install-ext-* steps in setup.yml
# and install_order in spex-init.sh.
OPTIONAL_EXTENSIONS="spex-gates spex-worktrees spex-deep-review spex-teams spex-collab spex-detach"
REGISTRY=".specify/extensions/.registry"

usage() {
  echo "Usage: spex-apply-extensions.sh [--before <registry-snapshot.json>] <comma-separated selection>" >&2
  exit 2
}

BEFORE=""
SELECTION=""
have_selection=false
while [ $# -gt 0 ]; do
  case "$1" in
    --before)
      [ $# -ge 2 ] || usage
      BEFORE="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: spex-apply-extensions.sh [--before <registry-snapshot.json>] <comma-separated selection>"
      exit 0
      ;;
    -*)
      echo "ERROR: unknown option '$1'" >&2
      usage
      ;;
    *)
      [ "$have_selection" = false ] || { echo "ERROR: more than one selection given" >&2; usage; }
      SELECTION="$1"
      have_selection=true
      shift
      ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 1; }

SELECTED=$(printf '%s' "$SELECTION" | tr ',' ' ')
# Collapse whitespace so an all-blank selection counts as empty.
SELECTED=$(echo $SELECTED)
if [ -z "$SELECTED" ]; then
  echo "ERROR: empty extension selection" >&2
  usage
fi

for name in $SELECTED; do
  case " spex $OPTIONAL_EXTENSIONS " in
    *" $name "*) ;;
    *) echo "ERROR: unknown spex extension '$name'" >&2; exit 2 ;;
  esac
done

if [ -n "$BEFORE" ]; then
  if [ ! -r "$BEFORE" ] || ! jq -e 'type == "object"' "$BEFORE" >/dev/null 2>&1; then
    echo "ERROR: cannot read registry snapshot '$BEFORE'" >&2
    exit 2
  fi
fi

is_selected() {
  case " $SELECTED " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

# state <file> <id>: prints true, false, or absent.
state() {
  [ -f "$1" ] || { echo absent; return 0; }
  jq -r --arg id "$2" '
    (.extensions // {})[$id] |
    if . == null then "absent" elif .enabled == false then "false" else "true" end
  ' "$1" 2>/dev/null || echo absent
}

# Fail before changing anything when a selected extension is missing.
missing=""
for ext in $OPTIONAL_EXTENSIONS; do
  if is_selected "$ext" && [ "$(state "$REGISTRY" "$ext")" = absent ]; then
    missing="$missing $ext"
  fi
done
if [ -n "$missing" ]; then
  for ext in $missing; do
    echo "ERROR: selected extension '$ext' is not installed" >&2
  done
  exit 1
fi

n_enabled=0
n_disabled=0
n_unchanged=0
rc=0

# spex-detach state before the loop: the reference for "repaired" vs. "written"
# when the snapshot does not know the extension.
detach_pre=$(state "$REGISTRY" spex-detach)

for ext in $OPTIONAL_EXTENSIONS; do
  current=$(state "$REGISTRY" "$ext")
  [ "$current" != absent ] || continue

  if is_selected "$ext"; then
    want=true; action=enable
  else
    want=false; action=disable
  fi

  if [ "$current" != "$want" ]; then
    if ! msg=$(specify extension "$action" "$ext" 2>&1); then
      echo "ERROR: could not $action extension '$ext'" >&2
      [ -z "$msg" ] || printf '%s\n' "$msg" | sed 's/^/  /' >&2
      rc=1
      n_unchanged=$((n_unchanged + 1))
      continue
    fi
  fi

  # Report against the snapshot when it knows the extension, otherwise
  # against the state found before this run.
  reference="$current"
  if [ -n "$BEFORE" ]; then
    previous=$(state "$BEFORE" "$ext")
    [ "$previous" = absent ] || reference="$previous"
  fi
  if [ "$reference" = "$want" ]; then
    n_unchanged=$((n_unchanged + 1))
  elif [ "$want" = true ]; then
    echo "Enabled: $ext" >&2
    n_enabled=$((n_enabled + 1))
  else
    echo "Disabled: $ext" >&2
    n_disabled=$((n_disabled + 1))
  fi
done

# spex-worktrees needs the spec-kit git extension for branch creation. Only
# warn here: the git checks in setup.yml and spex-init.sh report the error.
if is_selected spex-worktrees; then
  case "$(state "$REGISTRY" git)" in
    true) ;;
    false)
      if specify extension enable git >/dev/null 2>&1; then
        echo "Enabled: git (required by spex-worktrees)" >&2
      else
        echo "WARNING: could not enable the git extension (required by spex-worktrees)" >&2
      fi
      ;;
    *)
      echo "WARNING: the git extension (required by spex-worktrees) is not installed; the git check after this step reports it if it stays missing" >&2
      ;;
  esac
fi

# Stealth mode: write missing spex-detach exclude entries and verify them.
# Only stderr is relayed; the result never changes the exit code (FR-004).
DETACH_SCRIPT=".specify/extensions/spex-detach/scripts/spex-detach.sh"
if [ "$(state "$REGISTRY" spex-detach)" = true ] && [ -x "$DETACH_SCRIPT" ]; then
  detach_ref="$detach_pre"
  if [ -n "$BEFORE" ]; then
    detach_prev=$(state "$BEFORE" spex-detach)
    [ "$detach_prev" = absent ] || detach_ref="$detach_prev"
  fi
  # spex-init.sh leaves this marker when spex-detach was enabled before a
  # setup run whose workflow disabled it again (no declaration yet).
  DETACH_MARKER=".specify/.spex-detach-was-enabled"
  if [ -f "$DETACH_MARKER" ]; then
    detach_ref=true
    rm -f "$DETACH_MARKER"
  fi
  detach_rc=0
  detach_err=$(mktemp "${TMPDIR:-/tmp}/spex-detach-err.XXXXXX") || detach_err=/dev/null
  if [ "$detach_ref" = true ]; then
    detach_out=$("$DETACH_SCRIPT" ensure --was-enabled 2>"$detach_err") || detach_rc=$?
  else
    detach_out=$("$DETACH_SCRIPT" ensure 2>"$detach_err") || detach_rc=$?
  fi
  [ "$detach_err" = /dev/null ] || { cat "$detach_err" >&2; }
  # `ensure` prints its JSON result on stdout for exit 0 (active) and 1 (a
  # path is visible); exit 2 means "not a git repository" and stays silent.
  # Any other failure (no Python, a crash) printed no stealth-mode line, so
  # say so, with the last error line (callers may filter the rest out).
  # Keep in sync with report_detach_crash in spex-init.sh.
  if [ "$detach_rc" -ne 0 ] && [ "$detach_rc" -ne 2 ] && [ -z "$detach_out" ]; then
    detach_last=$(tail -n 1 "$detach_err" 2>/dev/null)
    echo "WARNING: stealth mode is NOT fully active. The exclude entries could not be written or verified:" >&2
    echo "  spex-detach.sh ensure failed with exit code $detach_rc${detach_last:+: $detach_last}" >&2
  fi
  [ "$detach_err" = /dev/null ] || rm -f "$detach_err"
fi

echo "Extensions: $n_enabled enabled, $n_disabled disabled, $n_unchanged unchanged" >&2
exit "$rc"
