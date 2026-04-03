# Implementation Plan: Context Isolation for Workflow Transitions

**Branch**: `012-context-isolation` | **Date**: 2026-04-03 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/012-context-isolation/spec.md`

## Summary

Add context isolation at two workflow transition points: (1) context clear warnings in overlay files for the manual workflow, (2) branch-based spec resolution in spex review skills so they work after `/clear`, and (3) `context: fork` for heavy stages in the ship pipeline. These three user stories are independently deliverable.

## Technical Context

**Language/Version**: Bash (POSIX-compatible), Markdown, Python 3 (hooks) + `jq` (JSON parsing)
**Primary Dependencies**: `specify` CLI (spec-kit), Claude Code skill/subagent system, `check-prerequisites.sh`
**Storage**: File-based (`.specify/.spex-ship-phase` for state, Markdown for artifacts)
**Testing**: `make test-install` (integration test), manual Claude Code session testing
**Target Platform**: Claude Code plugin (cross-platform)
**Project Type**: CLI plugin (Markdown skills + Bash scripts)
**Performance Goals**: N/A (workflow plugin)
**Constraints**: Overlays MUST be under 30 lines (constitution Principle II)
**Scale/Scope**: 4 skill files modified, 2 overlay files modified, 1 skill restructured

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-Guided Development | PASS | This feature follows the full SDD workflow |
| II. Overlay Delegation | PASS | Context warnings go in overlays (under 30 lines), not inlined |
| III. Trait Composability | PASS | Changes are orthogonal to existing traits |
| IV. Quality Gates | PASS | Adds context awareness to existing quality gates |
| V. Naming Discipline | PASS | Uses established `spex:` prefix and `speckit.*` conventions |
| VI. Skill Autonomy | PASS | Branch resolution added to each skill independently, no cross-skill coupling |

## Project Structure

### Documentation (this feature)

```text
specs/012-context-isolation/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (files to modify)

```text
spex/
├── overlays/
│   └── superpowers/
│       └── commands/
│           ├── speckit.plan.append.md      # Add context clear warning after plan review
│           └── speckit.implement.append.md  # Add context clear warning after implementation
├── skills/
│   ├── review-code/SKILL.md               # Add branch-based spec resolution
│   ├── review-spec/SKILL.md               # Add branch-based spec resolution
│   ├── deep-review/SKILL.md               # Add branch-based spec resolution
│   ├── verification-before-completion/SKILL.md  # Add branch-based spec resolution
│   └── ship/SKILL.md                      # Add context: fork for stages 6 and 7
```

**Structure Decision**: No new files or directories needed. All changes modify existing skills and overlays.

## Implementation Phases

### Phase 1: Context Clear Warnings (US1)

**Goal**: Add informational `/clear` recommendations at two transition points.

**Changes**:

1. **`spex/overlays/superpowers/commands/speckit.plan.append.md`**: Add a section after the "Commit and PR" block with the context clear message. The overlay already has review-plan invocation; append the warning after the plan review completes.

   Warning text (approximate):
   > **Context management**: Before starting implementation, consider running `/clear` to give the implementation stage a fresh context window. Spec-kit resolves all artifacts (spec, plan, tasks) from the branch name automatically, so no context is lost.

2. **`spex/overlays/superpowers/commands/speckit.implement.append.md`**: Add a section after the "After implementation completes" block with the context clear message.

   Warning text (approximate):
   > **Context management**: Before running code review, consider running `/clear` to ensure an unbiased review. The reviewer should evaluate the code independently, without carrying context from the implementation process. Spec-kit resolves all artifacts from the branch name automatically.

**Constraint**: Each addition must stay under 30 lines (overlay delegation principle). These are 5-6 lines each.

### Phase 2: Branch-Based Spec Resolution (US2)

**Goal**: Update spex review skills to resolve specs from the git branch name.

**Changes**: In each of the 4 skills (`review-code`, `review-spec`, `deep-review`, `verification-before-completion`), replace the "Spec Selection" section with branch-aware resolution:

```markdown
## Spec Selection

If a spec path is provided as an argument, use it directly.

Otherwise, attempt branch-based resolution:

\`\`\`bash
.specify/scripts/bash/check-prerequisites.sh --json --paths-only 2>/dev/null
\`\`\`

If this succeeds (outputs JSON with FEATURE_SPEC), use the resolved spec path.

If this fails (not on a feature branch, no matching spec directory), fall back to
interactive selection:

\`\`\`bash
fd -t f "spec.md" specs/ 2>/dev/null | head -20
\`\`\`
```

**Pattern**: The resolution logic is identical across all 4 skills. Each skill's "Spec Selection" section is replaced with the same pattern. This is acceptable (not duplication) because each skill is independently deployable and self-contained per constitution Principle VI.

### Phase 3: Forked Subagent Stages in Ship (US3)

**Goal**: Run implementation and review-code stages as forked subagents in the ship pipeline.

**Changes**: Modify `spex/skills/ship/SKILL.md`:

1. **Stage 6 (implement)**: Instead of invoking `/speckit.implement` inline, the orchestrator invokes a forked skill call. The ship skill's stage 6 instructions change from "Invoke `/speckit.implement`" to invoking the implement stage with `context: fork` via the Agent tool or by creating a dedicated ship-implement subskill.

2. **Stage 7 (review-code)**: Same pattern. The orchestrator invokes the review-code stage in a forked context so it has no implementation history.

3. **Handoff mechanism**: The orchestrator passes spec/plan/tasks paths as arguments to the forked stages. The forked stages read these files fresh (they have no conversation history). Results return as summaries to the orchestrator.

**Design decision**: Rather than adding `context: fork` to the main skill frontmatter (which would fork the entire ship pipeline), the ship skill uses the Agent tool to spawn isolated subagents for specific stages. This keeps the orchestrator inline while forking only the heavy stages.

**Risk**: Plugin skills may have limitations with `context: fork` or Agent tool spawning. This phase should be validated with a manual prototype before full implementation.

## Complexity Tracking

No constitution violations. All changes follow established patterns.
