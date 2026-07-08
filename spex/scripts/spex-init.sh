#!/bin/bash
# spex-init.sh - Fast spec-kit initialization check and setup
#
# Usage:
#   spex-init.sh           # Check + initialize if needed
#   spex-init.sh --refresh # Re-download templates and refresh project
#   spex-init.sh --update  # Update specify-cli and refresh project
#   spex-init.sh --clear   # Remove flow/ship state file (reset status line)
#
# Exit codes:
#   0 - READY (spec-kit fully initialized)
#   1 - Error (check output for details)
#   2 - NEED_INSTALL (specify CLI not found)
#   3 - RESTART_REQUIRED (new slash commands installed, restart Claude Code)

set -euo pipefail

# --- Check specify CLI version (require >= 0.5.0) ---
check_version() {
  local version_output
  version_output=$(specify version 2>/dev/null) || return 1

  # Extract semver from decorated output (e.g., "CLI Version    0.5.1.dev0")
  local version
  version=$(echo "$version_output" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  [ -n "$version" ] || return 1

  # Parse major.minor.patch
  local major minor patch
  major=$(echo "$version" | cut -d. -f1)
  minor=$(echo "$version" | cut -d. -f2)
  patch=$(echo "$version" | cut -d. -f3)

  # Require >= 0.5.0
  if [ "$major" -gt 0 ] 2>/dev/null; then
    return 0
  elif [ "$major" -eq 0 ] && [ "$minor" -ge 5 ] 2>/dev/null; then
    return 0
  fi

  echo "ERROR: spec-kit version $version is too old for this version of spex."
  echo ""
  echo "spex v4.0.0+ requires spec-kit >= 0.5.0, which uses the Agent Skills format."
  echo ""
  echo "Upgrade with:"
  echo "  uv tool install specify-cli --force --from git+https://github.com/github/spec-kit.git"
  echo ""
  echo "Then re-run /spex:init to complete the migration."
  return 1
}

# --- Check for spex plugin updates ---
check_update() {
  command -v curl &>/dev/null || return 0
  command -v jq &>/dev/null || return 0

  local script_dir
  script_dir="$(dirname "$0")"
  local plugin_json="$script_dir/../.claude-plugin/plugin.json"
  [ -f "$plugin_json" ] || return 0

  local local_version
  local_version=$(jq -r '.version // empty' "$plugin_json" 2>/dev/null)
  [ -n "$local_version" ] || return 0

  # Validate semver format (no -dev check needed: plugin.json always has release versions)
  echo "$local_version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' || return 0

  local api_response
  api_response=$(curl -sf --connect-timeout 2 --max-time 3 \
    "https://api.github.com/repos/rhuss/cc-spex/releases/latest" 2>/dev/null) || return 0

  local latest_tag
  latest_tag=$(echo "$api_response" | jq -r '.tag_name // empty' 2>/dev/null)
  [ -n "$latest_tag" ] || return 0

  # Strip v prefix
  local latest_version="${latest_tag#v}"

  # Validate remote version format
  echo "$latest_version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+' || return 0

  # Compare versions: local < latest means update available
  local l_major l_minor l_patch r_major r_minor r_patch
  l_major=$(echo "$local_version" | cut -d. -f1)
  l_minor=$(echo "$local_version" | cut -d. -f2)
  l_patch=$(echo "$local_version" | cut -d. -f3)
  r_major=$(echo "$latest_version" | cut -d. -f1)
  r_minor=$(echo "$latest_version" | cut -d. -f2)
  r_patch=$(echo "$latest_version" | cut -d. -f3)

  local behind=false
  if [ "$l_major" -lt "$r_major" ] 2>/dev/null; then
    behind=true
  elif [ "$l_major" -eq "$r_major" ] && [ "$l_minor" -lt "$r_minor" ] 2>/dev/null; then
    behind=true
  elif [ "$l_major" -eq "$r_major" ] && [ "$l_minor" -eq "$r_minor" ] && [ "$l_patch" -lt "$r_patch" ] 2>/dev/null; then
    behind=true
  fi

  if [ "$behind" = true ]; then
    echo "  spex update available: $local_version -> $latest_version"
    # Extract breaking change lines from release body
    local breaking
    breaking=$(echo "$api_response" | jq -r '.body // empty' 2>/dev/null | grep -i '^BREAKING:' || true)
    if [ -n "$breaking" ]; then
      echo "$breaking" | while IFS= read -r line; do
        echo "  $line"
      done
    fi
  fi
}

# --- Fast path: single check for everything ---
check_ready() {
  command -v specify &>/dev/null || return 1
  [ -d .specify ] || return 1
  [ -f .specify/templates/spec-template.md ] || return 1
  # Verify all core skill files exist
  for cmd in specify plan implement tasks clarify; do
    [ -f ".claude/skills/speckit-${cmd}/SKILL.md" ] || return 1
  done
  return 0
}

# --- Migrate .sdd-phase to .spex-phase ---
migrate_phase_marker() {
  if [ -f ".specify/.sdd-phase" ] && [ ! -f ".specify/.spex-phase" ]; then
    mv ".specify/.sdd-phase" ".specify/.spex-phase"
  fi
}

# --- Configure status line for ship pipeline ---
configure_statusline() {
  local settings_file=".claude/settings.local.json"
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

  local chain_file=".claude/.spex-previous-statusline"

  if [ -f "$settings_file" ]; then
    if jq -e '.statusLine' "$settings_file" >/dev/null 2>&1; then
      local current_cmd
      current_cmd="$(jq -r '.statusLine.command // empty' "$settings_file")"
      if [ -n "$current_cmd" ] && [ -f "$current_cmd" ]; then
        # Already pointing to our script, nothing to do
        case "$current_cmd" in
          *spex-ship-statusline.sh) return 0 ;;
        esac
        # Different statusline exists, save it for chaining
        echo "$current_cmd" > "$chain_file"
      fi
    fi
    # Merge or update statusLine
    local tmp
    tmp=$(mktemp)
    jq --arg cmd "$abs_script" '.statusLine = {"type": "command", "command": $cmd}' "$settings_file" > "$tmp"
    mv "$tmp" "$settings_file"
  else
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

# --- Migrate old speckit commands to skills format ---
migrate_old_commands() {
  local found=false
  for f in .claude/commands/speckit.*.md; do
    [ -f "$f" ] || continue
    found=true
    break
  done
  $found || return 0

  echo "Migrating from speckit commands to skills format..."
  for f in .claude/commands/speckit.*.md; do
    [ -f "$f" ] || continue
    local basename
    basename=$(basename "$f" .md)
    echo "  Removed $f (replaced by .claude/skills/${basename//./-}/)"
    rm "$f"
  done
  echo "Migration complete."
}

# --- Ensure .gitignore covers spex-generated files ---
configure_gitignore() {
  local gitignore=".gitignore"
  local sentinel="# spex: generated/local files"

  # Migrate old patterns if present
  if [ -f "$gitignore" ]; then
    if grep -qF ".claude/commands/speckit." "$gitignore"; then
      sed -i '' 's|\.claude/commands/speckit\.\*|.claude/skills/|' "$gitignore" 2>/dev/null || \
        sed -i 's|\.claude/commands/speckit\.\*|.claude/skills/|' "$gitignore" 2>/dev/null || true
      echo "  Migrated .gitignore pattern from commands to skills"
    elif grep -qF ".claude/skills/speckit-*" "$gitignore"; then
      sed -i '' 's|\.claude/skills/speckit-\*|.claude/skills/|' "$gitignore" 2>/dev/null || \
        sed -i 's|\.claude/skills/speckit-\*|.claude/skills/|' "$gitignore" 2>/dev/null || true
      echo "  Migrated .gitignore pattern from speckit-* to skills/"
    fi
    # Migrate old per-file .specify ignores to blanket ignore with constitution whitelist
    if grep -qF ".specify/.spex-phase" "$gitignore"; then
      sed -i '' '/.specify\/.spex-phase/d;/.specify\/.spex-state/d;/.claude\/skills\//d;/.claude\/settings\.local\.json/d' "$gitignore" 2>/dev/null || \
        sed -i '/.specify\/.spex-phase/d;/.specify\/.spex-state/d;/.claude\/skills\//d;/.claude\/settings\.local\.json/d' "$gitignore" 2>/dev/null || true
      # Replace old sentinel with new block
      sed -i '' "s|$sentinel|$sentinel (only constitution is committed)\n**/.claude/\n**/.specify/**\n!**/.specify/memory/\n!**/.specify/memory/constitution.md|" "$gitignore" 2>/dev/null || \
        sed -i "s|$sentinel|$sentinel (only constitution is committed)\n**/.claude/\n**/.specify/**\n!**/.specify/memory/\n!**/.specify/memory/constitution.md|" "$gitignore" 2>/dev/null || true
      echo "  Migrated .gitignore to blanket .specify/ ignore with constitution whitelist"
      return 0
    fi
  fi

  # Skip if already configured (new or old sentinel)
  [ -f "$gitignore" ] && grep -qF "$sentinel" "$gitignore" && return 0

  cat >> "$gitignore" <<'EOF'

# spex: generated/local files (only constitution is committed)
**/.claude/
**/.specify/**
!**/.specify/memory/
!**/.specify/memory/constitution.md
EOF
  echo "  Updated .gitignore with spex patterns"
}

# --- Detect active agent ---
detect_agent() {
  local script_dir
  script_dir="$(dirname "$0")"
  local detect_script="$script_dir/hooks/shared/detect-agent.sh"
  if [ -f "$detect_script" ]; then
    sh "$detect_script" "$(pwd)"
  else
    echo "claude"
  fi
}

# --- Install agent-specific adapter hooks ---
install_agent_adapter() {
  local agent="${1:-claude}"
  local script_dir
  script_dir="$(dirname "$0")"
  local plugin_root
  plugin_root="$(cd "$script_dir/.." && pwd)"

  case "$agent" in
    codex)
      # Create .codex directory if needed
      mkdir -p .codex

      # Resolve absolute paths for adapter scripts
      local codex_pretool
      codex_pretool="$(cd "$script_dir/adapters/codex" 2>/dev/null && pwd)/pretool-gate.py"
      local codex_context
      codex_context="$(cd "$script_dir/adapters/codex" 2>/dev/null && pwd)/context-hook.py"

      if [ ! -f "$codex_pretool" ] || [ ! -f "$codex_context" ]; then
        echo "  WARNING: Codex adapter scripts not found at $script_dir/adapters/codex/" >&2
        return 1
      fi

      # Write .codex/hooks.json with spex hook configuration
      cat > .codex/hooks.json << HOOKEOF
{
  "hooks": [
    {
      "type": "command",
      "event": "UserPromptSubmit",
      "command": "python3 $codex_context"
    },
    {
      "type": "command",
      "event": "PreToolUse",
      "command": "python3 $codex_pretool"
    }
  ]
}
HOOKEOF
      echo "  Codex adapter hooks installed to .codex/hooks.json"

      # Install AGENTS.md from template if available
      local agents_template="$plugin_root/templates/agents-md/codex.md"
      if [ -f "$agents_template" ]; then
        cp "$agents_template" AGENTS.md
        echo "  AGENTS.md generated for Codex"
      fi
      ;;

    opencode)
      # Create .opencode/plugins directory if needed
      mkdir -p .opencode/plugins

      # Copy TypeScript plugin
      local opencode_plugin="$script_dir/adapters/opencode/spex-plugin.ts"
      if [ -f "$opencode_plugin" ]; then
        cp "$opencode_plugin" .opencode/plugins/spex-plugin.ts
        echo "  OpenCode plugin installed to .opencode/plugins/"
      else
        echo "  WARNING: OpenCode plugin not found at $opencode_plugin" >&2
      fi

      # Install AGENTS.md from template if available
      local agents_template="$plugin_root/templates/agents-md/opencode.md"
      if [ -f "$agents_template" ]; then
        cp "$agents_template" AGENTS.md
        echo "  AGENTS.md generated for OpenCode"
      fi
      ;;

    claude|*)
      # Claude Code uses existing hooks in .claude/settings.json
      # Install CLAUDE.md template if available and not already present
      local claude_template="$plugin_root/templates/agents-md/claude.md"
      if [ -f "$claude_template" ]; then
        # Claude Code CLAUDE.md is managed by specify init, don't overwrite
        :
      fi
      ;;
  esac
}

