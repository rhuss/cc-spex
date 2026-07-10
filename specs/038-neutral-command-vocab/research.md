# Research: Neutral Command Vocabulary

## R1: CC-Specific Reference Audit

**Method**: `rg` scan of all 30 extension command files for AskUserQuestion, Agent tool, subagent_type, EnterWorktree, ExitWorktree, settings.json, settings.local.json, UserPromptSubmit, PreToolUse.

**Results**: 8 files contain CC-specific tool references (45 total):

| File | References |
|------|-----------|
| `speckit.spex-teams.orchestrate.md` | settings.json (1), settings.local.json (4), Agent Teams (4), CLAUDE_CODE_EXPERIMENTAL (2), team_name (1), isolation: "worktree" (1) |
| `speckit.spex-teams.research.md` | settings.json (1), settings.local.json (4), Agent Teams (4), CLAUDE_CODE_EXPERIMENTAL (2), team_name (1) |
| `speckit.spex.ship.md` | AskUserQuestion (2), Agent tool (4), subagent_type (1), Agent Teams (1) |
| `speckit.spex-worktrees.manage.md` | EnterWorktree (1), ExitWorktree (1), isolation: "worktree" (2) |
| `speckit.spex-deep-review.run.md` | Agent tool (2), subagent_type (1), harness-conditional blocks |
| `speckit.spex-gates.verify.md` | AskUserQuestion (2) |
| `speckit.spex-teams.implement.md` | Agent Teams (1), CLAUDE_CODE_EXPERIMENTAL (1) |
| `speckit.spex-gates.stamp.md` | AskUserQuestion (1) |

**Excluded**: 2 files use "subagent" as a neutral concept (revise.md, smoke-test.md). No UserPromptSubmit or PreToolUse references found in any command file.

## R2: Mapping Table Format

**Decision**: JSON (`command-map.json`)
**Rationale**: `jq` is already a required dependency. JSON avoids adding `yq` as a new dependency. Shell-native parsing via `jq`.
**Alternatives rejected**: YAML (adds dependency), TOML (no shell parser), sed scripts (not data-driven).

## R3: Idempotency Strategy

**Decision**: Always adapt from neutral source, never from previously adapted output.
**Rationale**: The setup workflow reinstalls extensions from source before adapting. No need to detect or reverse prior adaptations.

## R4: Atomicity Strategy

**Decision**: Transform to temp directory, move on success, leave originals on failure.
**Rationale**: Simple, shell-native (mktemp + mv), satisfies spec edge case requirement.

## R5: Existing Adapter Infrastructure

The `spex/scripts/adapters/` directory already exists with per-harness subdirectories:
- `codex/`: context-hook.py, pretool-gate.py
- `opencode/`: spex-plugin.ts

Adding `command-map.json` to each harness directory is a natural extension of this structure. A new `claude/` directory is needed since Claude Code has no adapter files yet (its configuration is inline in setup.yml).

## R6: setup.yml Integration Point

The setup workflow has these relevant steps in order:
1. `install-ext-*` (install all extensions)
2. `select-extensions` (enable/disable optional extensions)
3. `adapt-harness` (harness-specific config: statusline, hooks, plugins)
4. `configure-permissions`

The `adapt-commands` step should go between `select-extensions` and `adapt-harness`, since it transforms command content (which must happen after install but before harness-specific configuration). The existing `adapt-harness` step handles non-command harness config (statusline, hooks) and stays as-is.
