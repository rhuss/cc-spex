#!/usr/bin/env bash
# Validate a staged Spex harness distribution without mutating it.

set -u

usage() {
  echo "Usage: $0 --harness <claude|codex|opencode> --input <absolute-dir>" >&2
  exit 2
}

HARNESS=""
INPUT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --harness)
      [ "$#" -ge 2 ] || usage
      HARNESS=$2
      shift 2
      ;;
    --input)
      [ "$#" -ge 2 ] || usage
      INPUT=$2
      shift 2
      ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done

case "$HARNESS" in
  claude|codex|opencode) ;;
  *) usage ;;
esac
case "$INPUT" in
  /*) ;;
  *) usage ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  echo '{"status":"invalid","diagnostics":[{"code":"missing_dependency","detail":"jq is required"}]}'
  exit 1
fi

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/spex-validate.XXXXXX") || exit 1
DIAGNOSTICS="$TMP_ROOT/diagnostics.ndjson"
INVENTORY="$TMP_ROOT/inventory.txt"
: > "$DIAGNOSTICS"
: > "$INVENTORY"
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

add_diagnostic() {
  code=$1
  path=$2
  detail=$3
  jq -cn --arg code "$code" --arg path "$path" --arg detail "$detail" \
    '{code: $code, path: $path, detail: $detail}' >> "$DIAGNOSTICS"
}

if [ ! -d "$INPUT" ]; then
  add_diagnostic "input_not_directory" "$INPUT" "Input must be an existing directory."
else
  INPUT=$(cd "$INPUT" 2>/dev/null && pwd -P) || {
    add_diagnostic "input_unreadable" "$INPUT" "Input directory cannot be resolved."
  }
fi

ADAPTER=""
if [ -d "$INPUT" ]; then
  (
    cd "$INPUT" || exit 1
    find . -type f -print | sed 's#^\./##' | LC_ALL=C sort
  ) > "$INVENTORY"

  if [ ! -s "$INVENTORY" ]; then
    add_diagnostic "empty_inventory" "." "The staged distribution contains no files."
  fi

  while IFS= read -r link; do
    add_diagnostic "symlink_not_allowed" "${link#"$INPUT"/}" "Materialized distributions must contain only owned files and directories."
  done < <(find "$INPUT" -type l -print)

  duplicate=$(awk '{ folded=tolower($0); if (seen[folded]++) { print $0; exit } }' "$INVENTORY")
  if [ -n "$duplicate" ]; then
    add_diagnostic "path_collision" "$duplicate" "Two output paths collide when compared case-insensitively."
  fi

  if [ -f "$INPUT/adapter.json" ]; then
    ADAPTER="$INPUT/adapter.json"
  elif [ -f "$INPUT/scripts/adapters/$HARNESS/adapter.json" ]; then
    ADAPTER="$INPUT/scripts/adapters/$HARNESS/adapter.json"
  else
    add_diagnostic "adapter_missing" "adapter.json" "No adapter declaration for the selected harness was staged."
  fi
fi

if [ -n "$ADAPTER" ]; then
  if ! jq -e '
    type == "object" and
    ((keys - ["capabilities", "command_map", "config_root", "hook_adapter", "id", "manifest_root", "permission_profiles", "progress_adapter", "schema_version", "subagent_adapter", "version"]) | length == 0) and
    .schema_version == "1.0.0" and
    (.id == "claude" or .id == "codex" or .id == "opencode") and
    (.version | type == "string" and length > 0) and
    (.manifest_root | type == "string" and length > 0) and
    (.config_root | type == "string" and length > 0) and
    ((has("command_map") | not) or (.command_map | type == "string")) and
    ((has("hook_adapter") | not) or .hook_adapter == null or (.hook_adapter | type == "string")) and
    ((has("progress_adapter") | not) or .progress_adapter == null or (.progress_adapter | type == "string")) and
    ((has("subagent_adapter") | not) or .subagent_adapter == null or (.subagent_adapter | type == "string")) and
    (.capabilities | type == "object") and
    ([.capabilities[] |
      (type == "object") and
      (.status == "native" or .status == "adapted" or .status == "degraded" or .status == "unavailable") and
      ((has("reason") | not) or (.reason | type == "string")) and
      ((has("fallback") | not) or (.fallback | type == "string")) and
      (if (.status == "degraded" or .status == "unavailable")
       then (.reason | type == "string") and (.fallback | type == "string")
       else true end)
    ] | all) and
    (.permission_profiles | type == "object") and
    (.permission_profiles | keys == ["autonomous", "safe", "yolo"]) and
    (.permission_profiles.safe | type == "object") and
    (.permission_profiles.autonomous | type == "object") and
    (.permission_profiles.yolo | type == "object")
  ' "$ADAPTER" >/dev/null 2>&1; then
    add_diagnostic "adapter_schema_invalid" "${ADAPTER#"$INPUT"/}" "Adapter does not conform to HarnessAdapter schema version 1.0.0."
  else
    adapter_id=$(jq -r '.id' "$ADAPTER")
    if [ "$adapter_id" != "$HARNESS" ]; then
      add_diagnostic "adapter_identity_mismatch" "${ADAPTER#"$INPUT"/}" "Adapter identity '$adapter_id' does not match requested harness '$HARNESS'."
    fi

    manifest_root=$(jq -r '.manifest_root' "$ADAPTER")
    config_root=$(jq -r '.config_root' "$ADAPTER")
    case "$manifest_root" in
      /*|..|../*|*/..|*/../*)
        add_diagnostic "unsafe_adapter_path" "${ADAPTER#"$INPUT"/}" "Manifest and config roots must be relative paths without parent traversal."
        ;;
    esac
    case "$config_root" in
      /*|..|../*|*/..|*/../*)
        add_diagnostic "unsafe_adapter_path" "${ADAPTER#"$INPUT"/}" "Manifest and config roots must be relative paths without parent traversal."
        ;;
    esac

    case "$HARNESS:$manifest_root:$config_root" in
      claude:.claude-plugin:.claude|codex:.codex-plugin:.codex|opencode:.opencode:.opencode) ;;
      *)
        add_diagnostic "distribution_identity_collision" "${ADAPTER#"$INPUT"/}" "Manifest or config root does not belong exclusively to harness '$HARNESS'."
        ;;
    esac
    if [ ! -e "$INPUT/$manifest_root" ]; then
      add_diagnostic "manifest_root_missing" "$manifest_root" "Declared manifest root is absent from the staged distribution."
    fi

    command_map=$(jq -r '.command_map // empty' "$ADAPTER")
    if [ -n "$command_map" ]; then
      adapter_dir=$(dirname "$ADAPTER")
      if [ ! -f "$adapter_dir/$command_map" ]; then
        add_diagnostic "command_map_missing" "${ADAPTER#"$INPUT"/}" "Declared command map '$command_map' is absent."
      elif ! jq -e --arg harness "$HARNESS" '.harness == $harness and (.tokens | type == "object")' "$adapter_dir/$command_map" >/dev/null 2>&1; then
        add_diagnostic "command_map_identity_mismatch" "${adapter_dir#"$INPUT"/}/$command_map" "Command map is invalid or belongs to another harness."
      fi
    fi
  fi
fi

case "$HARNESS" in
  claude)
    FOREIGN_PATH_RE='(^|/)(\.codex-plugin|\.codex|\.opencode)(/|$)'
    FOREIGN_CONTENT_RE='AskUserQuestion_PLACEHOLDER_NEVER_MATCH|request_user_input|\.codex-plugin|\.codex/config\.toml|OPENCODE_|\.opencode/'
    ;;
  codex)
    FOREIGN_PATH_RE='(^|/)(\.claude-plugin|\.claude|\.opencode)(/|$)'
    FOREIGN_CONTENT_RE='AskUserQuestion|(^|[^[:alnum:]_])Agent tool|CLAUDE_CODE_|\.claude-plugin|\.claude/settings|statusline-command|spex-ship-statusline|EnterWorktree|ExitWorktree|OPENCODE_|\.opencode/'
    ;;
  opencode)
    FOREIGN_PATH_RE='(^|/)(\.claude-plugin|\.claude|\.codex-plugin|\.codex)(/|$)'
    FOREIGN_CONTENT_RE='AskUserQuestion|request_user_input|update_plan|(^|[^[:alnum:]_])Agent tool|CLAUDE_CODE_|\.claude-plugin|\.claude/settings|\.codex-plugin|\.codex/config\.toml|statusline-command|spex-ship-statusline|EnterWorktree|ExitWorktree'
    ;;
esac

if [ -d "$INPUT" ]; then
  if [ -d "$INPUT/scripts/adapters" ]; then
    while IFS= read -r adapter_dir; do
      adapter_name=${adapter_dir##*/}
      if [ "$adapter_name" != "$HARNESS" ]; then
        add_diagnostic "foreign_adapter_collision" "scripts/adapters/$adapter_name" "A staged distribution may contain only its selected harness adapter."
      fi
    done < <(find "$INPUT/scripts/adapters" -mindepth 1 -maxdepth 1 -type d -print)
  fi

  while IFS= read -r json_file; do
    if ! jq empty "$json_file" >/dev/null 2>&1; then
      add_diagnostic "malformed_json" "${json_file#"$INPUT"/}" "Staged JSON is not syntactically valid."
    fi
  done < <(find "$INPUT" -type f -name '*.json' -print)

  while IFS= read -r path; do
    if printf '%s\n' "$path" | grep -Eq "$FOREIGN_PATH_RE"; then
      add_diagnostic "foreign_harness_path" "$path" "Output path belongs to a different harness."
    fi
  done < "$INVENTORY"

  while IFS=: read -r file line text; do
    [ -n "$file" ] || continue
    add_diagnostic "unresolved_harness_marker" "${file#"$INPUT"/}:$line" "$text"
  done < <(grep -RInIH -E '\{harness:[^}]+\}|<!--[[:space:]]*/?harness:[^>]+-->' "$INPUT" 2>/dev/null || true)

  while IFS=: read -r file line text; do
    [ -n "$file" ] || continue
    add_diagnostic "foreign_harness_reference" "${file#"$INPUT"/}:$line" "$text"
  done < <(grep -RInIH -E "$FOREIGN_CONTENT_RE" "$INPUT" 2>/dev/null || true)

  while IFS=: read -r file line text; do
    [ -n "$file" ] || continue
    add_diagnostic "absolute_development_path" "${file#"$INPUT"/}:$line" "$text"
  done < <(grep -RInIH -E '(^|[^[:alnum:]_])(/Users/[^/[:space:]]+|/home/[^/[:space:]]+|/private/tmp/|/var/folders/|/tmp/cc-spex[^/[:space:]]*)' "$INPUT" 2>/dev/null || true)
