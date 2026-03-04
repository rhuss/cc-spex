#!/bin/bash
# sdd-traits.sh - Manage SDD trait configuration and overlay application
#
# Combines config management and overlay application into a single script.
# All trait operations go through this script for reproducibility.
#
# Usage:
#   sdd-traits.sh list                      # Show current trait status
#   sdd-traits.sh enable <trait>            # Enable a trait and apply overlays
#   sdd-traits.sh disable <trait>           # Disable a trait (config only, no reinit)
#   sdd-traits.sh init [--enable t1,t2]     # Create config (all disabled, or enable specified)
#   sdd-traits.sh apply                     # Apply overlays for all enabled traits
#   sdd-traits.sh permissions [level]       # Show or set auto-approval level
#
# Permission levels:
#   none       - No auto-approvals (confirm every command)
#   standard   - Auto-approve SDD plugin scripts
#   yolo       - Auto-approve SDD scripts + specify CLI
#
# Must be run from the project root (where .specify/ and .claude/ exist).
#
# Exit codes:
#   0 - Success
#   1 - Error
#   2 - Invalid arguments

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TRAITS_CONFIG=".specify/sdd-traits.json"
VALID_TRAITS="superpowers beads teams-vanilla teams-spec"

# --- Helpers ---

now_iso() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

is_valid_trait() {
  local trait="$1"
  for t in $VALID_TRAITS; do
    [ "$t" = "$trait" ] && return 0
  done
  return 1
}

get_trait_deps() {
  # Returns space-separated list of required traits (bash 3.2 compatible)
  case "$1" in
    teams-spec) echo "teams-vanilla superpowers beads" ;;
    *) echo "" ;;
  esac
}

check_deps_for_enable() {
  local trait="$1"
  local deps
  deps=$(get_trait_deps "$trait")
  [ -z "$deps" ] && return 0

  local missing=""
  for dep in $deps; do
    local val
    val=$(jq -r ".traits[\"$dep\"] // false" "$TRAITS_CONFIG")
    if [ "$val" != "true" ]; then
      missing="$missing $dep"
    fi
  done

  if [ -n "$missing" ]; then
    echo "ERROR: Trait '$trait' requires these traits to be enabled first:$missing" >&2
    return 1
  fi
  return 0
}

check_dependents_for_disable() {
  local trait="$1"
  local dependents=""

  for t in $VALID_TRAITS; do
    local val
    val=$(jq -r ".traits[\"$t\"] // false" "$TRAITS_CONFIG")
    [ "$val" != "true" ] && continue

    local deps
    deps=$(get_trait_deps "$t")
    for dep in $deps; do
      if [ "$dep" = "$trait" ]; then
        dependents="$dependents $t"
      fi
    done
  done

  if [ -n "$dependents" ]; then
    echo "ERROR: Cannot disable '$trait'. These enabled traits depend on it:$dependents" >&2
    return 1
  fi
  return 0
}

ensure_config() {
  # Create config with all traits disabled if it doesn't exist
  if [ ! -f "$TRAITS_CONFIG" ]; then
    mkdir -p "$(dirname "$TRAITS_CONFIG")"
    cat > "$TRAITS_CONFIG" <<EOF
{
  "version": 1,
  "traits": {
    "superpowers": false,
    "beads": false,
    "teams-vanilla": false,
    "teams-spec": false
  },
  "applied_at": "$(now_iso)"
}
EOF
    echo "Created $TRAITS_CONFIG with all traits disabled."
  fi

  # Validate JSON
  if ! jq empty "$TRAITS_CONFIG" 2>/dev/null; then
    echo "ERROR: Invalid JSON in $TRAITS_CONFIG" >&2
    exit 1
  fi
}

ensure_agent_teams_env() {
  # Set or remove CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS in settings.local.json
  # based on whether any teams trait is currently enabled.
  ensure_settings

  local teams_vanilla teams_spec
  teams_vanilla=$(jq -r '.traits["teams-vanilla"] // false' "$TRAITS_CONFIG" 2>/dev/null)
  teams_spec=$(jq -r '.traits["teams-spec"] // false' "$TRAITS_CONFIG" 2>/dev/null)

  local tmp
  tmp=$(mktemp)
  if [ "$teams_vanilla" = "true" ] || [ "$teams_spec" = "true" ]; then
    jq '.env //= {} | .env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1"' "$SETTINGS_FILE" > "$tmp"
    mv "$tmp" "$SETTINGS_FILE"
    echo "Set CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 in $SETTINGS_FILE"
  else
    jq 'if .env then .env |= del(.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS) | if .env == {} then del(.env) else . end else . end' "$SETTINGS_FILE" > "$tmp"
    mv "$tmp" "$SETTINGS_FILE"
  fi
}

