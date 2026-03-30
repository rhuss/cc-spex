#!/bin/bash
# spex-traits.sh - Manage spex trait configuration and overlay application
#
# Combines config management and overlay application into a single script.
# All trait operations go through this script for reproducibility.
#
# Usage:
#   spex-traits.sh list                      # Show current trait status
#   spex-traits.sh enable <trait>            # Enable a trait and apply overlays
#   spex-traits.sh disable <trait>           # Disable a trait (config only, no reinit)
#   spex-traits.sh init [--enable t1,t2]     # Create config (all disabled, or enable specified)
#   spex-traits.sh apply                     # Apply overlays for all enabled traits
#   spex-traits.sh permissions [level]       # Show or set auto-approval level
#
# Permission levels:
#   none       - No auto-approvals (confirm every command)
#   standard   - Auto-approve spex plugin scripts
#   yolo       - Auto-approve spex scripts + specify CLI
#
# Must be run from the project root (where .specify/ and .claude/ exist).
#
# Exit codes:
#   0 - Success
#   1 - Error
#   2 - Invalid arguments

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TRAITS_CONFIG=".specify/spex-traits.json"
# Backwards compatibility: fall back to old config if new one doesn't exist
if [ ! -f "$TRAITS_CONFIG" ] && [ -f ".specify/sdd-traits.json" ]; then
  TRAITS_CONFIG=".specify/sdd-traits.json"
fi
VALID_TRAITS="superpowers teams worktrees deep-review"

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

resolve_trait_name() {
  case "$1" in
    teams-vanilla|teams-spec) echo "teams" ;;
    *) echo "$1" ;;
  esac
}

get_trait_deps() {
  # Returns space-separated list of required traits (bash 3.2 compatible)
  case "$1" in
    teams) echo "superpowers" ;;
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
    "deep-review": false,
    "teams": false,
    "worktrees": false
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

  # Migrate removed beads trait: delete key from config
  local bv
  bv=$(jq -r '.traits["beads"] // "absent"' "$TRAITS_CONFIG" 2>/dev/null)
  if [ "$bv" != "absent" ]; then
    local tmp
    tmp=$(mktemp)
    jq 'del(.traits["beads"])' "$TRAITS_CONFIG" > "$tmp"
    mv "$tmp" "$TRAITS_CONFIG"
    if [ "$bv" = "true" ]; then
      echo "BEADS_MIGRATION_NEEDED"
    fi
  fi

  # Migrate old teams trait names to consolidated "teams" and remove deprecated keys
  local tv ts
  tv=$(jq -r '.traits["teams-vanilla"] // "absent"' "$TRAITS_CONFIG" 2>/dev/null)
  ts=$(jq -r '.traits["teams-spec"] // "absent"' "$TRAITS_CONFIG" 2>/dev/null)
  if [ "$tv" != "absent" ] || [ "$ts" != "absent" ]; then
    local tmp
    tmp=$(mktemp)
    if [ "$tv" = "true" ] || [ "$ts" = "true" ]; then
      jq '.traits["teams"] = true | del(.traits["teams-vanilla"], .traits["teams-spec"])' "$TRAITS_CONFIG" > "$tmp"
      echo "NOTICE: Migrated teams-vanilla/teams-spec to consolidated 'teams' trait."
    else
      jq 'del(.traits["teams-vanilla"], .traits["teams-spec"])' "$TRAITS_CONFIG" > "$tmp"
    fi
    mv "$tmp" "$TRAITS_CONFIG"
  fi
}

ensure_agent_teams_env() {
  # Set or remove CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS in settings.local.json
  # based on whether the teams trait is currently enabled.
  ensure_settings

  local teams_enabled
  teams_enabled=$(jq -r '.traits["teams"] // false' "$TRAITS_CONFIG" 2>/dev/null)

  local tmp
  tmp=$(mktemp)
  if [ "$teams_enabled" = "true" ]; then
    jq '.env //= {} | .env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1"' "$SETTINGS_FILE" > "$tmp"
    mv "$tmp" "$SETTINGS_FILE"
    echo "Set CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 in $SETTINGS_FILE"
  else
    jq 'if .env then .env |= del(.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS) | if .env == {} then del(.env) else . end else . end' "$SETTINGS_FILE" > "$tmp"
    mv "$tmp" "$SETTINGS_FILE"
  fi
}

