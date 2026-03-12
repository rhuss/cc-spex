#!/bin/bash
# sdd-init.sh - Fast spec-kit initialization check and setup
#
# Usage:
#   sdd-init.sh           # Check + initialize if needed
#   sdd-init.sh --refresh # Re-download templates and refresh project
#   sdd-init.sh --update  # Update specify-cli and refresh project
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

# --- Apply trait overlays if configured ---
apply_traits() {
  local script_dir
  script_dir="$(dirname "$0")"
  if [ -f .specify/sdd-traits.json ] && [ -x "$script_dir/sdd-traits.sh" ]; then
    if ! "$script_dir/sdd-traits.sh" apply "$@"; then
      echo "WARNING: sdd-traits.sh apply failed (traits not applied). spec-kit is still usable." >&2
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
    apply_traits
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
    # Fast path: already ready?
    if check_ready; then
      fix_constitution
      apply_traits >/dev/null 2>&1 || true
      echo "READY"
      exit 0
    fi
    # Slow path: need initialization
    do_init
    ;;
esac