# --- Install bundled extensions ---
install_extensions() {
  local plugin_root
  plugin_root="$(cd "$(dirname "$0")/.." && pwd)"
  local extensions_dir="$plugin_root/extensions"

  if [ ! -d "$extensions_dir" ]; then
    echo "WARNING: No bundled extensions found at $extensions_dir" >&2
    return 0
  fi

  # Install in dependency order: extensions without dependencies first,
  # then extensions that depend on others (spex-deep-review, spex-teams,
  # and spex-collab require spex-gates).
  local install_order=(spex spex-gates spex-worktrees spex-deep-review spex-teams spex-collab spex-detach)
  # Optional extensions are installed but disabled by default.
  # The init skill handles enable/disable via AskUserQuestion.
  local optional_extensions=()

  local installed=0 failed=0
  for ext_id in "${install_order[@]}"; do
    local ext_path="$extensions_dir/$ext_id"
    [ -f "$ext_path/extension.yml" ] || continue
    # Remove first if already installed (specify extension add skips existing)
    if [ -d ".specify/extensions/$ext_id" ]; then
      echo "y" | specify extension remove "$ext_id" >/dev/null 2>&1 || true
    fi
    if specify extension add "$ext_path" --dev; then
      installed=$((installed + 1))
    else
      echo "WARNING: Failed to install extension '$ext_id'" >&2
      failed=$((failed + 1))
    fi
  done

  # Prompt for optional extensions
  for ext_id in ${optional_extensions[@]+"${optional_extensions[@]}"}; do
    local ext_path="$extensions_dir/$ext_id"
    [ -f "$ext_path/extension.yml" ] || continue

    # Already installed — skip the prompt
    if [ -d ".specify/extensions/$ext_id" ]; then
      continue
    fi

    local ext_desc
    ext_desc=$(yq -r '.extension.description // ""' "$ext_path/extension.yml" 2>/dev/null || echo "")

    printf "  Enable %s? (%s) [y/N]: " "$ext_id" "$ext_desc"
    read -r answer </dev/tty 2>/dev/null || { echo "  Skipped $ext_id (non-interactive)"; continue; }
    case "$answer" in
      [yY]|[yY][eE][sS])
        if specify extension add "$ext_path" --dev; then
          installed=$((installed + 1))
        else
          echo "WARNING: Failed to install extension '$ext_id'" >&2
          failed=$((failed + 1))
        fi
        ;;
      *)
        echo "  Skipped $ext_id"
        ;;
    esac
  done

  echo "  Extensions: $installed installed, $failed failed"
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
        || cat ".specify/memory/constitution.md" > ".specify/memory/constitution.md.tmp"
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

  # Version gate: require specify >= 0.5.0
  if ! check_version; then
    exit 1
  fi

  # Migrate old command-format files if present
  migrate_old_commands

  # Track whether skills existed before init
  local had_skills=false
  ls .claude/skills/speckit-*/SKILL.md &>/dev/null 2>&1 && had_skills=true

  echo "Initializing spec-kit..."
  if ! specify init --here --integration claude --script sh --force; then
    echo "ERROR: specify init failed"
    exit 1
  fi

  # Check if NEW skills were installed (didn't exist before)
  if [ "$had_skills" = false ] && ls .claude/skills/speckit-*/SKILL.md &>/dev/null 2>&1; then
    fix_constitution
    install_extensions
    install_agent_adapter "$(detect_agent)"
    configure_statusline
    configure_gitignore
    echo ""
    echo "RESTART_REQUIRED"
    echo ""
    echo "spec-kit has installed local skills in:"
    echo "  .claude/skills/speckit-*/"
    echo ""
    echo "To load these new skills, please:"
    echo "1. Save your work"
    echo "2. Close this conversation"
    echo "3. Restart Claude Code"
    echo "4. Return to this project"
    exit 3
  fi

  # Verify after init
  if check_ready; then
    fix_constitution

    migrate_phase_marker

    install_extensions
    install_agent_adapter "$(detect_agent)"
    configure_statusline
    configure_gitignore
    check_update 2>/dev/null || true
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
  if ! specify init --here --integration claude --script sh --force; then
    echo "ERROR: specify init failed"
    exit 1
  fi

  fix_constitution
  install_extensions
  install_agent_adapter "$(detect_agent)"
  check_update 2>/dev/null || true

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

  # Migrate old command-format files if present
  migrate_old_commands

  echo ""
  echo "Refreshing project setup..."
  specify init --here --integration claude --script sh --force
  install_extensions
  install_agent_adapter "$(detect_agent)"

  echo ""
  specify version

  echo ""
  echo "RESTART_REQUIRED"
  echo "Skills refreshed. Please restart Claude Code."
  exit 3
}