# --- Subcommands ---

do_list() {
  ensure_config
  echo "spex Traits:"
  local shown_traits=""
  for trait in $VALID_TRAITS; do
    local canonical
    canonical=$(resolve_trait_name "$trait")
    # Skip if we already showed this canonical trait
    if echo "$shown_traits" | grep -qw "$canonical"; then
      continue
    fi
    shown_traits="$shown_traits $canonical"

    val=$(jq -r ".traits[\"$canonical\"] // false" "$TRAITS_CONFIG")
    if [ "$val" = "true" ]; then
      if [ "$canonical" != "$trait" ]; then
        echo "  $canonical: enabled (was: $trait)"
      else
        # Check if this canonical has aliases
        local aliases=""
        for t2 in $VALID_TRAITS; do
          [ "$t2" = "$canonical" ] && continue
          local c2
          c2=$(resolve_trait_name "$t2")
          [ "$c2" = "$canonical" ] && aliases="$aliases $t2"
        done
        if [ -n "$aliases" ]; then
          echo "  $canonical: enabled (aliases:$aliases)"
        else
          echo "  $canonical: enabled"
        fi
      fi
    else
      echo "  $canonical: disabled"
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

  # Deprecation notice for old trait names
  local canonical
  canonical=$(resolve_trait_name "$trait")
  if [ "$canonical" != "$trait" ]; then
    echo "NOTICE: Trait '$trait' is deprecated. Use '$canonical' instead."
    trait="$canonical"
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

  # Set agent teams env var if teams trait was enabled
  if [ "$trait" = "teams" ]; then
    ensure_agent_teams_env
  fi

  # Add worktrees_config with defaults when enabling worktrees
  if [ "$trait" = "worktrees" ]; then
    local has_wt_config
    has_wt_config=$(jq -r '.worktrees_config // "absent"' "$TRAITS_CONFIG")
    if [ "$has_wt_config" = "absent" ]; then
      local tmp
      tmp=$(mktemp)
      jq '.worktrees_config = {"base_path": ".."}' "$TRAITS_CONFIG" > "$tmp"
      mv "$tmp" "$TRAITS_CONFIG"
    fi
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

  # Deprecation notice for old trait names
  local canonical
  canonical=$(resolve_trait_name "$trait")
  if [ "$canonical" != "$trait" ]; then
    echo "NOTICE: Trait '$trait' is deprecated. Use '$canonical' instead."
    trait="$canonical"
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

  # Remove agent teams env var if teams trait was disabled
  if [ "$trait" = "teams" ]; then
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
        echo "Usage: spex-traits.sh init [--enable trait1,trait2]" >&2
        exit 2
        ;;
    esac
    shift
  done

  # Build the traits JSON object
  local superpowers_val="false" teams_val="false" worktrees_val="false" deep_review_val="false"

  if [ -n "$enable_list" ]; then
    IFS=',' read -ra traits_arr <<< "$enable_list"
    for t in "${traits_arr[@]}"; do
      t=$(echo "$t" | tr -d ' ')
      # Accept deprecated names and map to consolidated trait
      case "$t" in
        teams-vanilla|teams-spec)
          echo "NOTICE: '$t' is deprecated. Using consolidated 'teams' trait."
          t="teams"
          ;;
        beads)
          echo "NOTICE: 'beads' trait has been removed. Task state is tracked directly in tasks.md."
          continue
          ;;
      esac
      if ! is_valid_trait "$t"; then
        echo "ERROR: Invalid trait '$t'. Valid traits: $VALID_TRAITS" >&2
        exit 2
      fi
      case "$t" in
        superpowers) superpowers_val="true" ;;
        deep-review) deep_review_val="true" ;;
        teams) teams_val="true" ;;
        worktrees) worktrees_val="true" ;;
      esac
    done

    # Auto-resolve: teams requires superpowers
    if [ "$teams_val" = "true" ]; then
      if [ "$superpowers_val" = "false" ]; then
        superpowers_val="true"
        echo "NOTE: Auto-enabling superpowers (required by teams)."
      fi
    fi
  fi

  mkdir -p "$(dirname "$TRAITS_CONFIG")"
  local worktrees_config=""
  if [ "$worktrees_val" = "true" ]; then
    worktrees_config=',
  "worktrees_config": {
    "base_path": ".."
  }'
  fi
  local external_tools_config=""
  if [ "$deep_review_val" = "true" ]; then
    external_tools_config=',
  "external_tools": {
    "enabled": true,
    "coderabbit": true,
    "copilot": true
  }'
  fi
  cat > "$TRAITS_CONFIG" <<EOF
{
  "version": 1,
  "traits": {
    "superpowers": $superpowers_val,
    "deep-review": $deep_review_val,
    "teams": $teams_val,
    "worktrees": $worktrees_val
  }${worktrees_config}${external_tools_config},
  "applied_at": "$(now_iso)"
}
EOF

  echo "Traits config created."

  # Set agent teams env var if teams trait was enabled
  if [ "$teams_val" = "true" ]; then
    ensure_agent_teams_env
  fi

  do_list
  do_apply
}

