#!/bin/bash
# spex-init.sh - Fast spec-kit initialization check and setup
#
# Usage:
#   spex-init.sh           # Check + initialize if needed
#   spex-init.sh --refresh # Re-download templates and refresh project
#   spex-init.sh --update  # Update specify-cli and refresh project
#
# Exit codes:
#   0 - READY (spec-kit fully initialized)
#   1 - Error (check output for details)
#   2 - NEED_INSTALL (specify CLI not found)
#   3 - RESTART_REQUIRED (new slash commands installed, restart Claude Code)

set -euo pipefail

# --- Fast path: single check for everything ---
check_ready() {
  command -v specify &>/dev/null || return 1
  [ -d .specify ] || return 1
  [ -f .specify/templates/spec-template.md ] || return 1
  ls .claude/commands/speckit.* &>/dev/null || return 1
  return 0
}

# --- Migrate sdd-traits.json to spex-traits.json ---
migrate_traits_config() {
  local old_config=".specify/sdd-traits.json"
  local new_config=".specify/spex-traits.json"

  if [ -f "$old_config" ] && [ ! -f "$new_config" ]; then
    cp "$old_config" "$new_config"
    echo "Migrated trait config: copied $old_config to $new_config"
    echo "  You can safely delete $old_config after verifying the migration."
  elif [ -f "$old_config" ] && [ -f "$new_config" ]; then
    echo "Both $old_config and $new_config exist. Using $new_config (preferred)."
  fi
}

# --- Migrate .sdd-phase to .spex-phase ---
migrate_phase_marker() {
  if [ -f ".specify/.sdd-phase" ] && [ ! -f ".specify/.spex-phase" ]; then
    mv ".specify/.sdd-phase" ".specify/.spex-phase"
  fi
}

# --- Configure status line for ship pipeline ---
configure_statusline() {
  local settings_file=".claude/settings.json"
  local script_dir
  script_dir="$(dirname "$0")"
  local statusline_script="$script_dir/spex-ship-statusline.sh"

  # Only configure if the statusline script exists
  [ -f "$statusline_script" ] || return 0

  # Make it executable
  chmod +x "$statusline_script" 2>/dev/null || true

  # Resolve absolute path for the statusline command
  local abs_script
  abs_script="$(cd "$(dirname "$statusline_script")" && pwd)/$(basename "$statusline_script")"

  mkdir -p .claude

  if [ -f "$settings_file" ]; then
    # Check if statusLine is already configured
    if jq -e '.statusLine' "$settings_file" >/dev/null 2>&1; then
      # Already has a statusLine config, don't overwrite
      return 0
    fi
    # Merge statusLine into existing settings
    local tmp
    tmp=$(mktemp)
    jq --arg cmd "$abs_script" '. + {"statusLine": {"type": "command", "command": $cmd}}' "$settings_file" > "$tmp"
    mv "$tmp" "$settings_file"
  else
    # Create new settings file with statusLine
    cat > "$settings_file" << EOF
{
  "statusLine": {
    "type": "command",
    "command": "$abs_script"
  }
}
EOF
  fi
  echo "  Status line configured for ship pipeline progress"
}

# --- Apply trait overlays if configured ---
apply_traits() {
  local script_dir
  script_dir="$(dirname "$0")"
  if [ -f .specify/spex-traits.json ] && [ -x "$script_dir/spex-traits.sh" ]; then
    if ! "$script_dir/spex-traits.sh" apply "$@"; then
      echo "WARNING: spex-traits.sh apply failed (traits not applied). spec-kit is still usable." >&2
    fi
  fi
}

