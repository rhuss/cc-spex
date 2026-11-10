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

# --- Check specify CLI version (require >= 1.0.0) ---
check_version() {
  local version_output
  version_output=$(specify version 2>/dev/null) || return 1

  local version
  version=$(echo "$version_output" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  [ -n "$version" ] || return 1

  local major
  major=$(echo "$version" | cut -d. -f1)

  if [ "$major" -ge 1 ] 2>/dev/null; then
    return 0
  fi

  echo "ERROR: spec-kit version $version is too old (requires >= 1.0.0)."
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

# --- Ensure extension command skills exist ---
# Workaround: upstream extensions (e.g., git) don't ship .specify-dev/
# agent-commands/ directories, so their commands aren't registered as
# Claude Code skills. Spex extensions use symlinks for this, but upstream
# extensions rely on specify init which no longer generates git skills.
# This fills the gap until upstream adds agent-commands to the git extension.
ensure_extension_skills() {
  local ext_dir=".specify/extensions"
  [ -d "$ext_dir" ] || return 0

  for ext in "$ext_dir"/*/; do
    [ -d "${ext}commands" ] || continue
    local ext_id
    ext_id=$(basename "$ext")

    for cmd_file in "${ext}commands"/speckit.*.md; do
      [ -f "$cmd_file" ] || continue
      local cmd_name
      cmd_name=$(basename "$cmd_file" .md | tr '.' '-')
      local skill_dir=".claude/skills/${cmd_name}"

      if [ ! -f "${skill_dir}/SKILL.md" ]; then
        mkdir -p "$skill_dir"
        # Extract description from frontmatter (POSIX-compatible)
        local desc
        desc=$(awk '/^---$/{n++; next} n==1 && /^description:/{sub(/^description: *"?/, ""); sub(/"? *$/, ""); print; exit}' "$cmd_file")
        desc="${desc:-Extension command from $ext_id}"

        {
          printf '%s\n' '---'
          printf 'name: "%s"\n' "$cmd_name"
          printf 'description: "%s"\n' "$desc"
          printf '%s\n' 'compatibility: "Requires spec-kit project structure with .specify/ directory"'
          printf '%s\n' 'metadata:'
          printf '  author: "spec-kit-%s"\n' "$ext_id"
          printf '  source: "%s"\n' "$cmd_file"
          printf '%s\n' 'user-invocable: true'
          printf '%s\n' 'disable-model-invocation: false'
          printf '%s\n' '---'
          printf '\n'
          # Strip YAML frontmatter (everything between first two --- lines)
          awk '/^---$/{n++; next} n>=2{print}' "$cmd_file"
        } > "${skill_dir}/SKILL.md"
      fi
    done
  done
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
      if [ -n "$current_cmd" ]; then
        # A command that ENDS in our script name is ours (the bare path, or `bash <path>`).
        # If it still resolves, nothing to do. If it points at a script that is gone (a
        # plugin-cache path from an older version, a deleted temp source), refresh it below
        # and do not save it as the chain target: it would chain to nothing. A command that
        # merely mentions the script elsewhere (a wrapper) is someone else's and is chained.
        case "$current_cmd" in
          *spex-ship-statusline.sh)
            if [ "$current_cmd" = "$abs_script" ] || [ -f "$current_cmd" ]; then
              return 0
            fi
            current_cmd=""
            ;;
        esac
        # Different statusline exists: save the whole command line for chaining (a bare path
        # or `bash script.sh --args`). If it cannot be saved, leave the user's line alone
        # rather than replace it with nothing to fall back to. The braces keep the shell's own
        # "cannot create" message out of the output, so only our warning shows.
        if [ -n "$current_cmd" ]; then
          if ! { printf '%s\n' "$current_cmd" > "$chain_file"; } 2>/dev/null; then
            echo "  WARNING: could not save the existing status line to $chain_file; leaving it unchanged" >&2
            return 0
          fi
        fi
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

# --- Write and verify detach exclude entries if the extension is enabled ---
# Runs `spex-detach.sh ensure --was-enabled` when spex-detach is enabled now.
# Without a declaration, install_extensions keeps spex-detach disabled unless
# it was enabled before this run, so any entry added here is a repair.
# Its `Stealth mode: ...`, `Repaired stealth mode: ...` and warning lines go
# to stderr and reach the user. Skipped when install_extensions applied a
# declaration through spex-apply-extensions.sh in this run (that already ran
# ensure). A visible path never fails init (FR-004).
SPEX_DETACH_ENSURED=0
run_detach_ensure() {
  if [ "$SPEX_DETACH_ENSURED" = 1 ]; then
    return 0
  fi
  local detach_script=".specify/extensions/spex-detach/scripts/spex-detach.sh"
  [ -x "$detach_script" ] || return 0

  # Check if extension is enabled in registry
  local enabled
  enabled=$(jq -r '.extensions["spex-detach"].enabled // false' .specify/extensions/.registry 2>/dev/null)
  [ "$enabled" = "true" ] || return 0

  local out rc=0 err
  err=$(mktemp "${TMPDIR:-/tmp}/spex-detach-err.XXXXXX") || err=/dev/null
  out=$("$detach_script" ensure --was-enabled 2>"$err") || rc=$?
  if [ "$err" != /dev/null ]; then
    cat "$err" >&2
    report_detach_crash "$rc" "$out" "$(tail -n 1 "$err")"
    rm -f "$err"
  else
    report_detach_crash "$rc" "$out" ""
  fi
  return 0
}

# --- Report an `ensure` that failed without a result ---
# `ensure` prints its JSON result on stdout for exit 0 (active) and 1 (a path
# is visible); exit 2 means "not a git repository" and stays silent. Any other
# failure (no Python, a crash) printed no stealth-mode line, so say so, with
# the last error line (the fast path filters the rest out). Never changes the
# exit code (FR-004). Keep in sync with spex-apply-extensions.sh.
# report_detach_crash <exit code> <stdout> <last stderr line>
report_detach_crash() {
  if [ "$1" -ne 0 ] && [ "$1" -ne 2 ] && [ -z "$2" ]; then
    echo "WARNING: stealth mode is NOT fully active. The exclude entries could not be written or verified:" >&2
    echo "  spex-detach.sh ensure failed with exit code $1${3:+: $3}" >&2
  fi
}

# --- Ensure spex-generated files are ignored locally ---
#
# These patterns go to .git/info/exclude, never to the tracked .gitignore.
# Committing them pushes spex's local scaffolding into a repository that never
# opted into spex, and the rules can be actively wrong there: OpenShell, for
# one, uses .agents/ for its own contributor workflows.
#
# .git/info/exclude is per-clone and shared across worktrees (git-common-dir),
# which is the same mechanism spex-detach uses for stealth mode.
SPEX_EXCLUDE_SENTINEL="# spex: generated/local files (only constitution is committed)"
SPEX_EXCLUDE_PATTERNS='**/.claude/
**/.agents/
**/.codex/
**/.specify/**
!**/.specify/spex.json
!**/.specify/memory/
!**/.specify/memory/constitution.md'

configure_git_exclude() {
  local git_common_dir exclude_file pattern

  git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || return 0
  [ -n "$git_common_dir" ] || return 0

  exclude_file="$git_common_dir/info/exclude"
  mkdir -p "$git_common_dir/info"
  [ -f "$exclude_file" ] || : > "$exclude_file"

  if ! grep -qF "$SPEX_EXCLUDE_SENTINEL" "$exclude_file" 2>/dev/null; then
    printf '\n%s\n' "$SPEX_EXCLUDE_SENTINEL" >> "$exclude_file"
  fi

  printf '%s\n' "$SPEX_EXCLUDE_PATTERNS" | while IFS= read -r pattern; do
    [ -n "$pattern" ] || continue
    grep -qxF -- "$pattern" "$exclude_file" 2>/dev/null || printf '%s\n' "$pattern" >> "$exclude_file"
  done

  echo "  Updated .git/info/exclude with spex patterns"
  warn_gitignore_leftovers
}

# Older spex versions appended their patterns to the tracked .gitignore, where
# they get committed and show up in review. Report the leftover block, but never
# edit a tracked file on the user's behalf.
warn_gitignore_leftovers() {
  [ -f ".gitignore" ] || return 0
  grep -qF "# spex: generated/local files" ".gitignore" 2>/dev/null || return 0

  echo ""
  echo "  WARNING: .gitignore still holds a spex block from an earlier version."
  echo "  Those patterns now live in .git/info/exclude and are no longer needed here."
  echo "  Remove the block below from .gitignore so it stays out of your commits:"
  grep -n -A7 -F "# spex: generated/local files" ".gitignore" | sed 's/^/    /'
  echo ""
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
      local python_resolve
      python_resolve="$(cd "$script_dir/hooks" 2>/dev/null && pwd)/python-resolve.sh"

      if [ ! -f "$codex_pretool" ] || [ ! -f "$codex_context" ]; then
        echo "  WARNING: Codex adapter scripts not found at $script_dir/adapters/codex/" >&2
        return 1
      fi

      # Write .codex/hooks.json with spex hook configuration (v0.144+ format)
      if [ -f .codex/hooks.json ]; then
        local tmp
        tmp=$(mktemp)
        jq --arg ctx "sh $python_resolve $codex_context" --arg pre "sh $python_resolve $codex_pretool" '
          .hooks.UserPromptSubmit = [(.hooks.UserPromptSubmit // [] | .[] | select(
            .hooks[0].command | test("context-hook\\.py") | not
          ))] + [{hooks: [{command: $ctx, type: "command"}]}] |
          .hooks.PreToolUse = [(.hooks.PreToolUse // [] | .[] | select(
            .hooks[0].command | test("pretool-gate\\.py") | not
          ))] + [{hooks: [{command: $pre, type: "command"}]}]
        ' .codex/hooks.json > "$tmp"
        mv "$tmp" .codex/hooks.json
      else
        jq -n --arg ctx "sh $python_resolve $codex_context" --arg pre "sh $python_resolve $codex_pretool" '{
          hooks: {
            UserPromptSubmit: [{hooks: [{command: $ctx, type: "command"}]}],
            PreToolUse: [{hooks: [{command: $pre, type: "command"}]}]
          }
        }' > .codex/hooks.json
      fi
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

# --- Save the spex-detach configuration before anything is reinstalled ---
# Reinstalling spex-detach deletes its configuration and installs the
# template; install_extensions restores the saved copy right after re-adding
# it (FR-007). A failed save stops init before anything is changed (FR-009).
detach_config() {
  sh "$(cd "$(dirname "$0")/.." && pwd)/scripts/spex-detach-config.sh" "$@"
}

save_detach_config() {
  detach_config save || exit 1
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
  # Every extension is installed. The enabled set is decided afterwards: the
  # declaration is applied exactly, or (without one) the previous state is
  # restored.
  local install_order=(spex spex-gates spex-worktrees spex-deep-review spex-teams spex-collab spex-detach)

  local registry=".specify/extensions/.registry" prev_disabled=""
  local profile_tool="$plugin_root/scripts/spex-setup-profile.py"
  local apply_tool="$plugin_root/scripts/spex-apply-extensions.sh"
  local use_declaration=false snapshot=""

  # With a project declaration (.specify/spex.json), the declaration is the
  # single source of truth: its selection is applied after reinstalling
  # (FR-004). Snapshot the registry first so only real changes are reported.
  if [ -f .specify/spex.json ]; then
    local validation_error
    if ! validation_error=$(python3 "$profile_tool" validate --root "$PWD" < .specify/spex.json 2>&1 >/dev/null); then
      echo "${validation_error:-ERROR: invalid .specify/spex.json}" >&2
      echo "Fix .specify/spex.json (or remove it) and run /spex:init again." >&2
      exit 1
    fi
    use_declaration=true
    if [ -f "$registry" ]; then
      snapshot=$(mktemp "${TMPDIR:-/tmp}/spex-registry-before.XXXXXX")
      cp "$registry" "$snapshot"
    fi
  else
    # Without a declaration (FR-016): remove + add re-registers an extension
    # as enabled. Remember which ones the user had disabled, so they can be
    # disabled again afterwards.
    prev_disabled=$(jq -r '.extensions // {} | to_entries[] | select(.value.enabled == false) | .key' "$registry" 2>/dev/null || true)
  fi

  # spex-detach is opt-in. Remember whether it was enabled before reinstalling
  # (re-adding registers it as enabled).
  local detach_before
  detach_before=$(jq -r '.extensions["spex-detach"].enabled // "absent"' "$registry" 2>/dev/null || echo absent)

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
      # Put the configuration saved by save_detach_config back over the
      # template (no saved copy: the template stays).
      if [ "$ext_id" = "spex-detach" ] && ! detach_config restore; then
        # Re-adding registered it as enabled. Leave it as it was before this
        # run: never switch stealth mode on after a failed run, and never
        # switch it off either (a disabled spex-detach that the declaration
        # names would be dropped as a legacy entry by the next refresh).
        if [ "$detach_before" != "true" ]; then
          specify extension disable spex-detach >/dev/null 2>&1 || true
        fi
        [ -z "$snapshot" ] || rm -f "$snapshot"
        exit 1
      fi
    else
      echo "WARNING: Failed to install extension '$ext_id'" >&2
      failed=$((failed + 1))
    fi
  done

  echo "  Extensions: $installed installed, $failed failed"

  # Keep spex-detach disabled unless it was enabled before: the declaration
  # path enables it below when the declaration names it, so an error before
  # that never leaves stealth mode on, and a refresh without a declaration
  # never turns on a newly installed spex-detach.
  if [ "$use_declaration" = true ] || [ "$detach_before" != "true" ]; then
    if [ "$(jq -r '.extensions["spex-detach"].enabled // false' "$registry" 2>/dev/null)" = "true" ]; then
      specify extension disable spex-detach >/dev/null 2>&1 ||
        echo "WARNING: could not disable extension 'spex-detach'" >&2
    fi
  fi

  if [ "$use_declaration" = true ]; then
    # Drop spex-detach from a legacy declaration that listed it while leaving
    # it disabled (FR-023), then apply the declaration exactly.
    if [ -n "$snapshot" ]; then
      if ! python3 "$profile_tool" migrate-detach --root "$PWD" --before "$snapshot"; then
        rm -f "$snapshot"
        exit 1
      fi
    fi
    local declared apply_rc=0
    if ! declared=$(python3 "$profile_tool" resolve --root "$PWD" | jq -r '.extensions | join(",")'); then
      rm -f "$snapshot"
      echo "ERROR: cannot read the extension selection from .specify/spex.json" >&2
      exit 1
    fi
    if [ -n "$snapshot" ]; then
      sh "$apply_tool" --before "$snapshot" "$declared" || apply_rc=$?
    else
      sh "$apply_tool" "$declared" || apply_rc=$?
    fi
    # spex-apply-extensions.sh already wrote and verified the spex-detach
    # exclude entries when the selection enables it.
    SPEX_DETACH_ENSURED=1
    rm -f "$snapshot"
    if [ "$apply_rc" -ne 0 ]; then
      echo "ERROR: could not apply the extension selection from .specify/spex.json ($declared)" >&2
      exit 1
    fi
  else
    # Restore the user's disabled extensions.
    local prev_id
    for prev_id in $prev_disabled; do
      if [ "$(jq -r --arg id "$prev_id" '.extensions[$id].enabled // empty' "$registry" 2>/dev/null)" = "true" ]; then
        specify extension disable "$prev_id" >/dev/null 2>&1 ||
          echo "WARNING: could not disable extension '$prev_id' again" >&2
      fi
    done
  fi

  # Enforce git extension dependency: worktrees needs git for branch creation.
  # With spex-worktrees enabled and no git extension, specify would fall back
  # to a hand-made branch in the main checkout, so refuse the setup instead.
  # Without a declaration, a spex-worktrees the user had disabled never
  # triggers the refusal, even if restoring the disabled state above failed
  # (prev_disabled is empty on the declaration path, so a declaration that
  # enables spex-worktrees always gets the git check).
  local worktrees_enabled
  worktrees_enabled=$(jq -r '.extensions["spex-worktrees"].enabled // false' "$registry" 2>/dev/null || echo false)
  if printf '%s\n' "$prev_disabled" | grep -qxF "spex-worktrees"; then
    worktrees_enabled=false
  fi
  if [ "$worktrees_enabled" = "true" ]; then
    local git_enabled
    git_enabled=$(jq -r '.extensions.git.enabled // false' "$registry" 2>/dev/null || echo false)
    if [ "$git_enabled" != "true" ]; then
      # Enable it, or install the bundled git extension when it is missing.
      if specify extension enable git >/dev/null 2>&1 || specify extension add git >/dev/null 2>&1; then
        git_enabled=$(jq -r '.extensions.git.enabled // false' "$registry" 2>/dev/null || echo false)
      fi
      if [ "$git_enabled" = "true" ]; then
        echo "  Enabled git extension (required by spex-worktrees)"
      else
        worktrees_git_error
        exit 1
      fi
    fi
  fi
}

# True when spex-worktrees is enabled but the git extension is not.
worktrees_missing_git() {
  local registry=".specify/extensions/.registry"
  [ "$(jq -r '.extensions["spex-worktrees"].enabled // false' "$registry" 2>/dev/null || echo false)" = "true" ] &&
    [ "$(jq -r '.extensions.git.enabled // false' "$registry" 2>/dev/null || echo false)" != "true" ]
}

# Error shown when spex-worktrees is enabled but the git extension is not.
# The second fix changes the selection through setup (FR-019), so the project
# declaration and the enabled extensions stay in agreement.
worktrees_git_error() {
  local setup_workflow
  setup_workflow="$(cd "$(dirname "$0")/.." && pwd)/setup.yml"
  {
    echo "ERROR: spex-worktrees requires the spec-kit git extension"
    echo "The git extension creates the feature branch inside the worktree; without it the branch would be made in the main checkout."
    echo "Fix it with one of:"
    echo "  specify extension add git      (or: specify extension enable git), then run /spex:init again"
    echo "  re-run setup with an extension selection that leaves out spex-worktrees, for example:"
    echo "    specify workflow run \"$setup_workflow\" -i extensions=spex-gates,spex-deep-review"
    echo "  After a direct specify workflow run, sh \"$(dirname "$setup_workflow")/scripts/spex-setup-report.sh\" prints the extension changes and errors."
  } >&2
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
    # Before install_extensions: the stealth-mode verification it may run must
    # see spex's own exclude rules (including the re-include rules).
    configure_git_exclude
    install_extensions
    install_agent_adapter "$(detect_agent)"
    configure_statusline
    run_detach_ensure
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

    configure_git_exclude
    install_extensions
    install_agent_adapter "$(detect_agent)"
    configure_statusline
    run_detach_ensure
    check_update 2>/dev/null || true
    echo ""
    echo "READY"
  else
    echo "ERROR: initialization completed but verification failed"
    exit 1
  fi
}

# --- Migrate legacy Claude permission rules (spec 061) ---
# Rewrites Bash(*), Read(*), Edit(*) and Write(*) in the project's
# .claude/settings.json and .claude/settings.local.json to bare tool names.
# Prints "Migrated: ..." or "WARNING: ..." lines on stderr; never fails refresh.
migrate_permissions() {
  sh "$(dirname "$0")/spex-permissions.sh" migrate || true
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
  run_detach_ensure
  install_agent_adapter "$(detect_agent)"
  migrate_permissions
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
  run_detach_ensure
  install_agent_adapter "$(detect_agent)"
  migrate_permissions

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
    # A was-enabled marker is only meaningful within one no-flag /spex:init;
    # drop one left by an abandoned run.
    rm -f .specify/.spex-detach-was-enabled 2>/dev/null || true
    save_detach_config
    do_refresh
    ;;
  --update)
    rm -f .specify/.spex-detach-was-enabled 2>/dev/null || true
    save_detach_config
    do_update
    ;;
  --clear)
    do_clear
    ;;
  *)
    # Tell the init skill whether a project declaration existed before this
    # run: the setup workflow below always writes one, so the skill cannot
    # check the file itself afterwards (FR-022).
    if [ -f .specify/spex.json ]; then
      echo "DECLARATION_EXISTED=true"
    else
      echo "DECLARATION_EXISTED=false"
    fi
    # Without a declaration the workflow below applies the recommended set,
    # which disables spex-detach, and the init skill re-applies the user's
    # selection afterwards. Remember that spex-detach was enabled before this
    # run, so spex-apply-extensions.sh reports entries it adds then as a
    # repair (FR-010). It removes the marker when it uses it.
    rm -f .specify/.spex-detach-was-enabled 2>/dev/null || true
    if [ ! -f .specify/spex.json ] &&
       [ "$(jq -r '.extensions["spex-detach"].enabled // false' .specify/extensions/.registry 2>/dev/null)" = "true" ]; then
      : > .specify/.spex-detach-was-enabled
    fi
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
        # SPEX_SOURCE is legacy defense-in-depth; the workflow engine now
        # sets SPECKIT_WORKFLOW_DIR automatically from the YAML file path.
        _spex_root="$(cd "$_script_dir/.." && pwd)"
        _rc=0
        # Without a declaration, run with the defaults instead of the
        # workflow's interactive prompts: the init skill asks the user in
        # Step 2 and applies and persists the answer itself (FR-022).
        set --
        [ -f .specify/spex.json ] || set -- -i extensions=recommended -i security=safe
        SPEX_SOURCE="$_spex_root" specify workflow run "$_setup_workflow" "$@" || _rc=$?
        # The workflow engine keeps step messages in the run state; print the
        # extension changes and any failed step's error (FR-018, FR-019).
        sh "$_spex_root/scripts/spex-setup-report.sh" || true
        exit "$_rc"
      fi
    fi

    # Legacy path: no workflow available
    # Save the detach configuration here, before anything changes and outside
    # the fast path's output-discarding (install_extensions) subshell.
    save_detach_config
    migrate_phase_marker
    # Fast path: already ready?
    if check_ready; then
      fix_constitution

      # With a declaration, install_extensions applies it through
      # spex-apply-extensions.sh, which already writes and verifies the
      # spex-detach exclude entries.
      _declared=false
      [ -f .specify/spex.json ] && _declared=true
      # Before the install, so the stealth-mode verification sees spex's own
      # exclude rules (including the re-include rules).
      configure_git_exclude 2>/dev/null || true
      # Quiet install, but never swallow the spex-worktrees/git refusal.
      _inst_rc=0
      _inst_out=$(install_extensions 2>&1) || _inst_rc=$?
      if [ "$_inst_rc" -ne 0 ] && worktrees_missing_git; then
        worktrees_git_error
        exit 1
      fi
      # The install output is discarded, except for the stealth-mode lines
      # (written, repaired, verified, or the warning with its path lines),
      # which must reach the user (FR-003, FR-004, FR-010).
      printf '%s\n' "$_inst_out" | awk '
        /^(Stealth mode:|Repaired stealth mode:)/ { print; w = 0; next }
        /^WARNING: stealth mode/ { print; w = 1; next }
        w && /^  / { print; next }
        { w = 0 }' >&2
      [ "$_declared" = false ] || SPEX_DETACH_ENSURED=1
      # If restoring the detach configuration failed during the install,
      # retry visibly so the error is shown. When spex-detach was not
      # re-added, the saved copy stays for the next run (as on the other
      # paths).
      if detach_config pending; then
        detach_config restore || exit 1
        # The install stopped at the failed restore, before the extension
        # selection was applied: report it instead of claiming READY.
        if [ "$_inst_rc" -ne 0 ]; then
          echo "ERROR: restoring the spex-detach configuration failed during the install; it is restored now. Run /spex:init again to apply the extension selection." >&2
          exit 1
        fi
      fi
      ensure_extension_skills 2>/dev/null || true
      configure_statusline || true
      run_detach_ensure || true
      check_update 2>/dev/null || true
      echo "READY"
      exit 0
    fi
    # Slow path: need initialization
    do_init
    ;;
esac