ensure_beads_db() {
  # Initialize bd database if bd is installed but no database exists
  if ! command -v bd &>/dev/null; then
    echo "NOTE: bd CLI not found. Install beads to use the beads trait:"
    echo "  See https://github.com/beads-project/beads"
    echo "  Beads trait is enabled but bd commands will be skipped until installed."
    return
  fi

  if bd list --json &>/dev/null; then
    return  # database already exists
  fi

  echo "Initializing beads database..."
  bd init
  # Refresh SQLite cache from JSONL to prevent stale-db errors
  bd sync --import-only 2>/dev/null || true
  echo "Beads database initialized."
}

# --- Subcommands ---

do_list() {
  ensure_config
  echo "SDD Traits:"
  for trait in $VALID_TRAITS; do
    val=$(jq -r ".traits[\"$trait\"] // false" "$TRAITS_CONFIG")
    if [ "$val" = "true" ]; then
      echo "  $trait: enabled"
    else
      echo "  $trait: disabled"
    fi
  done
  applied_at=$(jq -r '.applied_at // "unknown"' "$TRAITS_CONFIG")
  echo "  applied_at: $applied_at"
}

do_enable() {
  local trait="$1"

  if ! is_valid_trait "$trait"; then
    echo "ERROR: Invalid trait '$trait'. Valid traits: $VALID_TRAITS" >&2
    exit 2
  fi

  ensure_config

  # Check dependencies before enabling
  if ! check_deps_for_enable "$trait"; then
    exit 1
  fi

  # Check if already enabled
  current=$(jq -r ".traits[\"$trait\"] // false" "$TRAITS_CONFIG")
  if [ "$current" = "true" ]; then
    echo "Trait '$trait' is already enabled."
    do_apply
    return
  fi

  # Update config
  local tmp
  tmp=$(mktemp)
  jq --arg t "$trait" --arg ts "$(now_iso)" \
    '.traits[$t] = true | .applied_at = $ts' "$TRAITS_CONFIG" > "$tmp"
  mv "$tmp" "$TRAITS_CONFIG"
  echo "Trait '$trait' enabled."

  # Trait-specific post-enable setup
  if [ "$trait" = "beads" ]; then
    ensure_beads_db
  fi

  # Set agent teams env var if a teams trait was enabled
  if [ "$trait" = "teams-vanilla" ] || [ "$trait" = "teams-spec" ]; then
    ensure_agent_teams_env
  fi

  # Apply overlays
  do_apply
}

do_disable() {
  local trait="$1"

  if ! is_valid_trait "$trait"; then
    echo "ERROR: Invalid trait '$trait'. Valid traits: $VALID_TRAITS" >&2
    exit 2
  fi

  ensure_config

  # Check that no enabled trait depends on this one
  if ! check_dependents_for_disable "$trait"; then
    exit 1
  fi

  # Check if already disabled
  current=$(jq -r ".traits[\"$trait\"] // false" "$TRAITS_CONFIG")
  if [ "$current" = "false" ]; then
    echo "Trait '$trait' is already disabled."
    return
  fi

  # Update config only (caller handles spec-kit reinit and reapply)
  local tmp
  tmp=$(mktemp)
  jq --arg t "$trait" --arg ts "$(now_iso)" \
    '.traits[$t] = false | .applied_at = $ts' "$TRAITS_CONFIG" > "$tmp"
  mv "$tmp" "$TRAITS_CONFIG"
  echo "Trait '$trait' disabled in config."

  # Remove agent teams env var if no teams traits remain enabled
  if [ "$trait" = "teams-vanilla" ] || [ "$trait" = "teams-spec" ]; then
    ensure_agent_teams_env
  fi

  echo "NOTE: Run 'specify init --here --ai claude --force' then '$0 apply' to regenerate files."
}