apply_internal_overlays() {
  # Apply overlays from _ship-guard (and any future internal overlays).
  # These are always applied unconditionally, not user-configurable.
  local guard_dir="$PLUGIN_ROOT/overlays/_ship-guard"
  [ -d "$guard_dir" ] || return 0

  local applied=0 skipped=0
  while IFS= read -r -d '' overlay_file; do
    local rel_path="${overlay_file#"$guard_dir"/}"
    local overlay_subdir
    overlay_subdir=$(dirname "$rel_path")
    local overlay_basename
    overlay_basename=$(basename "$rel_path")
    local target_basename="${overlay_basename%.append.md}.md"

    local target_file=""
    case "$overlay_subdir" in
      commands) target_file=".claude/commands/$target_basename" ;;
      *) continue ;;
    esac

    [ -f "$target_file" ] || continue

    # Check sentinel (SPEX-GUARD:ship)
    if grep -q "<!-- SPEX-GUARD:ship -->" "$target_file" 2>/dev/null; then
      skipped=$((skipped + 1))
      continue
    fi

    printf '\n' >> "$target_file"
    cat "$overlay_file" >> "$target_file"
    applied=$((applied + 1))
  done < <(find "$guard_dir" -name "*.append.md" -print0 2>/dev/null)

  if [ $applied -gt 0 ]; then
    echo "Ship pipeline guard: $applied overlay(s) applied, $skipped already present."
  fi
}