# --- Migrate legacy constitution symlink setup ---
# Older versions stored the constitution at specs/constitution.md with a symlink
# from .specify/memory/constitution.md. The canonical location is now
# .specify/memory/constitution.md (matching upstream spec-kit).
fix_constitution() {
  # Case 1: symlink at .specify/memory/ pointing to specs/ - replace with real file
  if [ -L ".specify/memory/constitution.md" ]; then
    local target
    target=$(readlink ".specify/memory/constitution.md")
    if [ -f ".specify/memory/constitution.md" ]; then
      cp --remove-destination ".specify/memory/constitution.md" ".specify/memory/constitution.md.tmp" 2>/dev/null \
        || cp "$(cd .specify/memory && pwd -P)/$(readlink constitution.md)" ".specify/memory/constitution.md.tmp"
      rm ".specify/memory/constitution.md"
      mv ".specify/memory/constitution.md.tmp" ".specify/memory/constitution.md"
      echo "Migrated constitution: replaced symlink with real file at .specify/memory/constitution.md"
    fi
    # Clean up the old specs/ copy if it was the symlink target
    if [ -f "specs/constitution.md" ] && [ ! -L "specs/constitution.md" ]; then
      rm "specs/constitution.md"
      echo "Removed legacy specs/constitution.md"
    fi
  # Case 2: real file at specs/ but nothing at .specify/memory/ - move it
  elif [ -f "specs/constitution.md" ] && [ ! -e ".specify/memory/constitution.md" ]; then
    mkdir -p .specify/memory
    mv specs/constitution.md .specify/memory/constitution.md
    echo "Migrated constitution: moved specs/constitution.md to .specify/memory/constitution.md"
  # Case 3: real file at both locations - keep .specify/memory/, remove specs/
  elif [ -f "specs/constitution.md" ] && [ -f ".specify/memory/constitution.md" ] && [ ! -L ".specify/memory/constitution.md" ]; then
    rm "specs/constitution.md"
    echo "Removed duplicate specs/constitution.md (canonical: .specify/memory/constitution.md)"
  fi
}

