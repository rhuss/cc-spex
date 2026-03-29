# Implementation Plan: Deep-Review Trait

**Branch**: `009-deep-review-trait` | **Date**: 2026-03-28 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/009-deep-review-trait/spec.md`

## Summary

The deep-review trait adds multi-perspective code review with an autonomous fix loop to the spex plugin. When enabled, `spex:review-code` runs five specialized review agents (correctness, architecture, security, production-readiness, test-quality) after standard spec compliance passes. Critical and Important findings trigger an autonomous fix loop (up to 3 rounds). All findings are documented in `review-findings.md`. The trait integrates with the teams trait for parallel agent execution and optionally includes CodeRabbit as an external review perspective.

## Technical Context

**Language/Version**: Bash (POSIX-compatible), Markdown, Python 3 (hooks)
**Primary Dependencies**: `jq` (JSON parsing), `specify` CLI (spec-kit), spex plugin infrastructure, Claude Code Agent Teams (parallel mode)
**Storage**: File-based (`.specify/spex-traits.json` for config, Markdown for artifacts)
**Testing**: Manual verification via `make reinstall` + Claude Code session testing
**Target Platform**: macOS/Linux (Claude Code CLI)
**Project Type**: CLI plugin trait (spex overlay + skill)
**Performance Goals**: <10 min for <2000 LOC sequential review (SC-003), 2x speedup with teams (SC-004)
**Constraints**: Overlay files <30 lines (constitution), skills self-contained, no compiled artifacts
**Scale/Scope**: Single trait, ~5-7 new/modified files, 5 review agent prompt templates embedded in skill

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-Guided Development | PASS | Full SDD workflow: specify, clarify, review-spec, plan |
| II. Overlay Delegation | PASS | Overlay will be <30 lines, delegates to `{Skill: spex:deep-review}` |
| III. Trait Composability | PASS | Independent of superpowers (FR-003). No modifications to other trait overlays. Combines with teams trait via trait detection, not cross-overlay coupling |
| IV. Quality Gates | PASS | Review gates active via superpowers trait |
| V. Naming Discipline | PASS | Trait: `deep-review`. Skill: `spex:deep-review`. Sentinel: `<!-- SPEX-TRAIT:deep-review -->` |
| VI. Skill Autonomy | PASS | Dedicated `deep-review` skill handles orchestration. `review-code` skill gains one trait-detection branch that delegates via `{Skill: spex:deep-review}` |

No violations. Complexity Tracking table not needed.

## Project Structure

### Documentation (this feature)

```text
specs/009-deep-review-trait/
├── plan.md              # This file
├── research.md          # Phase 0: design decisions
├── data-model.md        # Phase 1: entities and state
├── quickstart.md        # Phase 1: usage guide
└── tasks.md             # Phase 2: task breakdown
```

### Source Code (repository root)

```text
spex/
├── overlays/
│   └── deep-review/
│       └── commands/
│           └── speckit.implement.append.md   # Overlay: note deep-review enhances review-code
├── skills/
│   ├── deep-review/
│   │   └── SKILL.md                          # NEW: orchestration, agent prompts, fix loop
│   └── review-code/
│       └── SKILL.md                          # MODIFIED: add trait detection, delegate
├── scripts/
│   └── spex-traits.sh                        # MODIFIED: register deep-review in VALID_TRAITS
└── docs/
    └── (help updates if needed)
```

**Structure Decision**: Follows existing trait pattern. One new skill directory (`deep-review`), one new overlay directory, two modified files (`review-code/SKILL.md`, `spex-traits.sh`). No new scripts or compiled artifacts.

## Design Decisions

### D1: Integration Point - Skill-Level Trait Detection

The deep-review enhancement is triggered inside the `review-code` skill via trait config detection, not solely through overlays. This is necessary because:
- `review-code` can be invoked manually (`/spex:review-code`) without going through any command overlay
- The enhancement must work regardless of invocation path (FR-003)
- The overlay exists for consistency with the trait system but the behavioral trigger is in the skill

The `review-code` skill will:
1. Run standard spec compliance check (Stage 1)
2. Check `.specify/spex-traits.json` for `deep-review` enabled
3. If enabled and Stage 1 passes (or no spec exists): invoke `{Skill: spex:deep-review}`
4. If not enabled: continue with standard review behavior

### D2: Agent Prompt Architecture

All five review agent prompts are embedded in `deep-review/SKILL.md` as structured sections. This follows the existing pattern (one SKILL.md per skill, no auxiliary files) and keeps prompts co-located with the orchestration logic that dispatches them.

Each agent prompt template includes:
- Role/scope gate (what the agent IS and IS NOT responsible for)
- Anti-sycophancy instructions (FR-080, FR-081)
- Distrust instruction (FR-021)
- Confidence scoring rules (FR-021, including lowered threshold for Critical)
- Structured output format for findings (severity, confidence, file:line, description, fix)
- Self-verification checklist
- Language-aware checklist adaptation section (FR-023)

### D3: Sequential vs. Parallel Dispatch

The deep-review skill checks for the `teams` trait:
- **Teams enabled**: Dispatch all 5 agents via `Agent` tool calls in a single message (parallel). External tools (CodeRabbit, Copilot) run as additional parallel tasks via `Bash`.
- **Teams disabled**: Dispatch agents sequentially in the main conversation, one at a time. External tools run alongside internal agents.

In both modes, each agent operates in isolated context (FR-022) via the Agent tool's fresh context behavior.

### D4: Findings Consolidation Algorithm

After all agents complete:
1. Parse each agent's structured output into a findings list
2. Normalize findings to common schema: `{severity, confidence, file, line_start, line_end, category, description, rationale, fix, source_agent}`
3. Sort by file path, then line number
4. Deduplicate: for each pair of findings matching on (file + overlapping line range + category), keep the one with more detail, note both sources
5. Classify gate outcome: any Critical or Important remaining = gate fail

### D5: Fix Loop Flow

```
Round 1:
  1. Collect all Critical + Important findings
  2. Main agent applies fixes (top-to-bottom per file, FR-046)
  3. Stage changes
  4. Re-dispatch review agents on modified files only (FR-013 narrowed scope)
  5. Merge new findings
  6. If no Critical/Important: PASS → write review-findings.md
  7. If Critical/Important remain: continue to Round 2

Round 2-3: Same as Round 1

After Round 3 with remaining issues:
  FAIL → write review-findings.md with remaining findings, report to user
```

### D6: Gate Behavior by Context (FR-044)

The deep-review skill receives context about how it was invoked:
- **From superpowers quality gate**: Gate fail blocks completion. The skill returns a failure signal that prevents proceeding to verification.
- **From manual `/spex:review-code`**: Gate fail is advisory. Findings are reported, user decides next steps. No blocking.

The invocation context is determined by checking whether the call chain includes the superpowers implement overlay.

### D7: Overlay Design

The deep-review overlay appends to `speckit.implement.md` with a minimal note:

```markdown
<!-- SPEX-TRAIT:deep-review -->
## Deep Review Enhancement

When `deep-review` trait is active, `spex:review-code` automatically runs
multi-perspective review agents after spec compliance passes. No additional
commands needed. See {Skill: spex:deep-review} for details.
```

This is informational (helps users understand the flow) and consistent with the overlay pattern. The actual behavior trigger is in the review-code skill (D1).

## Complexity Tracking

> No constitution violations to justify.