do_apply() {
  ensure_config

  # Ensure agent teams env var matches current trait state on every apply
  ensure_agent_teams_env

  # Always apply internal _ship-guard overlays (not user-configurable)
  apply_internal_overlays

  # Collect enabled traits
  enabled_traits=$(jq -r '.traits | to_entries[] | select(.value == true) | .key' "$TRAITS_CONFIG")

  if [ -z "$enabled_traits" ]; then
    echo "No traits enabled. Nothing to apply."
    return
  fi

  # Resolve aliases and deduplicate
  local resolved_traits=""
  local seen_traits=""
  for trait in $enabled_traits; do
    local canonical
    canonical=$(resolve_trait_name "$trait")
    # Deduplicate
    if echo "$seen_traits" | grep -qw "$canonical"; then
      continue
    fi
    seen_traits="$seen_traits $canonical"
    resolved_traits="$resolved_traits $canonical"
  done
  enabled_traits="$resolved_traits"

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

  # Cleanup stale trait blocks from target files
  # Check both legacy (SDD-TRAIT) and current (SPEX-TRAIT) markers
  local all_sentinels="superpowers beads teams worktrees"
  for target in $(printf '%s\n' "${target_files[@]}" | sort -u); do
    for sentinel_trait in $all_sentinels; do
      # Skip if this trait is enabled (its block will be re-applied fresh)
      local is_enabled=false
      for et in $enabled_traits; do
        [ "$et" = "$sentinel_trait" ] && is_enabled=true
      done
      $is_enabled && continue

      # Remove block from sentinel to next sentinel or EOF
      # Check both old (SDD-TRAIT) and new (SPEX-TRAIT) markers
      for marker_prefix in "SDD-TRAIT" "SPEX-TRAIT"; do
        local sentinel="<!-- ${marker_prefix}:${sentinel_trait} -->"
        if grep -q "$sentinel" "$target" 2>/dev/null; then
          local tmp
          tmp=$(mktemp)
          awk -v sentinel="$sentinel" '
            BEGIN { skip=0 }
            $0 ~ sentinel { skip=1; next }
            skip && /<!-- (SDD|SPEX)-(TRAIT|GUARD):/ { skip=0 }
            !skip { print }
          ' "$target" > "$tmp"
          mv "$tmp" "$target"
          echo "Cleaned up stale '$sentinel_trait' block from $target"
        fi
      done
    done
  done

  # Apply overlays (idempotent via sentinel markers)
  local applied=0 skipped=0

  for i in "${!overlay_files[@]}"; do
    local sentinel="<!-- SPEX-TRAIT:${trait_names[$i]} -->"

    # Check for both old (SDD-TRAIT) and new (SPEX-TRAIT) markers
    if grep -q "<!-- \(SDD\|SPEX\)-TRAIT:${trait_names[$i]} -->" "${target_files[$i]}" 2>/dev/null; then
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

# spex-specific permission patterns
SPEX_PATTERN_INIT='Bash(*/scripts/spex-init.sh*)'
SPEX_PATTERN_TRAITS='Bash(*/scripts/spex-traits.sh*)'
SPEX_PATTERN_SPECIFY='Bash(specify *)'
# Broad tool patterns for YOLO level
SPEX_YOLO_EXTRAS=("Bash" "Read" "Edit" "Write" "mcp__*")

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

# Remove all spex-managed patterns from the allow list
remove_spex_patterns() {
  local tmp
  tmp=$(mktemp)
  jq '
    if .permissions.allow then
      .permissions.allow = [
        .permissions.allow[] |
        select(
          # spex script patterns
          (test("spex-init\\.sh|spex-traits\\.sh|^Bash\\(specify ") | not)
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
add_spex_patterns() {
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

  local has_init=false has_traits=false has_specify=false has_bash=false
  echo "$allow" | grep -q "spex-init" && has_init=true
  echo "$allow" | grep -q "spex-traits" && has_traits=true
  echo "$allow" | grep -q "specify " && has_specify=true
  echo "$allow" | grep -qx "Bash" && has_bash=true

  if [ "$has_init" = true ] && [ "$has_traits" = true ] && [ "$has_specify" = true ] && [ "$has_bash" = true ]; then
    echo "yolo"
  elif [ "$has_init" = true ] && [ "$has_traits" = true ]; then
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
      echo "spex auto-approval: $current"
      echo ""
      echo "Levels:"
      echo "  none       No auto-approvals (confirm every command)"
      echo "  standard   Auto-approve spex plugin scripts"
      echo "  yolo       Auto-approve all tools (Bash, Read, Edit, Write, MCP, specify)"
      ;;
    none)
      ensure_settings
      local before
      before=$(detect_permission_level)
      remove_spex_patterns
      echo "Auto-approval set to: none"
      echo "All spex commands will require confirmation."
      [ "$before" != "none" ] && echo "CHANGED" || true
      ;;
    standard)
      ensure_settings
      local before
      before=$(detect_permission_level)
      remove_spex_patterns
      add_spex_patterns "$SPEX_PATTERN_INIT" "$SPEX_PATTERN_TRAITS"
      echo "Auto-approval set to: standard"
      echo "Auto-approved:"
      echo "  spex-init.sh        Project initialization"
      echo "  spex-traits.sh      Trait configuration and overlay management"
      [ "$before" != "standard" ] && echo "CHANGED" || true
      ;;
    yolo)
      ensure_settings
      local before
      before=$(detect_permission_level)
      remove_spex_patterns
      add_spex_patterns "$SPEX_PATTERN_INIT" "$SPEX_PATTERN_TRAITS" "$SPEX_PATTERN_SPECIFY" "${SPEX_YOLO_EXTRAS[@]}"
      echo "Auto-approval set to: yolo"
      echo "All tools auto-approved: Bash, Read, Edit, Write, MCP, specify CLI, spex scripts."
      [ "$before" != "yolo" ] && echo "CHANGED" || true
      ;;
    *)
      echo "ERROR: Invalid permission level '$level'. Use: none, standard, yolo" >&2
      exit 2
      ;;
  esac
}

show_usage() {
  echo "Usage: spex-traits.sh <command> [options]"
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
