# Review Summary: Autonomous Full-Cycle Workflow (spex:yolo)

**Spec:** specs/010-yolo-autonomous-workflow/spec.md | **Plan:** specs/010-yolo-autonomous-workflow/plan.md
**Generated:** 2026-03-29

---

## Executive Summary

The spex plugin currently requires developers to manually invoke 8 or more slash commands in sequence to take a feature from brainstorm to verified implementation. Each command requires confirmation, context switching, and awareness of which command comes next. This creates friction, especially for well-scoped features where the workflow is predictable.

The `spex:yolo` skill introduces a single entry point (`/spex:yolo`) that chains the entire pipeline autonomously: specify, clarify, review-spec, plan, review-plan, tasks, implement, deep-review, and verify. The developer points it at a brainstorm document and chooses an autonomy level that controls how much human oversight the pipeline requires.

Three autonomy levels serve different situations. "Cautious" stops at every review finding for developers working on critical features or learning the workflow. "Balanced" (the default) auto-fixes straightforward issues like formatting and style while pausing on architectural or ambiguous questions that need human judgment. "Autopilot" fixes everything it can and only stops when genuinely blocked, suitable for well-scoped features after thorough brainstorming.

The skill tracks its progress in a JSON state file (`.specify/.spex-yolo-phase`) that records the current stage, retry count, and autonomy level. This enables status line integration so developers can see pipeline progress at a glance.

The implementation is deliberately minimal. It is a single Markdown skill file that orchestrates existing skills and commands. It adds no new hooks, overlays, or traits. It requires both the `superpowers` and `deep-review` traits to be enabled, ensuring all quality gates remain active. External review tool flags (CodeRabbit, Copilot) pass through to the deep-review stage, and PR creation is optional via `--create-pr`.

## Review Recipe (30 minutes)

### Step 1: Understand the problem (5 min)
- Read the Executive Summary above
- Skim `spec.md` User Story 1 (the core value proposition)
- Ask yourself: Does autonomous chaining add real value, or does manual control matter?

### Step 2: Check critical references (10 min)
- Review each item in the **Critical References** table below
- The autonomy classification logic and retry mechanism are the most novel parts
- Check whether the three autonomy levels are well-defined enough to implement

### Step 3: Evaluate technical decisions (8 min)
- Review the **Technical Decisions** section below
- Key question: Is a single SKILL.md the right architecture, or will it become unwieldy?
- Consider whether the "no new trait" decision is correct

### Step 4: Validate coverage and risks (5 min)
- Check the **Risk Areas** table for context window and retry loop concerns
- Verify the scope boundaries make sense (no resume across sessions)

### Step 5: Complete the checklist (2 min)
- Work through the **Reviewer Checklist** below

## PR Contents

This spec PR includes the following artifacts:

| Artifact | Description |
|----------|-------------|
| `spec.md` | Defines the spex:yolo skill with 5 user stories, 13 functional requirements, and 6 edge cases |
| `plan.md` | Implementation approach: single skill file, JSON state tracking, delegated orchestration |
| `tasks.md` | 29 tasks across 9 phases, organized by user story with MVP scope at Phase 3 |
| `research.md` | 10 design decisions with alternatives and rationale |
| `data-model.md` | PipelineState, AutonomyLevel, and PipelineStage entity definitions |
| `contracts/skill-interface.md` | CLI interface contract with flags, preconditions, and error conditions |
| `quickstart.md` | Usage examples for each autonomy level and flag combination |
| `REVIEWERS.md` | This file |

## Technical Decisions

### Single SKILL.md vs. Command + Skill Split
- **Chosen approach:** Single `spex/skills/yolo/SKILL.md` containing all orchestration logic
- **Alternatives considered:**
  - Command file + skill file: Rejected because yolo is not a speckit command. Overlays don't append to skills, so the command file would serve no purpose.
  - Shell script orchestrator: Rejected because autonomy decisions require Claude's judgment (classifying findings as ambiguous vs. clear), which can't be done in Bash.
- **Trade-off:** Simpler structure (one file) at the cost of a potentially large skill file
- **Reviewer question:** Will a single SKILL.md become too large? The 29 tasks all write sections into one file.

### Yolo as a Skill, Not a Trait
- **Chosen approach:** `spex:yolo` is a standalone skill, not registered as a trait in `spex-traits.json`
- **Alternatives considered:**
  - Register as trait: Rejected because traits modify existing command behavior via overlays. Yolo is a new entry point that composes existing behaviors without modifying them.
- **Trade-off:** Yolo is always available when the plugin is installed, no enable/disable needed. But it can't be discovered via `/spex:traits list`.

### Autonomy Classification at Yolo Level
- **Chosen approach:** The yolo skill classifies review findings (unambiguous/ambiguous/blocker) rather than pushing this logic into individual review skills
- **Alternatives considered:**
  - Push autonomy into review skills: Rejected because it would require modifying 4+ existing skills and would couple them to the yolo workflow.