# --- Migrate legacy beads integration ---
# The beads trait has been removed. Task state is tracked directly in
# tasks.md checkboxes. This function syncs any closed bd issues back to
# tasks.md and strips (bd-xxx) markers.
migrate_from_beads() {
  local has_beads_dir=false has_beads_trait=false has_bd_markers=false
  [ -d ".beads" ] && has_beads_dir=true
  [ "$(jq -r '.traits.beads // false' .specify/spex-traits.json 2>/dev/null)" = "true" ] && has_beads_trait=true
  grep -rq '(bd-' specs/*/tasks.md 2>/dev/null && has_bd_markers=true

  # Nothing to migrate
  $has_beads_dir || $has_beads_trait || $has_bd_markers || return 0

  echo "BEADS_MIGRATION_NEEDED"
  echo "BEADS_HAS_DIR=$has_beads_dir"
  echo "BEADS_HAS_TRAIT=$has_beads_trait"
  echo "BEADS_HAS_MARKERS=$has_bd_markers"
}

# Run the actual beads migration (called after user confirms in spex:init)
do_beads_migration() {
  echo "Migrating from beads..."

  # Reverse sync: if bd is available, update tasks.md checkboxes from bd state
  if command -v bd &>/dev/null; then
    for tasks_file in specs/*/tasks.md; do
      [ -f "$tasks_file" ] || continue
      grep -q '(bd-' "$tasks_file" 2>/dev/null || continue

      grep -oP '\(bd-[a-zA-Z0-9_-]+\)' "$tasks_file" 2>/dev/null | while read -r marker; do
        bd_id="${marker:1:-1}"
        status=$(bd show "$bd_id" --json 2>/dev/null | jq -r '.[0].status // "unknown"' 2>/dev/null || echo "unknown")
        if [ "$status" = "closed" ]; then
          sd "- \[ \] (T\d+) \(${bd_id}\)" '- [X] $1' "$tasks_file" 2>/dev/null || true
        fi
      done
      echo "  Synced bd state to $tasks_file"
    done
  fi

  # Strip (bd-xxx) markers from all tasks.md files
  for tasks_file in specs/*/tasks.md; do
    [ -f "$tasks_file" ] || continue
    if grep -q '(bd-' "$tasks_file" 2>/dev/null; then
      sd '\s*\(bd-[a-zA-Z0-9_-]+\)' '' "$tasks_file" 2>/dev/null || \
        sed -i '' 's/ *(bd-[a-zA-Z0-9_-]*)//g' "$tasks_file"
      echo "  Stripped bd markers from $tasks_file"
    fi
  done

  # Disable beads trait in config (if still present)
  if [ -f .specify/spex-traits.json ]; then
    local tmp
    tmp=$(mktemp)
    jq 'del(.traits["beads"])' .specify/spex-traits.json > "$tmp"
    mv "$tmp" .specify/spex-traits.json
  fi

  echo "Beads migration complete. The .beads/ directory is kept for reference."
  echo "You can delete it manually when ready: rm -rf .beads"
}

# --- Initialize project ---
do_init() {
  if ! command -v specify &>/dev/null; then
    echo "NEED_INSTALL"
    echo ""
    echo "The 'specify' CLI is required but not installed."
    echo ""
    echo "Install with:"
    echo "  uv tool install specify-cli --force --from git+https://github.com/github/spec-kit.git"
    echo ""
    echo "IMPORTANT: The CLI command is 'specify' (not 'speckit')."
    echo "           The package is 'specify-cli' (from github.com/github/spec-kit)."
    exit 2
  fi

  # Track whether commands existed before init
  local had_commands=false
  ls .claude/commands/speckit.* &>/dev/null && had_commands=true

  echo "Initializing spec-kit..."
  if ! specify init --here --ai claude --force; then
    echo "ERROR: specify init failed"
    exit 1
  fi

  # Check if NEW commands were installed (didn't exist before)
  if [ "$had_commands" = false ] && ls .claude/commands/speckit.* &>/dev/null; then
    fix_constitution
    echo ""
    echo "RESTART_REQUIRED"
    echo ""
    echo "spec-kit has installed local slash commands in:"
    echo "  .claude/commands/speckit.*"
    echo ""
    echo "To load these new commands, please:"
    echo "1. Save your work"
    echo "2. Close this conversation"
    echo "3. Restart Claude Code"
    echo "4. Return to this project"
    exit 3
  fi

  # Verify after init
  if check_ready; then
    fix_constitution
    migrate_traits_config
    migrate_phase_marker
    migrate_from_beads
    apply_traits
    configure_statusline
    echo ""
    echo "READY"
  else
    echo "ERROR: initialization completed but verification failed"
    exit 1
  fi
}

# --- Refresh templates only ---
do_refresh() {
  if ! command -v specify &>/dev/null; then
    echo "ERROR: specify CLI not installed. Run without flags to install, or use --update."
    exit 2
  fi

  echo "Refreshing project templates..."
  if ! specify init --here --ai claude --force; then
    echo "ERROR: specify init failed"
    exit 1
  fi

  fix_constitution
  apply_traits

  echo ""
  echo "RESTART_REQUIRED"
  echo "Templates and slash commands refreshed. Please restart Claude Code."
  exit 3
}

# --- Update protocol ---
do_update() {
  echo "Updating specify-cli from GitHub..."
  if ! uv tool install specify-cli --force --from git+https://github.com/github/spec-kit.git; then
    echo "ERROR: Failed to update specify-cli"
    echo "Please update manually: uv tool install specify-cli --force --from git+https://github.com/github/spec-kit.git"
    exit 1
  fi

  echo ""
  echo "Refreshing project setup..."
  specify init --here --ai claude --force

  apply_traits

  echo ""
  specify version

  echo ""
  echo "RESTART_REQUIRED"
  echo "Slash commands refreshed. Please restart Claude Code."
  exit 3
}

# --- Main ---
case "${1:-}" in
  --refresh)
    do_refresh
    ;;
  --update)
    do_update
    ;;
  *)
    # Migrate legacy config files first
    migrate_traits_config
    migrate_phase_marker
    # Fast path: already ready?
    if check_ready; then
      fix_constitution
      migrate_from_beads
      apply_traits >/dev/null 2>&1 || true
      configure_statusline 2>/dev/null || true
      echo "READY"
      exit 0
    fi
    # Slow path: need initialization
    do_init
    ;;
esac