# --- Clear flow/ship state ---
do_clear() {
  local state_file=".specify/.spex-state"
  if [ -f "$state_file" ]; then
    rm -f "$state_file"
    echo "Cleared spex state (flow/ship status line reset)"
  else
    echo "No active spex state to clear"
  fi
}

# --- Main ---
case "${1:-}" in
  --refresh)
    do_refresh
    ;;
  --update)
    do_update
    ;;
  --clear)
    do_clear
    ;;
  *)
    # Delegate to setup workflow if specify CLI and setup.yml are available
    if command -v specify &>/dev/null; then
      _script_dir="$(dirname "$0")"
      _setup_workflow="$_script_dir/../setup.yml"
      if [ -f "$_setup_workflow" ]; then
        # Ensure project is initialized (workflow engine requires .specify/)
        if [ ! -d .specify ]; then
          if ! specify init --here --integration claude --script sh --force >/dev/null 2>&1; then
            echo "Failed to bootstrap .specify/ for setup workflow" >&2
            exit 1
          fi
        fi
        _spex_root="$(cd "$_script_dir/.." && pwd)"
        SPEX_SOURCE="$_spex_root" specify workflow run "$_setup_workflow"
        exit $?
      fi
    fi

    # Legacy path: no workflow available
    migrate_phase_marker
    # Fast path: already ready?
    if check_ready; then
      fix_constitution

      install_extensions >/dev/null 2>&1 || true
      configure_statusline 2>/dev/null || true
      configure_gitignore 2>/dev/null || true
      check_update 2>/dev/null || true
      echo "READY"
      exit 0
    fi
    # Slow path: need initialization
    do_init
    ;;
esac
