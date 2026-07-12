#!/bin/sh
# spex-adapt-commands.sh - Transform neutral command files to harness-specific versions
#
# Usage: spex-adapt-commands.sh [--dry-run] [--debug] <harness> <commands-dir> <adapters-dir>
#
# Arguments:
#   harness      - claude | codex | opencode | generic
#   commands-dir - path to installed .specify/extensions/ directory
#   adapters-dir - path to spex/scripts/adapters/ source directory
#
# Behavior:
#   Loads <adapters-dir>/<harness>/command-map.json and replaces {harness:key}
#   inline tokens and {harness:key}...{/harness:key} block markers with values
#   from the mapping table's "tokens" object. Uses temp directory for safe
#   transforms. In --dry-run mode, outputs unified diff without modifying files.
#   In --debug mode, outputs per-marker trace lines to stderr.

set -e

DRY_RUN=false
DEBUG=false

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --debug) DEBUG=true; shift ;;
    *) break ;;
  esac
done

HARNESS="${1:?Usage: spex-adapt-commands.sh [--dry-run] [--debug] <harness> <commands-dir> <adapters-dir>}"
COMMANDS_DIR="${2:?Missing commands-dir argument}"
ADAPTERS_DIR="${3:?Missing adapters-dir argument}"

MAPPING_TABLE="$ADAPTERS_DIR/$HARNESS/command-map.json"

if [ ! -f "$MAPPING_TABLE" ]; then
  exit 0
fi

if ! jq empty "$MAPPING_TABLE" 2>/dev/null; then
  echo "ERROR: Malformed JSON in $MAPPING_TABLE" >&2
  exit 1
fi

TMPDIR_WORK=$(mktemp -d "${TMPDIR:-/tmp}/spex-adapt-XXXXXX")
trap 'rm -rf "$TMPDIR_WORK"' EXIT

FALLBACK_NOTE=$(jq -r '.fallback_note // ""' "$MAPPING_TABLE")
HARNESS_ID=$(jq -r '.harness // ""' "$MAPPING_TABLE")

# Pre-extract token values into individual files for replacement
TOKENS_DIR="$TMPDIR_WORK/.tokens"
mkdir -p "$TOKENS_DIR"
jq -r '.tokens // {} | keys[]' "$MAPPING_TABLE" 2>/dev/null | while IFS= read -r tkey; do
  jq -r --arg key "$tkey" '.tokens[$key]' "$MAPPING_TABLE" > "$TOKENS_DIR/$tkey"
done

file_count=0
changed_count=0