fi

file_count=$(wc -l < "$INVENTORY" 2>/dev/null | tr -d ' ')
file_count=${file_count:-0}
HASH_LINES="$TMP_ROOT/hash-lines.txt"
: > "$HASH_LINES"
if command -v shasum >/dev/null 2>&1; then
  while IFS= read -r file; do
    hash=$(shasum -a 256 "$INPUT/$file" | awk '{print $1}')
    printf '%s  %s\n' "$hash" "$file" >> "$HASH_LINES"
  done < "$INVENTORY"
  digest="sha256:$(shasum -a 256 "$HASH_LINES" | awk '{print $1}')"
elif command -v sha256sum >/dev/null 2>&1; then
  while IFS= read -r file; do
    hash=$(sha256sum "$INPUT/$file" | awk '{print $1}')
    printf '%s  %s\n' "$hash" "$file" >> "$HASH_LINES"
  done < "$INVENTORY"
  digest="sha256:$(sha256sum "$HASH_LINES" | awk '{print $1}')"
else
  digest="unavailable"
  add_diagnostic "missing_digest_tool" "." "Neither shasum nor sha256sum is available."
fi

diagnostic_count=$(wc -l < "$DIAGNOSTICS" | tr -d ' ')
if [ "$diagnostic_count" -eq 0 ]; then
  jq -cn --arg harness "$HARNESS" --arg input "$INPUT" --arg digest "$digest" --argjson file_count "$file_count" \
    '{status: "valid", harness: $harness, input: $input, inventory: {file_count: $file_count, digest: $digest}, diagnostics: []}'
  exit 0
fi

jq -cs --arg harness "$HARNESS" --arg input "$INPUT" --arg digest "$digest" --argjson file_count "$file_count" \
  '{status: "invalid", harness: $harness, input: $input, inventory: {file_count: $file_count, digest: $digest}, diagnostics: .}' \
  "$DIAGNOSTICS"
exit 1
