# Implementation Plan: Replace find calls with plugin root references

**Branch**: `033-plugin-root-refs` | **Date**: 2026-07-02 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/033-plugin-root-refs/spec.md`

## Summary

Replace 16 `find ~/.claude -name '...' 2>/dev/null | head -1` patterns across 11 extension command files with direct `<PLUGIN_ROOT>/scripts/...` path references. Each file gets a "Step 0: Resolve Plugin Root" preamble (if not already present) that extracts the plugin root from the `<spex-context>` system reminder. This is a mechanical text replacement in markdown command files with no behavioral change.

## Technical Context

**Language/Version**: Markdown (command/skill files), Bash (inline code blocks within markdown)
**Primary Dependencies**: None (editing markdown content only)
**Storage**: N/A
**Testing**: `rg "find ~/\.claude" spex/extensions/` for zero-match verification; `make release` for integration test
**Target Platform**: Claude Code (AI agent harness)
**Project Type**: Plugin (AI agent extension system)
**Performance Goals**: N/A (no runtime change)
**Constraints**: Must preserve exact script execution behavior
**Scale/Scope**: 16 replacements across 11 files

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-Guided Development | PASS | Following full SDD workflow |
| II. Extension Architecture | PASS | Commands remain self-contained and portable |
| III. Extension Composability | PASS | No cross-extension modifications |
| IV. Quality Gates | PASS | Running full pipeline |
| V. Naming Discipline | PASS | No naming changes |
| VI. Skill Autonomy | PASS | Each command remains independent |
| VII. State as Scripts | PASS | Script references preserved, only resolution method changes |
| Plugin root detection | PASS | This change aligns with the constraint: "Commands extract `$PLUGIN_ROOT` from the `<spex-context>` system reminder" |

No violations. No complexity tracking needed.

## Project Structure

### Documentation (this feature)

```text
specs/033-plugin-root-refs/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
└── tasks.md             # Phase 2 output (from /speckit.tasks)
```

### Source Code (repository root)

```text
spex/
├── extensions/
│   ├── spex/
│   │   └── commands/
│   │       ├── speckit.spex.ship.md           # 2 find replacements
│   │       ├── speckit.spex.finish.md         # 2 find replacements
│   │       ├── speckit.spex.submit.md         # 3 find replacements
│   │       ├── speckit.spex.brainstorm.md     # 1 find replacement
│   │       ├── speckit.spex.flow-state.md     # 1 find replacement
│   │       └── speckit.spex.smoke-test.md     # 1 find replacement
│   ├── spex-detach/
│   │   └── commands/
│   │       └── speckit.spex-detach.detach.md  # 1 find replacement
│   ├── spex-gates/
│   │   └── commands/
│   │       ├── speckit.spex-gates.review-code.md  # 2 find replacements
│   │       ├── speckit.spex-gates.review-plan.md  # 1 find replacement
│   │       └── speckit.spex-gates.review-spec.md  # 1 find replacement
│   └── spex-deep-review/
│       └── commands/
│           └── speckit.spex-deep-review.run.md    # 1 find replacement
└── scripts/
    ├── spex-ship-state.sh
    ├── spex-flow-state.sh
    ├── spex-finish-context.sh
    ├── spex-worktree-cwd.sh
    └── bash/
        └── spex-detach.sh
```

**Structure Decision**: No new files or directories. All changes are edits to existing markdown command files.

## Research

### Reference Implementation

The canonical pattern is already established in `speckit.spex-collab.phase-manager.md`:

```markdown
## Step 0: Resolve Plugin Root

Extract the plugin root path from the `<plugin-root>` tag in the `<spex-context>` system reminder. All script references below use this path:

\`\`\`bash
FLOW_STATE="<PLUGIN_ROOT>/scripts/spex-flow-state.sh"
\`\`\`

Replace `<PLUGIN_ROOT>` with the actual path from the system reminder.
```

### Script Path Mapping

Each `find` pattern maps to a specific script path relative to `<PLUGIN_ROOT>`:

| find target | Replacement path | Files using it |
|-------------|-----------------|----------------|
| `spex-ship-state.sh` | `<PLUGIN_ROOT>/scripts/spex-ship-state.sh` | ship, finish, submit, smoke-test |
| `spex-flow-state.sh` | `<PLUGIN_ROOT>/scripts/spex-flow-state.sh` | flow-state, review-code, review-plan, review-spec, deep-review.run |
| `spex-finish-context.sh` | `<PLUGIN_ROOT>/scripts/spex-finish-context.sh` | finish, submit |
| `spex-detach.sh` | `<PLUGIN_ROOT>/scripts/bash/spex-detach.sh` | brainstorm, submit, detach |
| `spex-worktree-cwd.sh` | `<PLUGIN_ROOT>/scripts/spex-worktree-cwd.sh` | ship (already uses PLUGIN_ROOT) |

**Important**: `spex-detach.sh` lives at `scripts/bash/spex-detach.sh`, not `scripts/spex-detach.sh`.

### Preamble Requirements Per File

| File | Has preamble? | Action |
|------|--------------|--------|
| speckit.spex.ship.md | Yes (partial) | No preamble change; replace remaining `find` patterns |
| speckit.spex.finish.md | No | Add preamble |
| speckit.spex.submit.md | No | Add preamble |
| speckit.spex.brainstorm.md | No | Add preamble |
| speckit.spex.flow-state.md | No | Add preamble |
| speckit.spex.smoke-test.md | No | Add preamble |
| speckit.spex-detach.detach.md | No | Add preamble |
| speckit.spex-gates.review-code.md | No | Add preamble |
| speckit.spex-gates.review-plan.md | No | Add preamble |
| speckit.spex-gates.review-spec.md | No | Add preamble |
| speckit.spex-deep-review.run.md | No | Add preamble |

### Replacement Strategy

For each file:

1. **If preamble is missing**: Add a "Step 0: Resolve Plugin Root" section near the top of the execution flow. List all scripts referenced in that file.
2. **Replace each `find` pattern**: Change `$(find ~/.claude -name 'X' 2>/dev/null | head -1)` to the corresponding `<PLUGIN_ROOT>/scripts/X` reference.
3. **Preserve surrounding context**: The variable name and usage pattern around the `find` call stays the same. Only the path resolution changes.

### Replacement Pattern

**Before:**
```bash
SCRIPT="$(find ~/.claude -name 'script-name.sh' 2>/dev/null | head -1)"
```

**After:**
```bash
SCRIPT="<PLUGIN_ROOT>/scripts/script-name.sh"
```

Where `<PLUGIN_ROOT>` is defined in the preamble and replaced by the AI agent with the actual path from the system reminder.

## Implementation Approach

Group files by extension for logical commit boundaries:

1. **spex core extension** (6 files, 10 occurrences): ship, finish, submit, brainstorm, flow-state, smoke-test
2. **spex-detach extension** (1 file, 1 occurrence): detach
3. **spex-gates extension** (3 files, 4 occurrences): review-code, review-plan, review-spec
4. **spex-deep-review extension** (1 file, 1 occurrence): deep-review.run

Each group can be implemented and verified independently.

## Verification

After all replacements:

```bash
# Must return zero matches
rg "find ~/\.claude" spex/extensions/ --glob '*.md'

# Must return 11+ matches (all affected files plus existing collab files)
rg "PLUGIN_ROOT" spex/extensions/ --glob '*.md' -l

# Full integration test
make release
```
