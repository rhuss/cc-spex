#!/usr/bin/env bash
# Materialize a harness-specific plugin from the canonical Spex source tree.

set -euo pipefail

usage() {
  echo "Usage: $0 --harness <claude|codex|opencode> --output <absolute-dir>" >&2
  exit 2
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

HARNESS=""
OUTPUT=""

while (($# > 0)); do
  case "$1" in
    --harness)
      (($# >= 2)) || usage
      HARNESS="$2"
      shift 2
      ;;
    --output)
      (($# >= 2)) || usage
      OUTPUT="$2"
      shift 2
      ;;
    --help|-h)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

case "$HARNESS" in
  claude|codex|opencode) ;;
  *) usage ;;
esac

[[ "$OUTPUT" == /* ]] || die "--output must be an absolute path"
[[ "$OUTPUT" != "/" ]] || die "refusing to materialize at filesystem root"

for dependency in jq find sort wc mktemp mv cp rm rmdir sed awk tr; do
  command -v "$dependency" >/dev/null 2>&1 || die "required command not found: $dependency"
done

if command -v sha256sum >/dev/null 2>&1; then
  hash_file() { sha256sum "$1" | awk '{print $1}'; }
elif command -v shasum >/dev/null 2>&1; then
  hash_file() { shasum -a 256 "$1" | awk '{print $1}'; }
else
  die "required SHA-256 command not found (sha256sum or shasum)"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
REPO_ROOT="$(cd "$SOURCE_ROOT/.." && pwd -P)"
ADAPTER_DIR="$SOURCE_ROOT/scripts/adapters/$HARNESS"
ADAPTER_FILE="$ADAPTER_DIR/adapter.json"
DESCRIPTOR_DIR="$REPO_ROOT/plugins/$HARNESS"

[[ -f "$ADAPTER_FILE" ]] || die "adapter declaration not found: $ADAPTER_FILE"
if [[ ! -d "$DESCRIPTOR_DIR" && "$HARNESS" != "opencode" ]]; then
  die "distribution descriptor not found: $DESCRIPTOR_DIR"
fi
jq -e . "$ADAPTER_FILE" >/dev/null 2>&1 || die "adapter declaration is not valid JSON"
[[ "$(jq -r '.id // empty' "$ADAPTER_FILE")" == "$HARNESS" ]] ||
  die "adapter id does not match requested harness"

COMMAND_MAP="$(jq -r '.command_map // empty' "$ADAPTER_FILE")"
[[ -n "$COMMAND_MAP" ]] || die "adapter does not declare command_map"
[[ "$COMMAND_MAP" != /* && "$COMMAND_MAP" != *".."* ]] ||
  die "adapter command_map must be a local relative path"
[[ -f "$ADAPTER_DIR/$COMMAND_MAP" ]] || die "adapter command map not found: $COMMAND_MAP"
jq -e . "$ADAPTER_DIR/$COMMAND_MAP" >/dev/null 2>&1 || die "adapter command map is not valid JSON"
[[ "$(jq -r '.harness // empty' "$ADAPTER_DIR/$COMMAND_MAP")" == "$HARNESS" ]] ||
  die "command map harness does not match requested harness"

OUTPUT_PARENT="$(dirname "$OUTPUT")"
OUTPUT_NAME="$(basename "$OUTPUT")"
[[ -d "$OUTPUT_PARENT" ]] || die "output parent does not exist: $OUTPUT_PARENT"
OUTPUT_PARENT="$(cd "$OUTPUT_PARENT" && pwd -P)"
OUTPUT="$OUTPUT_PARENT/$OUTPUT_NAME"

case "$OUTPUT/" in
  "$REPO_ROOT/"*)
    die "output must not replace or be inside the repository source tree"
    ;;
esac
case "$REPO_ROOT/" in
  "$OUTPUT/"*) die "output must not contain the repository source tree" ;;
esac
[[ ! -L "$OUTPUT" ]] || die "output must not be a symbolic link"
[[ ! -e "$OUTPUT" || -d "$OUTPUT" ]] || die "output exists and is not a directory"

STAGE="$(mktemp -d "$OUTPUT_PARENT/.${OUTPUT_NAME}.stage.XXXXXX")"
BACKUP=""
LIST_FILE="$(mktemp "$OUTPUT_PARENT/.${OUTPUT_NAME}.files.XXXXXX")"
INVENTORY_FILE="$(mktemp "$OUTPUT_PARENT/.${OUTPUT_NAME}.inventory.XXXXXX")"
MANIFEST_FILE="$(mktemp "$OUTPUT_PARENT/.${OUTPUT_NAME}.manifest.XXXXXX")"

cleanup() {
  [[ -z "$STAGE" || ! -e "$STAGE" ]] || rm -rf -- "$STAGE"
  [[ -z "$BACKUP" || ! -e "$BACKUP" ]] || rm -rf -- "$BACKUP"
  rm -f -- "$LIST_FILE" "$INVENTORY_FILE" "$MANIFEST_FILE"
}
trap cleanup EXIT

tree_digest() {
  local root="$1" list manifest relative digest
  list="$(mktemp "$OUTPUT_PARENT/.${OUTPUT_NAME}.source-list.XXXXXX")"
  manifest="$(mktemp "$OUTPUT_PARENT/.${OUTPUT_NAME}.source-manifest.XXXXXX")"
  (
    cd "$root"
    find . -type f -print | sed 's#^./##' | LC_ALL=C sort > "$list"
    while IFS= read -r relative; do
      digest="$(hash_file "$relative")"
      printf '%s  %s\n' "$digest" "$relative"
    done < "$list"
  ) > "$manifest"
  digest="$(hash_file "$manifest")"
  rm -f -- "$list" "$manifest"
  printf '%s\n' "$digest"
}

SOURCE_DIGEST_BEFORE="$(tree_digest "$SOURCE_ROOT")"

cp -R "$SOURCE_ROOT/." "$STAGE/"
if [[ -d "$DESCRIPTOR_DIR" ]]; then
  cp -R "$DESCRIPTOR_DIR/." "$STAGE/"
fi

# Remove manifest and project-configuration roots owned by other harnesses.
# These can exist in the canonical compatibility tree but are never shared
# distribution content.
for foreign_adapter in "$SOURCE_ROOT/scripts/adapters"/*/adapter.json; do
  [[ -f "$foreign_adapter" ]] || continue
  [[ "$(jq -r '.id // empty' "$foreign_adapter")" != "$HARNESS" ]] || continue
  for foreign_root in \
    "$(jq -r '.manifest_root // empty' "$foreign_adapter")" \
    "$(jq -r '.config_root // empty' "$foreign_adapter")"; do
    [[ -n "$foreign_root" ]] || continue
    [[ "$foreign_root" != /* && "$foreign_root" != "." && "$foreign_root" != *"/"* && "$foreign_root" != *".."* ]] ||
      die "foreign adapter declares an unsafe distribution root: $foreign_root"
    [[ ! -e "$STAGE/$foreign_root" ]] || rm -rf -- "$STAGE/$foreign_root"
  done
done

# A distribution owns one adapter. Retaining foreign adapters would make the
# package ambiguous and permits harness-specific hooks to leak into a release.
for candidate in "$STAGE/scripts/adapters"/*; do
  [[ -d "$candidate" ]] || continue
  [[ "$(basename "$candidate")" == "$HARNESS" ]] || rm -rf -- "$candidate"
done

"$STAGE/scripts/spex-adapt-commands.sh" \
  "$HARNESS" "$STAGE/extensions" "$STAGE/scripts/adapters"

SOURCE_DIGEST_AFTER="$(tree_digest "$SOURCE_ROOT")"
[[ "$SOURCE_DIGEST_BEFORE" == "$SOURCE_DIGEST_AFTER" ]] ||
  die "canonical Spex sources changed during materialization"

(
  cd "$STAGE"
  find . -type f -print | sed 's#^./##' | LC_ALL=C sort > "$LIST_FILE"
  while IFS= read -r relative; do
    [[ "$relative" != *$'\n'* ]] || die "distribution paths must not contain newlines"
    digest="$(hash_file "$relative")"
    size="$(wc -c < "$relative" | tr -d '[:space:]')"
    printf '%s  %s\n' "$digest" "$relative" >> "$MANIFEST_FILE"
    jq -cn \
      --arg path "$relative" \
      --arg sha256 "sha256:$digest" \
      --argjson size "$size" \
      '{path: $path, sha256: $sha256, size: $size}' >> "$INVENTORY_FILE"
  done < "$LIST_FILE"
)

DISTRIBUTION_DIGEST="$(hash_file "$MANIFEST_FILE")"
INVENTORY="$(jq -s . "$INVENTORY_FILE")"

if [[ -e "$OUTPUT" ]]; then
  BACKUP="$(mktemp -d "$OUTPUT_PARENT/.${OUTPUT_NAME}.backup.XXXXXX")"
  rmdir "$BACKUP"
  mv -- "$OUTPUT" "$BACKUP"
fi

if ! mv -- "$STAGE" "$OUTPUT"; then
  [[ -z "$BACKUP" || ! -e "$BACKUP" ]] || mv -- "$BACKUP" "$OUTPUT"
  die "failed to publish materialized distribution"
fi
STAGE=""
[[ -z "$BACKUP" || ! -e "$BACKUP" ]] || rm -rf -- "$BACKUP"
BACKUP=""

jq -cn \
  --arg schema_version "1.0.0" \
  --arg harness "$HARNESS" \
  --arg output "$OUTPUT" \
  --arg digest "sha256:$DISTRIBUTION_DIGEST" \
  --argjson inventory "$INVENTORY" \
  '{
    schema_version: $schema_version,
    harness: $harness,
    output: $output,
    digest: $digest,
    inventory: $inventory
  }'