do_init() {
  local enable_list=""

  # Parse --enable flag
  while [ $# -gt 0 ]; do
    case "$1" in
      --enable)
        shift
        enable_list="${1:-}"
        if [ -z "$enable_list" ]; then
          echo "ERROR: --enable requires a comma-separated list of traits" >&2
          exit 2
        fi
        ;;
      *)
        echo "ERROR: Unknown argument '$1'" >&2
        echo "Usage: sdd-traits.sh init [--enable trait1,trait2]" >&2
        exit 2
        ;;
    esac
    shift
  done

  # Build the traits JSON object
  local superpowers_val="false" beads_val="false"
  local teams_vanilla_val="false" teams_spec_val="false"

  if [ -n "$enable_list" ]; then
    IFS=',' read -ra traits_arr <<< "$enable_list"
    for t in "${traits_arr[@]}"; do
      t=$(echo "$t" | tr -d ' ')
      if ! is_valid_trait "$t"; then
        echo "ERROR: Invalid trait '$t'. Valid traits: $VALID_TRAITS" >&2
        exit 2
      fi
      case "$t" in
        superpowers) superpowers_val="true" ;;
        beads) beads_val="true" ;;
        teams-vanilla) teams_vanilla_val="true" ;;
        teams-spec) teams_spec_val="true" ;;
      esac
    done

    # Auto-resolve: teams-spec requires teams-vanilla
    if [ "$teams_spec_val" = "true" ] && [ "$teams_vanilla_val" = "false" ]; then
      teams_vanilla_val="true"
      echo "NOTE: Auto-enabling teams-vanilla (required by teams-spec)."
    fi

    # Check non-auto-resolvable deps for teams-spec
    if [ "$teams_spec_val" = "true" ]; then
      local missing_deps=""
      [ "$superpowers_val" = "false" ] && missing_deps="$missing_deps superpowers"
      [ "$beads_val" = "false" ] && missing_deps="$missing_deps beads"
      if [ -n "$missing_deps" ]; then
        echo "ERROR: teams-spec requires these traits to also be enabled:$missing_deps" >&2
        exit 2
      fi
    fi
  fi

  mkdir -p "$(dirname "$TRAITS_CONFIG")"
  cat > "$TRAITS_CONFIG" <<EOF
{
  "version": 1,
  "traits": {
    "superpowers": $superpowers_val,
    "beads": $beads_val,
    "teams-vanilla": $teams_vanilla_val,
    "teams-spec": $teams_spec_val
  },
  "applied_at": "$(now_iso)"
}
EOF

  echo "Traits config created."

  # Initialize beads database if beads trait was enabled
  if [ "$beads_val" = "true" ]; then
    ensure_beads_db
  fi

  # Set agent teams env var if any teams trait was enabled
  if [ "$teams_vanilla_val" = "true" ] || [ "$teams_spec_val" = "true" ]; then
    ensure_agent_teams_env
  fi

  do_list
  do_apply
}

