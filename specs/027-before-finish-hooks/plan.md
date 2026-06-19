# Implementation Plan: Before/After Finish Hook Support

**Branch**: `027-before-finish-hooks` | **Date**: 2026-06-19 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/027-before-finish-hooks/spec.md`

## Summary

Add hook-reading boilerplate to the finish skill so `before_finish` and `after_finish` hooks fire at the correct lifecycle points. Register the smoke test as an optional `before_finish` hook in the spex extension manifest. Update the next-steps text in review-code and deep-review skills to mention the smoke test.

## Technical Context

**Language/Version**: Markdown (skill files), YAML (extension config), Bash (POSIX-compatible)
**Primary Dependencies**: spec-kit extension system, `yq` for YAML parsing
**Storage**: N/A (file-based config only)
**Testing**: Manual verification via `make release` (integration test) + visual inspection of hook prompts
**Target Platform**: Claude Code CLI (macOS/Linux)
**Project Type**: AI agent plugin (Markdown skills + YAML config)
**Performance Goals**: N/A (no runtime performance requirements)
**Constraints**: No compiled artifacts; Markdown and Bash only (constitution constraint)
**Scale/Scope**: 4 files modified, ~60 lines added total

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-Guided Development | PASS | Following full SDD workflow |
| II. Extension Architecture | PASS | Hook registered in extension manifest, fires at command boundaries |
| III. Extension Composability | PASS | New hook is independent, does not modify other extensions |
| IV. Quality Gates | PASS | Smoke test hook adds a quality checkpoint before finish |
| V. Naming Discipline | PASS | Uses `speckit.spex.smoke-test` naming pattern |
| VI. Skill Autonomy | PASS | Finish skill delegates to hooks, no logic duplication |
| VII. State as Scripts | N/A | No state management changes (hook boilerplate is markdown instructions, not state logic) |

No violations. No entries needed in Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/027-before-finish-hooks/
├── plan.md              # This file
├── research.md          # Phase 0 output (minimal, no unknowns)
├── data-model.md        # Phase 1 output (minimal, no data entities)
├── tasks.md             # Phase 2 output (via /speckit-tasks)
└── checklists/
    └── requirements.md  # Spec quality checklist
```

### Source Code (files to modify)

```text
spex/extensions/spex/
├── extension.yml                    # Add before_finish hook registration
└── commands/
    └── speckit.spex.finish.md       # Add hook-reading boilerplate (before Phase 1 + after Phase 6)

spex/extensions/spex-gates/
└── commands/
    └── speckit.spex-gates.review-code.md   # Update next-steps text

spex/extensions/spex-deep-review/
└── commands/
    └── speckit.spex-deep-review.run.md     # Update next-steps text
```

**Structure Decision**: No new files created. Four existing files modified. The changes follow the existing extension architecture.

## Implementation Approach

### Deliverable 1: Hook-reading boilerplate in finish skill (FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-011, FR-012, FR-013)

Copy the Pre-Execution Checks pattern from core spec-kit's implement.md template into `speckit.spex.finish.md`:

**Before Phase 1 (before_finish):**
- Insert a new section "## Pre-Execution Checks" before the existing "## Phase 1: Verification"
- The section reads `.specify/extensions.yml`, checks for `hooks.before_finish` entries
- Filters out disabled hooks, skips hooks with conditions
- For optional hooks: outputs prompt text
- For mandatory hooks: auto-executes
- If extensions.yml missing or malformed: skips silently

**After Phase 6 (after_finish):**
- Insert hook-reading logic after Phase 6 state cleanup, before Phase 7 watch mode
- Same pattern but reads `hooks.after_finish` entries
- Only fires when watch mode is NOT active (watch mode has its own cleanup path)

**Autonomous mode handling (edge case):**
- When `.specify/.spex-state` exists with `ask` of `smart` or `never`, optional hooks execute without prompting (same behavior as ship pipeline suppression of interactive prompts)

### Deliverable 2: Hook registration in extension manifest (FR-008)

Add `before_finish` hook to `spex/extensions/spex/extension.yml` under the `hooks:` section:

```yaml
before_finish:
  command: speckit.spex.smoke-test
  optional: true
  prompt: "Run interactive smoke test before finishing?"
  description: "Walk through spec acceptance scenarios interactively"
```

After adding, reinstall the extension to aggregate into `.specify/extensions.yml`:
```bash
specify extension add spex/extensions/spex --dev
```

### Deliverable 3: Next-steps text updates (FR-009, FR-010)

Update the "Next Steps" section in both skills to add smoke test as step 1:

**In `speckit.spex-gates.review-code.md` (line ~416):**
```
Code review complete. To close out this feature:
  1. /speckit-spex-smoke-test    (walk through acceptance scenarios)
  2. /clear                      (free context for final gate)
  3. /speckit-spex-finish         (verify + merge/PR, all-in-one)
```

**In `speckit.spex-deep-review.run.md` (line ~598):**
```
Deep review complete. To close out this feature:
  1. /speckit-spex-smoke-test    (walk through acceptance scenarios)
  2. /clear                      (free context for final gate)
  3. /speckit-spex-finish         (verify + merge/PR, all-in-one)
```

### Deliverable 4: Documentation updates

Update README.md and docs/help.md to mention the before_finish hook and smoke test integration (constitution requirement for documentation maintenance).

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Hook boilerplate diverges from spec-kit upstream pattern | Low | Medium | Copy verbatim from implement.md, note source in comments |
| After_finish hook conflicts with existing Phase 6 cleanup | Low | Low | Phase 6 removes `.spex-state`; after_finish flow-state hook handles `.spex-flow-state` (different file) |
| Extension reinstall overwrites manual extensions.yml edits | Medium | Low | Only modify extension.yml (source), not extensions.yml (generated) |
