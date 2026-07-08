# Implementation Plan: Workflow-Based Setup

**Branch**: `037-workflow-setup` | **Date**: 2026-07-07 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/037-workflow-setup/spec.md`

## Summary

Replace `spex-init.sh` with a spec-kit setup workflow (`setup.yml`) that installs all spex extensions, auto-detects the agent harness, and applies per-agent configuration. The workflow is the single-command entry point for all harnesses, executable from a GitHub URL or a local clone. The Claude Code plugin delegates its init to this workflow as a compatibility shim.

## Technical Context

**Language/Version**: YAML (spec-kit workflow format), Bash (shell steps), Python 3 (existing adapter scripts)
**Primary Dependencies**: `specify` CLI (spec-kit >= 0.7.4), `jq`, `yq`
**Storage**: File-based (YAML workflow, JSON config, Markdown commands)
**Testing**: Manual verification on 3 harnesses (Claude Code, Codex, OpenCode), `specify workflow run` dry-run if supported
**Target Platform**: macOS, Linux (any platform spec-kit supports)
**Project Type**: CLI plugin (spec-kit extension bundle with setup workflow)
**Performance Goals**: Setup completes in under 60 seconds (SC-001)
**Constraints**: No upstream spec-kit changes required. Workflow uses only existing step types.
**Scale/Scope**: 1 setup workflow, 1 bundle manifest, 3 harness switch branches, 7 extensions, 1 CC plugin shim update

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-Guided Development | PASS | Following full SDD workflow |
| II. Extension Architecture | PASS | Extensions remain self-contained; workflow is the orchestrator |
| III. Extension Composability | PASS | Independent extensions, workflow handles dependency ordering |
| IV. Quality Gates | PASS | Using step-by-step specify flow |
| V. Naming Discipline | PASS | No naming changes |
| VI. Skill Autonomy | PASS | Setup workflow is orchestration, not skill logic |
| VII. State as Scripts | PASS | Setup logic moves from bash script to declarative workflow |
| Extension-local scripts (constraint) | PASS | Extensions carry their own scripts (from feature 036) |

## Project Structure

### Documentation (this feature)

```text
specs/037-workflow-setup/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
└── tasks.md             # Phase 2 output (via /speckit-tasks)
```

### Source Code (repository root)

```text
spex/
├── setup.yml                         # NEW: spec-kit setup workflow
├── bundle.yml                        # NEW: bundle manifest
├── extensions/                       # Existing (unchanged)
│   ├── spex/
│   ├── spex-gates/
│   ├── spex-collab/
│   ├── spex-deep-review/
│   ├── spex-detach/
│   ├── spex-teams/
│   └── spex-worktrees/
├── scripts/
│   ├── spex-init.sh                  # MODIFIED: delegate to workflow when specify available
│   ├── hooks/
│   │   └── shared/
│   │       └── detect-agent.sh       # Existing (used by workflow shell steps)
│   └── adapters/
│       ├── codex/                    # Existing (installed by workflow)
│       └── opencode/                 # Existing (installed by workflow)
└── templates/
    └── agents-md/                    # Existing (installed by workflow)
        ├── codex.md
        └── opencode.md
```

**Structure Decision**: The setup workflow (`setup.yml`) lives at the spex root alongside `bundle.yml`. It replaces the orchestration logic in `spex-init.sh` while reusing existing adapter scripts and templates.

## Implementation Approach

### Phase 1: Create the Setup Workflow

Write `spex/setup.yml` using spec-kit workflow syntax with these inputs and steps:

**Inputs:**
- `integration`: string, default "auto" (auto, claude, codex, opencode)
- `extensions`: string, default "all" (all, interactive, or comma-separated list)
- `permissions`: string, default "standard" (standard, yolo, none)

**Steps (in order):**

1. **check-version**: `shell` step verifying `specify` CLI >= 0.7.4
2. **init-project**: `init` step running `specify init` with the resolved integration
3. **detect-agent**: `shell` step running `detect-agent.sh` when integration is "auto"
4. **migrate-commands**: `shell` step removing pre-skills-format command files
5. **install-extensions**: Sequential `shell` steps for each extension in dependency order: spex, spex-gates, spex-worktrees, spex-deep-review, spex-teams, spex-collab, spex-detach
6. **select-extensions**: `if` step on `inputs.extensions`:
   - "all": no action
   - "interactive": `prompt` step for agent-native selection, fallback to all
   - comma-separated: `shell` step to disable unselected
7. **adapt-harness**: `switch` on detected integration:
   - `claude`: Configure statusline, hooks, permissions in `.claude/settings.json`
   - `codex`: Install `.codex/hooks.json`, copy `AGENTS.md`
   - `opencode`: Install `.opencode/plugins/spex-plugin.ts`, copy `AGENTS.md`
   - `default`: Log neutral configuration message
8. **configure-permissions**: Nested `switch` within adapt-harness on `inputs.permissions`
9. **configure-gitignore**: `shell` step adding spex patterns
10. **fix-constitution**: `shell` step for legacy constitution migration
11. **check-update**: `shell` step checking for newer spex versions (non-blocking)

### Phase 2: Create Bundle Manifest

Write `spex/bundle.yml` declaring all extensions and the setup workflow in `provides`.

### Phase 3: Update spex-init.sh (Compatibility Shim)

Add delegation logic at the top of `do_init()`: if `specify` CLI is available and `setup.yml` exists relative to the script, delegate to `specify workflow run`. Otherwise fall through to the legacy init path.

### Phase 4: Test on Three Harnesses

1. **Claude Code**: Verify identical results to current `spex-init.sh`
2. **Codex**: Verify `.codex/hooks.json` and `AGENTS.md` created
3. **OpenCode**: Verify `.opencode/plugins/` and `AGENTS.md` created

### Phase 5: Release and Documentation

1. Add `setup.yml` to GitHub release assets
2. Update README.md with `specify workflow run <url>` install command
3. Update `spex/docs/help.md`
4. Write migration guide

## Mapping: spex-init.sh Functions to Workflow Steps

| spex-init.sh Function | Workflow Step | Step Type |
|------------------------|--------------|-----------|
| `check_version` | check-version | `shell` |
| `check_ready` | check-ready | `if` |
| `do_init` / `specify init` | init-project | `init` |
| `install_extensions` | install-ext-* (7 sequential) | `shell` |
| `detect_agent` | detect-agent | `shell` |
| `install_agent_adapter` | adapt-harness | `switch` |
| `configure_statusline` | (inside claude case) | `shell` |
| `configure_gitignore` | configure-gitignore | `shell` |
| `fix_constitution` | fix-constitution | `shell` |
| `migrate_old_commands` | migrate-commands | `shell` |
| `check_update` | check-update | `shell` |
| Permission config (init skill) | configure-permissions | `switch` |
| Extension selection (init skill) | select-extensions | `if` + `prompt` |