do_apply() {
  ensure_config

  # Ensure agent teams env var matches current trait state on every apply
  ensure_agent_teams_env

  # Collect enabled traits
  enabled_traits=$(jq -r '.traits | to_entries[] | select(.value == true) | .key' "$TRAITS_CONFIG")

  if [ -z "$enabled_traits" ]; then
    echo "No traits enabled. Nothing to apply."
    return
  fi

  # Collect overlays and validate targets
  declare -a overlay_files=()
  declare -a target_files=()
  declare -a trait_names=()
  local errors=0

  for trait in $enabled_traits; do
    overlay_dir="$PLUGIN_ROOT/overlays/$trait"

    if [ ! -d "$overlay_dir" ]; then
      echo "WARNING: No overlay directory for trait '$trait' at $overlay_dir" >&2
      continue
    fi

    while IFS= read -r -d '' overlay_file; do
      rel_path="${overlay_file#"$overlay_dir"/}"
      overlay_subdir=$(dirname "$rel_path")
      overlay_basename=$(basename "$rel_path")
      target_basename="${overlay_basename%.append.md}.md"

      case "$overlay_subdir" in
        commands)
          target_file=".claude/commands/$target_basename"
          ;;
        templates)
          target_file=".specify/templates/$target_basename"
          ;;
        *)
          echo "WARNING: Unknown overlay subdirectory '$overlay_subdir', skipping" >&2
          continue
          ;;
      esac

      if [ ! -f "$target_file" ]; then
        echo "ERROR: Target file not found: $target_file (from $overlay_file)" >&2
        errors=$((errors + 1))
        continue
      fi

      overlay_files+=("$overlay_file")
      target_files+=("$target_file")
      trait_names+=("$trait")
    done < <(find "$overlay_dir" -name "*.append.md" -print0 2>/dev/null)
  done

  if [ "$errors" -gt 0 ]; then
    echo "ERROR: $errors target file(s) missing. No overlays applied." >&2
    return 1
  fi

  if [ ${#overlay_files[@]} -eq 0 ]; then
    echo "No overlay files found for enabled traits."
    return
  fi

  # Apply overlays (idempotent via sentinel markers)
  local applied=0 skipped=0

  for i in "${!overlay_files[@]}"; do
    local sentinel="<!-- SDD-TRAIT:${trait_names[$i]} -->"

    if grep -q "$sentinel" "${target_files[$i]}" 2>/dev/null; then
      skipped=$((skipped + 1))
      continue
    fi

    printf '\n' >> "${target_files[$i]}"
    cat "${overlay_files[$i]}" >> "${target_files[$i]}"
    applied=$((applied + 1))
  done

  echo "Traits applied: $applied overlay(s) appended, $skipped already present."
}

# --- Permissions ---

SETTINGS_FILE=".claude/settings.local.json"

# SDD-specific permission patterns
SDD_PATTERN_INIT='Bash(*/scripts/sdd-init.sh*)'
SDD_PATTERN_TRAITS='Bash(*/scripts/sdd-traits.sh*)'
SDD_PATTERN_BEADS_SYNC='Bash(*/scripts/sdd-beads-sync.py*)'
SDD_PATTERN_BEADS_BD='Bash(bd *)'
SDD_PATTERN_SPECIFY='Bash(specify *)'
# Broad tool patterns for YOLO level
SDD_YOLO_EXTRAS=("Bash" "Read" "Edit" "Write" "mcp__*")

ensure_settings() {
  if [ ! -f "$SETTINGS_FILE" ]; then
    mkdir -p .claude
    echo '{}' > "$SETTINGS_FILE"
  fi
  if ! jq empty "$SETTINGS_FILE" 2>/dev/null; then
    echo "ERROR: Invalid JSON in $SETTINGS_FILE" >&2
    exit 1
  fi
}

# Remove all SDD-managed patterns from the allow list
remove_sdd_patterns() {
  local tmp
  tmp=$(mktemp)
  jq '
    if .permissions.allow then
      .permissions.allow = [
        .permissions.allow[] |
        select(
          # SDD script patterns
          (test("sdd-init\\.sh|sdd-traits\\.sh|sdd-beads-sync\\.py|^Bash\\(specify |^Bash\\(bd ") | not)
          and
          # YOLO broad patterns (exact matches only)
          (. != "Bash" and . != "Read" and . != "Edit" and . != "Write" and . != "mcp__*")
        )
      ]
    else . end
  ' "$SETTINGS_FILE" > "$tmp"
  mv "$tmp" "$SETTINGS_FILE"
}

# Add patterns to the allow list
add_sdd_patterns() {
  local tmp
  tmp=$(mktemp)
  # Build the pattern array from arguments
  local patterns="[]"
  for p in "$@"; do
    patterns=$(echo "$patterns" | jq --arg p "$p" '. + [$p]')
  done
  jq --argjson new "$patterns" '
    .permissions //= {} |
    .permissions.allow //= [] |
    .permissions.allow += $new
  ' "$SETTINGS_FILE" > "$tmp"
  mv "$tmp" "$SETTINGS_FILE"
}

detect_permission_level() {
  ensure_settings
  local allow
  allow=$(jq -r '.permissions.allow // [] | .[]' "$SETTINGS_FILE")

  local has_init=false has_traits=false has_beads_sync=false has_bd=false has_specify=false has_bash=false
  echo "$allow" | grep -q "sdd-init" && has_init=true
  echo "$allow" | grep -q "sdd-traits" && has_traits=true
  echo "$allow" | grep -q "sdd-beads-sync\." && has_beads_sync=true
  echo "$allow" | grep -q "Bash(bd " && has_bd=true
  echo "$allow" | grep -q "specify " && has_specify=true
  echo "$allow" | grep -qx "Bash" && has_bash=true

  if [ "$has_init" = true ] && [ "$has_traits" = true ] && [ "$has_beads_sync" = true ] && [ "$has_bd" = true ] && [ "$has_specify" = true ] && [ "$has_bash" = true ]; then
    echo "yolo"
  elif [ "$has_init" = true ] && [ "$has_traits" = true ] && [ "$has_beads_sync" = true ] && [ "$has_bd" = true ]; then
    echo "standard"
  else
    echo "none"
  fi
}

do_permissions() {
  local level="${1:-show}"

  case "$level" in
    show)
      ensure_settings
      local current
      current=$(detect_permission_level)
      echo "SDD auto-approval: $current"
      echo ""
      echo "Levels:"
      echo "  none       No auto-approvals (confirm every command)"
      echo "  standard   Auto-approve SDD plugin scripts and beads CLI (bd)"
      echo "  yolo       Auto-approve all tools (Bash, Read, Edit, Write, MCP, specify)"
      ;;
    none)
      ensure_settings
      local before
      before=$(detect_permission_level)
      remove_sdd_patterns
      echo "Auto-approval set to: none"
      echo "All SDD commands will require confirmation."
      [ "$before" != "none" ] && echo "CHANGED" || true
      ;;
    standard)
      ensure_settings
      local before
      before=$(detect_permission_level)
      remove_sdd_patterns
      add_sdd_patterns "$SDD_PATTERN_INIT" "$SDD_PATTERN_TRAITS" "$SDD_PATTERN_BEADS_SYNC" "$SDD_PATTERN_BEADS_BD"
      echo "Auto-approval set to: standard"
      echo "Auto-approved:"
      echo "  sdd-init.sh        Project initialization"
      echo "  sdd-traits.sh      Trait configuration and overlay management"
      echo "  sdd-beads-sync.py  Bidirectional sync between tasks.md and bd issues"
      echo "  bd *               Beads CLI (create, close, sync, ready, list, dep)"
      [ "$before" != "standard" ] && echo "CHANGED" || true
      ;;
    yolo)
      ensure_settings
      local before
      before=$(detect_permission_level)
      remove_sdd_patterns
      add_sdd_patterns "$SDD_PATTERN_INIT" "$SDD_PATTERN_TRAITS" "$SDD_PATTERN_BEADS_SYNC" "$SDD_PATTERN_BEADS_BD" "$SDD_PATTERN_SPECIFY" "${SDD_YOLO_EXTRAS[@]}"
      echo "Auto-approval set to: yolo"
      echo "All tools auto-approved: Bash, Read, Edit, Write, MCP, specify CLI, SDD scripts, beads CLI."
      [ "$before" != "yolo" ] && echo "CHANGED" || true
      ;;
    *)
      echo "ERROR: Invalid permission level '$level'. Use: none, standard, yolo" >&2
      exit 2
      ;;
  esac
}