for cmd_file in "$COMMANDS_DIR"/*/commands/*.md; do
  [ -f "$cmd_file" ] || continue
  file_count=$((file_count + 1))

  rel_path="${cmd_file#"$COMMANDS_DIR"/}"
  ext_name=$(echo "$rel_path" | cut -d'/' -f1)

  mkdir -p "$TMPDIR_WORK/$ext_name/commands"
  dest="$TMPDIR_WORK/$rel_path"

  cp "$cmd_file" "$dest"

  # Phase 1: Replace {harness:key}...{/harness:key} block markers
  # Block replacement must precede inline to avoid partial matches where
  # an inline token key matches inside a block's opening marker.
  block_keys=$(grep -oE '\{/harness:[a-z][a-z0-9-]*\}' "$dest" 2>/dev/null | sed 's/{\/harness://;s/}//' | sort -u || true)

  # Detect unmatched block openers: keys that appear as {harness:key} on
  # their own line (block-style) but have no corresponding {/harness:key}.
  opener_keys=$(grep -oE '\{harness:[a-z][a-z0-9-]*\}' "$dest" 2>/dev/null | sed 's/{harness://;s/}//' | sort -u || true)
  for okey in $opener_keys; do
    if ! echo "$block_keys" | grep -qxF "$okey"; then
      # Key has no closer - check if it appears on a line by itself (block intent)
      if grep -qE '^\s*\{harness:'"$okey"'\}\s*$' "$dest"; then
        echo "ERROR: Unclosed block marker {harness:$okey} in $rel_path (opening marker on its own line but no {/harness:$okey} closer)" >&2
        exit 1
      fi
    fi
  done

  for bkey in $block_keys; do
    # Check for orphan closer (no matching opener)
    if ! grep -q "{harness:$bkey}" "$dest"; then
      echo "WARNING: Orphan closing marker {/harness:$bkey} without matching opener in $rel_path" >&2
      continue
    fi

    # Determine replacement content
    repl_file="$TOKENS_DIR/$bkey"
    if [ -f "$repl_file" ]; then
      actual_repl="$repl_file"
      [ "$DEBUG" = true ] && echo "DEBUG: $rel_path: block {harness:$bkey} -> replaced" >&2
    elif [ -n "$FALLBACK_NOTE" ]; then
      actual_repl="$TMPDIR_WORK/.fallback-$bkey"
      printf '%s\n' "$FALLBACK_NOTE" | sed "s/{harness}/$HARNESS_ID/g;s/{fallback_text}/This feature requires harness-specific support./g" > "$actual_repl"
      [ "$DEBUG" = true ] && echo "DEBUG: $rel_path: block {harness:$bkey} -> fallback" >&2
    else
      [ "$DEBUG" = true ] && echo "DEBUG: $rel_path: block {harness:$bkey} -> skipped (no mapping, no fallback)" >&2
      continue
    fi

    awk -v key="$bkey" -v repl_file="$actual_repl" '
      BEGIN { in_block = 0 }
      {
        if (index($0, "{harness:" key "}") > 0 && !in_block) {
          in_block = 1
          while ((getline line < repl_file) > 0) { print line }
          close(repl_file)
          next
        }
        if (index($0, "{/harness:" key "}") > 0 && in_block) {
          in_block = 0
          next
        }
        if (!in_block) print
      }
      END {
        if (in_block) {
          print "ERROR: Unclosed block marker {harness:" key "}" > "/dev/stderr"
          exit 1
        }
      }
    ' "$dest" > "$dest.tmp" && mv "$dest.tmp" "$dest"
  done

  # Phase 2: Replace remaining {harness:key} inline tokens
  # Uses position-tracking replacement to avoid re-scanning replaced text
  awk -v tokens_dir="$TOKENS_DIR" -v fallback_note="$FALLBACK_NOTE" -v harness_id="$HARNESS_ID" -v do_debug="$DEBUG" -v rel_path="$rel_path" '
    {
      line = $0
      result = ""
      while (match(line, /\{harness:[a-z][a-z0-9-]*\}/)) {
        prefix = substr(line, 1, RSTART - 1)
        token = substr(line, RSTART, RLENGTH)
        tkey = substr(token, 10, length(token) - 10)
        rest_line = substr(line, RSTART + RLENGTH)

        repl_file = tokens_dir "/" tkey
        repl = ""
        rc = (getline repl < repl_file)
        if (rc > 0) {
          while ((getline tmpline < repl_file) > 0) {
            repl = repl "\n" tmpline
          }
          close(repl_file)
          if (do_debug == "true") {
            print "DEBUG: " rel_path ": inline {harness:" tkey "} -> replaced" > "/dev/stderr"
          }
        } else {
          if (rc < 0) close(repl_file)
          # Apply fallback template
          repl = fallback_note
          gsub(/\{harness\}/, harness_id, repl)
          gsub(/\{fallback_text\}/, "This feature requires harness-specific support.", repl)
          if (do_debug == "true") {
            print "DEBUG: " rel_path ": inline {harness:" tkey "} -> fallback" > "/dev/stderr"
          }
        }

        result = result prefix repl
        line = rest_line
      }
      print result line
    }
  ' "$dest" > "$dest.tmp" && mv "$dest.tmp" "$dest"

  if ! diff -q "$cmd_file" "$dest" >/dev/null 2>&1; then
    changed_count=$((changed_count + 1))
  fi
done

# Phase 3: Post-adaptation validation - scan for leftover markers
for cmd_file in "$COMMANDS_DIR"/*/commands/*.md; do
  [ -f "$cmd_file" ] || continue
  rel_path="${cmd_file#"$COMMANDS_DIR"/}"
  dest="$TMPDIR_WORK/$rel_path"
  [ -f "$dest" ] || continue

  leftovers=$(grep -onE '\{/?harness:[a-z][a-z0-9-]*\}' "$dest" 2>/dev/null || true)
  if [ -n "$leftovers" ]; then
    echo "$leftovers" | while IFS= read -r match; do
      echo "WARNING: Leftover marker in $rel_path:$match" >&2
    done
  fi
done

if [ "$DRY_RUN" = true ]; then
  for cmd_file in "$COMMANDS_DIR"/*/commands/*.md; do
    [ -f "$cmd_file" ] || continue
    rel_path="${cmd_file#"$COMMANDS_DIR"/}"
    dest="$TMPDIR_WORK/$rel_path"
    [ -f "$dest" ] || continue
    if ! diff -q "$cmd_file" "$dest" >/dev/null 2>&1; then
      diff -u "$cmd_file" "$dest" 2>/dev/null || true
    fi
  done
  echo "Dry run: $changed_count of $file_count files would be modified" >&2
  exit 0
fi

# Copy transformed files into place (re-running setup restores neutral state on failure)
for cmd_file in "$COMMANDS_DIR"/*/commands/*.md; do
  [ -f "$cmd_file" ] || continue
  rel_path="${cmd_file#"$COMMANDS_DIR"/}"
  dest="$TMPDIR_WORK/$rel_path"
  [ -f "$dest" ] || continue
  cp "$dest" "$cmd_file"
done

echo "Adapted $changed_count of $file_count command files for $HARNESS" >&2