- **Trade-off:** All classification logic is centralized (easier to tune), but review skills don't benefit from autonomy when invoked standalone.

### Resume and Start-From Support
- **Chosen approach:** `--resume` reads the state file and continues from the next uncompleted stage. `--start-from <stage>` skips to any named stage.
- **Alternatives considered:**
  - Auto-resume on invocation: Rejected because implicit behavior is surprising and may restart in a stale context.
  - No resume at all: Rejected after user feedback that restarting a 9-stage pipeline from scratch is wasteful.
- **Trade-off:** Explicit flags give control, but resume assumes prior context is still valid (same branch, artifacts exist).
- **Reviewer question:** Should `--resume` validate that artifacts from completed stages still exist, or trust the state file?

## Critical References

| Reference | Why it needs attention |
|-----------|----------------------|
| `spec.md` FR-006, FR-007: Auto-fix and pause logic | Defines when the pipeline pauses vs. continues. The boundary between "unambiguous" and "ambiguous" is inherently subjective. Reviewers should assess whether the classification criteria are implementable. |
| `spec.md` FR-009: State file format | The JSON schema for `.spex-yolo-phase` is a new interface contract. Other tools (status line scripts) will depend on it. |
| `spec.md` Edge case: max retries | The "2 retry cycles" limit affects user experience. Too few retries may cause unnecessary pauses; too many may create loops. |
| `data-model.md` AutonomyLevel table | The mapping of finding types to autonomy behaviors is the core decision logic. |
| `plan.md` Project Structure | Only two files are created. Reviewers should verify this is sufficient. |

## Reviewer Checklist

### Verify
- [ ] All 9 pipeline stages are correctly ordered and each has a clear invocation method
- [ ] The autonomy level definitions are specific enough to implement consistently
- [ ] External tool flag pass-through follows the same resolution pattern as review-code
- [ ] The state file JSON schema contains all fields needed for status line display
- [ ] The "max 2 retries" limit is documented in both spec and data model

### Question
- [ ] Is the single SKILL.md approach sustainable, or should sections be split into helper files?
- [ ] Is the `--start-from` implementation sufficient, or does it need artifact validation beyond warnings?
- [ ] Is "no cross-session resume" acceptable, or do users expect to resume after Ctrl+C?

### Watch out for
- [ ] Context window exhaustion: running 9 stages in one session may exceed limits for large features
- [ ] The autonomy classification ("unambiguous" vs "ambiguous") is subjective and may be inconsistent across runs
- [ ] State file cleanup: if the pipeline completes successfully but cleanup fails, stale state files may confuse future runs

## Scope Boundaries
- **In scope:** Single-session autonomous pipeline, 3 autonomy levels, state tracking, external tool flag pass-through, optional PR creation, `--resume` from interrupted pipelines, `--start-from` for partial runs
- **Out of scope:** Custom stage ordering, parallelizing stages, new trait registration, automated test suite
- **Why these boundaries:** MVP focuses on the core automation value. Resume and partial runs add complexity with unclear demand. The skill is pure Markdown with no test infrastructure.

## Naming and Schema Decisions

| Item | Name | Context |
|------|------|---------|
| Skill name | `spex:yolo` | Follows `spex:` prefix convention. "yolo" is memorable and captures the "just do everything" intent. |
| State file | `.specify/.spex-yolo-phase` | Follows existing `.spex-phase` naming pattern, scoped to yolo. |
| Autonomy flag | `--autonomy` | Full word, not abbreviated. Values: `cautious`, `balanced`, `autopilot`. |
| PR flag | `--create-pr` | Matches common CLI conventions. |

**State file schema (key fields):**
```json
{
  "stage": "string (stage name)",
  "stage_index": "int (0-8)",
  "autonomy": "string (cautious|balanced|autopilot)",
  "status": "string (running|paused|completed|failed)",
  "retries": "int (0-2)"
}
```

## Risk Areas

| Risk | Impact | Mitigation |
|------|--------|------------|
| Context window exhaustion during 9-stage pipeline | High | Each stage delegates to existing skills which manage their own context. Large features may need `autopilot` to minimize back-and-forth. |
| Inconsistent autonomy classification across runs | Med | Classification criteria are documented in the skill. Users can override with `cautious` for critical features. |
| Stale state file after interruption | Low | State file is informational only (no auto-resume). Can be manually deleted. |
| Single SKILL.md becomes too large to maintain | Med | If the file exceeds ~500 lines, consider splitting stage orchestration into per-stage sections or helper files. |
| Existing skill behavior changes when invoked through yolo | Med | Yolo delegates to existing skills/commands unchanged. Acceptance test SC-005 explicitly verifies identical behavior. |

---
*Share this with reviewers. Full context in linked spec and plan.*