show_usage() {
  echo "Usage: sdd-traits.sh <command> [options]"
  echo ""
  echo "Commands:"
  echo "  list                      Show current trait status"
  echo "  enable <trait>            Enable a trait and apply overlays"
  echo "  disable <trait>           Disable a trait (config update only)"
  echo "  init [--enable t1,t2]     Create config (default: all disabled)"
  echo "  apply                     Apply overlays for all enabled traits"
  echo "  permissions [level]       Show or set auto-approval (none|standard|yolo)"
  echo ""
  echo "Valid traits: $VALID_TRAITS"
}

# --- Main ---

case "${1:-}" in
  list|"")
    do_list
    ;;
  enable)
    if [ -z "${2:-}" ]; then
      echo "ERROR: 'enable' requires a trait name" >&2
      show_usage >&2
      exit 2
    fi
    do_enable "$2"
    ;;
  disable)
    if [ -z "${2:-}" ]; then
      echo "ERROR: 'disable' requires a trait name" >&2
      show_usage >&2
      exit 2
    fi
    do_disable "$2"
    ;;
  init)
    shift
    do_init "$@"
    ;;
  apply)
    do_apply
    ;;
  permissions)
    do_permissions "${2:-show}"
    ;;
  -h|--help|help)
    show_usage
    ;;
  *)
    echo "ERROR: Unknown command '$1'" >&2
    show_usage >&2
    exit 2
    ;;
esac
