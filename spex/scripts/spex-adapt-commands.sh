#!/bin/sh
# spex-adapt-commands.sh - Transform neutral command files to harness-specific versions
#
# Usage: spex-adapt-commands.sh [--dry-run] <harness> <commands-dir> <adapters-dir>
#
# Arguments:
#   harness      - claude | codex | opencode | generic
#   commands-dir - path to installed .specify/extensions/ directory
#   adapters-dir - path to spex/scripts/adapters/ source directory
#
# Behavior:
#   Loads <adapters-dir>/<harness>/command-map.json and applies inline
#   substitutions + capability marker section replacements to all .md files
#   in <commands-dir>/*/commands/. Uses temp directory for safe transforms.
#   In --dry-run mode, outputs unified diff without modifying files.

set -e

DRY_RUN=false
if [ "$1" = "--dry-run" ]; then
  DRY_RUN=true
  shift
fi

HARNESS="${1:?Usage: spex-adapt-commands.sh [--dry-run] <harness> <commands-dir> <adapters-dir>}"
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

# Pre-extract inline substitutions into a single TSV file for batched processing
INLINE_TSV="$TMPDIR_WORK/.inline.tsv"
jq -r '(.inline // [])[] | "\(.neutral)\t\(.adapted)"' "$MAPPING_TABLE" > "$INLINE_TSV" 2>/dev/null

# Pre-extract section replacements
SECTIONS_DIR="$TMPDIR_WORK/.sections"
mkdir -p "$SECTIONS_DIR"
jq -r '.sections | keys[]' "$MAPPING_TABLE" 2>/dev/null | while read -r sname; do
  jq -r --arg name "$sname" '.sections[$name]' "$MAPPING_TABLE" > "$SECTIONS_DIR/$sname"
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

  # Phase 1: Apply all inline substitutions in a single awk pass
  # Position-tracking replacement avoids infinite loops when adapted text
  # contains the neutral search string as a substring.
  awk -v tsv_file="$INLINE_TSV" '
    BEGIN {
      n = 0
      while ((getline line < tsv_file) > 0) {
        split(line, parts, "\t")
        if (parts[1] != "" && parts[2] != "") {
          n++
          old[n] = parts[1]
          new_val[n] = parts[2]
        }
      }
      close(tsv_file)
    }
    {
      for (i = 1; i <= n; i++) {
        result = ""
        rest = $0
        while ((idx = index(rest, old[i])) > 0) {
          result = result substr(rest, 1, idx - 1) new_val[i]
          rest = substr(rest, idx + length(old[i]))
        }
        $0 = result rest
      }
      print
    }
  ' "$dest" > "$dest.tmp" && mv "$dest.tmp" "$dest"

  # Phase 2: Replace capability marker sections
  marker_names=$(grep -oE '<!-- harness:[a-z][a-z0-9-]* -->' "$dest" 2>/dev/null | sed 's/<!-- harness://;s/ -->//' || true)

  if [ -n "$marker_names" ]; then
    for mname in $marker_names; do
      repl_file="$SECTIONS_DIR/$mname"
      if [ -f "$repl_file" ] && [ -s "$repl_file" ]; then
        actual_repl="$repl_file"
      elif [ -n "$FALLBACK_NOTE" ]; then
        actual_repl="$TMPDIR_WORK/.fallback-$mname"
        printf '%s\n' "$FALLBACK_NOTE" | sed "s/{harness}/$HARNESS_ID/g;s/{fallback_text}/This feature requires harness-specific support./g" > "$actual_repl"
      else
        continue
      fi
      awk -v mname="$mname" -v repl_file="$actual_repl" '
        BEGIN { in_block = 0 }
        $0 ~ "<!-- harness:" mname " -->" {
          in_block = 1
          while ((getline line < repl_file) > 0) { print line }
          close(repl_file)
          next
        }
        $0 ~ "<!-- /harness:" mname " -->" {
          in_block = 0
          next
        }
        { if (!in_block) print }
        END { if (in_block) { print "ERROR: unclosed capability marker: " mname > "/dev/stderr"; exit 1 } }
      ' "$dest" > "$dest.tmp" && mv "$dest.tmp" "$dest"
    done
  fi

  if ! diff -q "$cmd_file" "$dest" >/dev/null 2>&1; then
    changed_count=$((changed_count + 1))
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
