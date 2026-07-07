# Implementation Plan: Extension-Local Scripts

**Branch**: `036-extension-local-scripts` | **Date**: 2026-07-06 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/036-extension-local-scripts/spec.md`

## Summary

Replace all `$PLUGIN_ROOT` script references with extension-local paths (`.specify/extensions/<ext-id>/scripts/<script>`). Add a Makefile `sync-scripts` target that copies canonical scripts from `spex/scripts/` into each extension's source directory. Update all command templates, skill files, the context hook, and the constitution. Simplify `spex-init.sh` by removing manual script-copy logic (already handled by `specify extension add`).

## Technical Context

**Language/Version**: Bash (POSIX-compatible), Python 3, Markdown
**Primary Dependencies**: `jq`, `yq`, `specify` CLI (spec-kit), GNU `diff`
**Storage**: File-based (Markdown commands, shell scripts)
**Testing**: `make test-install` (integration), `make sync-scripts-check` (CI), manual `rg` verification
**Target Platform**: macOS, Linux
**Project Type**: CLI plugin (Claude Code plugin with extensions)
**Performance Goals**: `make sync-scripts` under 5 seconds
**Constraints**: No upstream spec-kit changes needed. `specify extension add` already copies all files including `scripts/`.
**Scale/Scope**: 14 command files, 13 skill files, 1 context hook, 1 constitution, 1 init script, 9 unique scripts across 5 extensions

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-Guided Development | PASS | Following full SDD workflow |
| II. Extension Architecture | PASS | Making extensions self-contained and portable |
| III. Extension Composability | PASS | Each extension owns its scripts independently |
| IV. Quality Gates | PASS | Using ship pipeline with all gates |
| V. Naming Discipline | PASS | No naming changes |
| VI. Skill Autonomy | PASS | No skill logic changes, only path references |
| VII. State as Scripts | PASS | Scripts stay in `spex/scripts/` as canonical source; extensions get copies |
| Plugin root detection (constraint) | VIOLATION | FR-010 explicitly requires updating this constraint. The old `$PLUGIN_ROOT` mechanism is being replaced by extension-local paths. |
| File organization (constraint) | VIOLATION | Scripts will now also live in extension directories, not only in `spex/scripts/`. Constitution must be updated. |

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Plugin root detection constraint | Extension-local scripts eliminate the Claude Code-specific `<plugin-root>` dependency, enabling harness-agnostic operation | Keeping `$PLUGIN_ROOT` requires every harness to implement the same system prompt injection |
| File organization constraint | Extension directories need `scripts/` to be self-contained | Shared scripts dir would need upstream spec-kit support that doesn't exist |

## Project Structure

### Documentation (this feature)

```text
specs/036-extension-local-scripts/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
└── tasks.md             # Phase 2 output (via /speckit-tasks)
```

### Source Code (repository root)

```text
spex/
├── scripts/                          # Canonical script source (unchanged)
│   ├── spex-flow-state.sh
│   ├── spex-ship-state.sh
│   ├── spex-finish-context.sh
│   ├── spex-worktree-cwd.sh
│   ├── spex-closeout-gate.sh
│   ├── spex-triage-state.sh
│   ├── spex-ship-statusline.sh
│   ├── sanitize-gh-json.py
│   └── bash/spex-detach.sh
├── extensions/
│   ├── spex/scripts/                 # NEW: scripts for spex core
│   │   ├── spex-flow-state.sh
│   │   ├── spex-ship-state.sh
│   │   ├── spex-finish-context.sh
│   │   ├── spex-worktree-cwd.sh
│   │   ├── spex-ship-statusline.sh
│   │   └── bash/spex-detach.sh
│   ├── spex-gates/scripts/           # NEW: scripts for gates
│   │   ├── spex-flow-state.sh
│   │   └── spex-closeout-gate.sh
│   ├── spex-collab/scripts/          # NEW: scripts for collab
│   │   ├── spex-flow-state.sh
│   │   ├── spex-triage-state.sh
│   │   └── sanitize-gh-json.py
│   ├── spex-deep-review/scripts/     # NEW: scripts for deep review
│   │   └── spex-flow-state.sh
│   └── spex-detach/scripts/          # NEW: scripts for detach
│       └── bash/spex-detach.sh
└── Makefile (updated with sync-scripts target)

.claude/skills/
├── speckit-spex-ship/SKILL.md        # Updated: PLUGIN_ROOT -> extension-local
├── speckit-spex-brainstorm/SKILL.md  # Updated
├── speckit-spex-submit/SKILL.md      # Updated
├── speckit-spex-smoke-test/SKILL.md  # Updated
├── speckit-spex-flow-state/SKILL.md  # Updated
├── speckit-spex-gates-review-*/      # Updated (3 files)
├── speckit-spex-gates-review-plan/   # Updated
├── speckit-spex-collab-triage/       # Updated
└── (others as needed)

