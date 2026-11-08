#!/bin/sh
# spex-detach-config.sh - Keep the spex-detach configuration across an
# extension reinstall (FR-007, FR-009).
#
# Usage (from the project root):
#   spex-detach-config.sh save     # before any extension is uninstalled
#   spex-detach-config.sh restore  # right after spex-detach is re-added
#   spex-detach-config.sh pending  # exit 0 when a saved copy waits to be
#                                  # restored into an installed spex-detach
#
# `specify extension remove` deletes .specify/extensions/spex-detach/ with
# its configuration, and `add` installs the template. `save` copies the
# configuration to a place outside the extension directory; `restore` moves
# it back over the template, byte for byte. The preserved file is never
# merged with a newer template (FR-009a).
#
#   save:    config present -> copy to the saved file (exit 1 on failure,
#            nothing changed). Config missing, or config identical to the
#            template while a saved copy that differs from it is present
#            (left by a run that installed the template but did not
#            restore) -> keep the saved copy. Neither -> no-op.
#   restore: saved copy present -> move it over the config (exit 1 on
#            failure, the saved copy stays). No saved copy -> no-op (the
#            template stays, FR-008).
#   pending: exit 0 when a saved copy exists and spex-detach is installed
#            (restore would apply it), 1 otherwise. Changes nothing.
#
# Exit codes: 0 success, 1 save or restore failed (pending: nothing to
# restore), 2 usage error.

set -u

CONFIG=".specify/extensions/spex-detach/spex-detach-config.yml"
SAVED=".specify/.spex-detach-config.saved.yml"
# The template the extension installs; this script lives in <spex>/scripts.
TEMPLATE="$(dirname "$0")/../extensions/spex-detach/config-template.yml"

usage() {
  echo "Usage: spex-detach-config.sh save|restore|pending" >&2
  exit 2
}

[ $# -eq 1 ] || usage

case "$1" in
  save)
    if [ -f "$CONFIG" ]; then
      # A saved copy left by a run that installed the template but did not
      # restore (interrupted, or restore failed) holds the user's real
      # configuration. Never overwrite it with the template.
      if [ -f "$SAVED" ] && [ ! -L "$SAVED" ] && [ -f "$TEMPLATE" ] &&
         cmp -s "$CONFIG" "$TEMPLATE" && ! cmp -s "$SAVED" "$TEMPLATE"; then
        echo "Keeping the detach configuration saved by an earlier run ($SAVED)" >&2
        exit 0
      fi
      # Stage the copy in a fresh temporary file and move it into place, so an
      # existing saved copy survives a failed copy and a symlink planted at
      # the fixed saved-copy name is replaced, never written through.
      # A directory at the saved-copy name would swallow the copy (mv moves
      # into it), and restore would then find nothing.
      if [ -d "$SAVED" ] && [ ! -L "$SAVED" ]; then
        echo "ERROR: cannot save $CONFIG to $SAVED ($SAVED is a directory); nothing was changed" >&2
        exit 1
      fi
      tmp=$(mktemp "$(dirname "$SAVED")/.spex-detach-config.XXXXXX" 2>/dev/null) || tmp=""
      if [ -z "$tmp" ] || ! cp -p "$CONFIG" "$tmp" 2>/dev/null || ! mv -f "$tmp" "$SAVED" 2>/dev/null; then
        [ -z "$tmp" ] || rm -f "$tmp" 2>/dev/null
        echo "ERROR: cannot save $CONFIG to $SAVED; nothing was changed" >&2
        exit 1
      fi
    fi
    # Config missing: a saved copy from an interrupted run is kept as it is.
    exit 0
    ;;
  restore)
    if [ -L "$SAVED" ]; then
      echo "WARNING: $SAVED is a symlink; not restoring it (the template stays)" >&2
      rm -f "$SAVED" 2>/dev/null || true
      exit 0
    fi
    [ -f "$SAVED" ] || exit 0
    if ! mkdir -p "$(dirname "$CONFIG")" 2>/dev/null || ! mv -f "$SAVED" "$CONFIG" 2>/dev/null; then
      echo "ERROR: cannot restore $CONFIG from $SAVED; your configuration is kept in $SAVED" >&2
      exit 1
    fi
    exit 0
    ;;
  pending)
    [ -f "$SAVED" ] && [ ! -L "$SAVED" ] && [ -f "$(dirname "$CONFIG")/extension.yml" ]
    exit $?
    ;;
  *)
    usage
    ;;
esac