.specify/memory/constitution.md       # Updated: remove PLUGIN_ROOT constraint
```

**Structure Decision**: No new directories outside the existing `spex/extensions/` structure. Each extension gets a `scripts/` subdirectory. The canonical `spex/scripts/` remains as the single source of truth.

## Implementation Approach

### Phase 1: Build Infrastructure (sync-scripts + CI check)

Create the script inventory mapping and Makefile targets before touching any commands. This ensures the single-source-of-truth relationship is enforceable from the start.

**Script Inventory Mapping** (defined in Makefile):

| Script | spex | spex-gates | spex-collab | spex-deep-review | spex-detach |
|--------|------|------------|-------------|------------------|-------------|
| spex-flow-state.sh | x | x | x | x | |
| spex-ship-state.sh | x | | | | |
| spex-ship-statusline.sh | x | | | | |
| spex-finish-context.sh | x | | | | |
| spex-worktree-cwd.sh | x | | | | |
| spex-closeout-gate.sh | | x | | | |
| spex-triage-state.sh | | | x | | |
| sanitize-gh-json.py | | | x | | |
| bash/spex-detach.sh | x | | | | x |

**Makefile targets**:
- `sync-scripts`: Copies from `spex/scripts/` to each extension's `scripts/` dir per the mapping
- `sync-scripts-check`: Compares extension scripts against canonical sources, fails on mismatch (for CI)
- `release`: Add `sync-scripts-check` as a prerequisite

### Phase 2: Migrate Command Templates

For each command file in `spex/extensions/*/commands/`, replace:
1. Remove the "Step 0: Resolve Plugin Root" preamble section
2. Replace `$PLUGIN_ROOT/scripts/<script>` with `.specify/extensions/<own-ext-id>/scripts/<script>`
3. Remove any "Set `PLUGIN_ROOT` from the `<plugin-root>` tag..." instructions

**Commands to update** (14 files across 6 extensions):

| Extension | Command File | Scripts Referenced |
|-----------|-------------|-------------------|
| spex | speckit.spex.ship.md | spex-ship-state.sh, spex-worktree-cwd.sh |
| spex | speckit.spex.finish.md | spex-ship-state.sh, spex-finish-context.sh |
| spex | speckit.spex.submit.md | spex-detach.sh, spex-finish-context.sh, spex-ship-state.sh |
| spex | speckit.spex.brainstorm.md | spex-detach.sh |
| spex | speckit.spex.flow-state.md | spex-flow-state.sh |
| spex | speckit.spex.smoke-test.md | spex-ship-state.sh |
| spex-gates | speckit.spex-gates.review-spec.md | spex-flow-state.sh |
| spex-gates | speckit.spex-gates.review-plan.md | spex-flow-state.sh |
| spex-gates | speckit.spex-gates.review-code.md | spex-flow-state.sh |
| spex-gates | speckit.spex-gates.verify.md | spex-closeout-gate.sh |
| spex-collab | speckit.spex-collab.triage.md | spex-triage-state.sh, sanitize-gh-json.py |
| spex-collab | speckit.spex-collab.phase-manager.md | spex-flow-state.sh |
| spex-deep-review | speckit.spex-deep-review.run.md | spex-flow-state.sh |
| spex-detach | speckit.spex-detach.detach.md | spex-detach.sh |

### Phase 3: Migrate Skill Files

For each skill in `.claude/skills/speckit-*/SKILL.md`, replace `<PLUGIN_ROOT>/scripts/<script>` with `.specify/extensions/<ext-id>/scripts/<script>`. Remove the "Replace `<PLUGIN_ROOT>` with the actual path from the system reminder" instructions.

**Skills to update** (13 files):

| Skill | Scripts Referenced | Extension |
|-------|-------------------|-----------|
| speckit-spex-ship | spex-ship-state.sh, spex-worktree-cwd.sh | spex |
| speckit-spex-brainstorm | spex-detach.sh | spex |
| speckit-spex-submit | spex-detach.sh, spex-finish-context.sh, spex-ship-state.sh | spex |
| speckit-spex-smoke-test | spex-ship-state.sh | spex |
| speckit-spex-flow-state | spex-flow-state.sh | spex |
| speckit-spex-finish | spex-ship-state.sh, spex-finish-context.sh | spex |
| speckit-spex-gates-review-spec | spex-flow-state.sh | spex-gates |
| speckit-spex-gates-review-plan | spex-flow-state.sh | spex-gates |
| speckit-spex-gates-review-code | spex-flow-state.sh | spex-gates |
| speckit-spex-collab-triage | spex-triage-state.sh, sanitize-gh-json.py | spex-collab |
| speckit-spex-collab-phase-manager | spex-flow-state.sh | spex-collab |
| speckit-spex-deep-review-run | spex-flow-state.sh | spex-deep-review |
| speckit-spex-detach-detach | bash/spex-detach.sh | spex-detach |

### Phase 4: Update Context Hook and Constitution

1. **context-hook.py**: Remove the `<plugin-root>` tag from the injected `<spex-context>` block. The `plugin_root` variable is still needed internally (for command file lookup in `context-hook.sh`), but it should no longer be exposed to the agent via the system prompt.

2. **context-hook.sh**: The shared hook still uses `$PLUGIN_ROOT` as a parameter for internal file lookups (finding command files to check for `{Skill:` delegation). This internal usage is fine since it's resolved at hook execution time, not at command runtime. No change needed.

3. **constitution.md**: Update the "Plugin root detection" constraint in the Plugin Architecture Constraints section. Replace the `$PLUGIN_ROOT` requirement with the new extension-local script pattern.

### Phase 5: Simplify spex-init.sh

The `install_extensions` function already handles extension installation via `specify extension add`. Since `specify extension add` copies the entire extension directory (including `scripts/`), no additional script-copy logic is needed. The only changes:

1. Remove any residual manual script-copy logic (if any)
2. Verify the `configure_statusline` function can find the statusline script at the extension-local path (it currently uses `$script_dir` which resolves relative to `spex/scripts/`, so the canonical copy works fine during init)

### Phase 6: Verification

1. Run `make sync-scripts` to populate extension scripts
2. Run `make sync-scripts-check` to verify freshness
3. Run `rg 'PLUGIN_ROOT' spex/extensions/ .claude/skills/` to confirm zero matches (excluding brainstorm/specs/docs)
4. Run `make test-install` to verify plugin installs correctly
5. Run `rg '<plugin-root>' spex/scripts/hooks/context-hook.py` to confirm tag is removed
