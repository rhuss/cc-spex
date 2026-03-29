# Research: Autonomous Full-Cycle Workflow (spex:yolo)

**Date:** 2026-03-29
**Feature:** 010-yolo-autonomous-workflow

## Decision 1: Skill Architecture

**Decision:** Single SKILL.md file with inline pipeline orchestration (no separate command file).

**Rationale:** The yolo skill is a self-contained orchestrator that chains existing skills. Unlike speckit commands (which are extended by trait overlays), yolo itself IS the trait-aware workflow. Adding a separate command file would create an unnecessary layer since no overlays need to append to it.

**Alternatives considered:**
- Command file + skill file: Rejected because yolo is not a speckit command, it's a spex skill. Overlays don't append to skills.
- Shell script orchestrator: Rejected because the pipeline needs Claude's judgment for autonomy decisions (when to pause, what to auto-fix).

## Decision 2: Skill-to-Skill Invocation Pattern

**Decision:** Use `{Skill: spex:skill-name}` references for quality-gate skills (review-spec, review-plan, review-code, deep-review). Use direct `/speckit.*` command invocation for speckit stages (specify, clarify, plan, tasks, implement).

**Rationale:** Existing codebase uses `{Skill:}` for spex skills and `/speckit.*` for speckit commands. Following the same pattern ensures consistency and proper overlay application (speckit commands get trait overlays applied).

**Alternatives considered:**
- All via `{Skill:}`: Rejected because speckit commands have overlay infrastructure that must be invoked through the command path.
- Direct tool calls: Rejected because it would bypass the skill/command system entirely.

## Decision 3: State File Format

**Decision:** JSON state file at `.specify/.spex-yolo-phase` with the following schema:

```json
{
  "stage": "implement",
  "stage_index": 6,
  "total_stages": 9,
  "autonomy": "balanced",
  "started_at": "2026-03-29T10:00:00Z",
  "retries": 0,
  "status": "running"
}
```

**Rationale:** Follows existing `.specify/` state file patterns. JSON matches `spex-traits.json` format. The `stage` field uses the skill/command name for readability. A separate `stage_index` provides numeric progress for status line scripts.

**Alternatives considered:**
- Plain text (like `.spex-phase`): Rejected because yolo needs more fields (autonomy, retries, timing).
- YAML: Rejected because the codebase uses JSON exclusively for machine-readable config.

## Decision 4: Argument Parsing Pattern

**Decision:** Parse flags in the skill's "Argument Parsing" section using the same pattern as `review-code` (flag extraction with remaining text as brainstorm path). Flags are boolean toggles with `--no-*` negation.

**Rationale:** The `review-code` skill already handles `--no-external`, `--coderabbit`, etc. Reusing the same parsing pattern ensures consistency and reduces cognitive load.

**Alternatives considered:**
- Shell script for argument parsing: Rejected because skills run in Claude's context, not as shell scripts.
- Configuration file for defaults: Already used via `.specify/spex-traits.json` for external_tools defaults.

## Decision 5: Autonomy Level Implementation

**Decision:** Autonomy level is a parameter passed to review stages that controls their pause/continue behavior. The yolo skill evaluates review findings and decides whether to auto-fix or pause based on the level.

- `cautious`: Pause on every finding, present to user
- `balanced`: Auto-fix findings where the fix is unambiguous (formatting, style, minor issues). Pause when the fix requires judgment (architecture, design, ambiguous requirements).
- `autopilot`: Auto-fix everything. Only pause on genuine blockers (compilation errors, missing dependencies, test failures that can't be auto-resolved).

**Rationale:** The classification happens at the yolo skill level, not inside individual review skills. This keeps review skills unchanged and makes the autonomy decision transparent.

**Alternatives considered:**
- Push autonomy logic into each review skill: Rejected because it would require modifying 4+ existing skills.
- Binary auto-fix/manual: Rejected because the three-level model matches real-world developer needs better.

## Decision 6: Retry Mechanism

**Decision:** Max 2 retry cycles per review stage. After applying fixes, re-run the same review. If findings persist after 2 cycles, pause and present to user regardless of autonomy level.

**Rationale:** Prevents infinite fix loops. Two cycles is enough for most auto-fixable issues (first pass catches obvious issues, second pass catches issues introduced by fixes).

**Alternatives considered:**
- Single retry: Too aggressive, some fixes reveal secondary issues.
- Three or more retries: Diminishing returns; if 2 cycles can't fix it, human judgment is needed.

## Decision 7: Pipeline Stage Ordering

**Decision:** Fixed 9-stage pipeline: specify, clarify, review-spec, plan, review-plan, tasks, implement, deep-review, verify.

**Rationale:** This mirrors the existing manual workflow documented in the superpowers trait overlays. The ordering ensures each stage has the artifacts it needs from previous stages.

**Alternatives considered:**
- Configurable stage ordering: Over-engineered for the use case. The order is logically determined by artifact dependencies.
- Parallel stages: Not feasible because each stage depends on the previous stage's output.

## Decision 8: Worktree Integration

**Decision:** The yolo skill does NOT handle worktree creation directly. Instead, it invokes `/speckit.specify` which, with the worktrees trait enabled, creates the worktree via its overlay. Subsequent stages run in whatever directory the session is in after specify completes.

**Rationale:** The worktrees trait already handles this through its overlay on `speckit.specify`. Duplicating this logic in yolo would violate the trait composability principle.

**Alternatives considered:**
- Yolo manages worktree directly: Rejected because it would bypass the overlay system and break trait composability.

## Decision 9: Trait Registration

**Decision:** Yolo does NOT need to be registered as a trait in `spex-traits.json`. It is a standalone skill that requires other traits (superpowers, deep-review) but is always available when the spex plugin is installed.

**Rationale:** Yolo is a workflow orchestrator, not a behavioral modifier. Traits modify how existing commands behave (via overlays). Yolo is a new entry point that composes existing behaviors.

**Alternatives considered:**
- Register as a trait: Rejected because yolo has no overlays to apply to existing commands. It's a skill, not a trait.

## Decision 10: Resume and Start-From

**Decision:** Support explicit `--resume` (reads state file, continues from next uncompleted stage) and `--start-from <stage>` (skips to a named stage, assumes prior artifacts exist).

**Rationale:** A 9-stage pipeline is expensive to restart from scratch. Explicit flags give the user control over resumption without surprising auto-resume behavior.

**Alternatives considered:**
- Auto-resume on invocation: Rejected because implicit behavior is surprising and may restart in a stale context.
- No resume at all: Rejected after user feedback that restarting a 9-stage pipeline from scratch is wasteful.

## Decision 11: PR Creation

**Decision:** When `--create-pr` is specified, use `gh pr create` after verify succeeds. Target `upstream` if configured, otherwise `origin`. PR body summarizes the feature and links to the spec.

**Rationale:** Follows the pattern established in the superpowers overlay for `speckit.plan` (which also asks about PR creation).

**Alternatives considered:**
- Always create PR: Rejected because some developers prefer local review first.
- Use GitHub MCP: `gh` CLI is simpler and already used in the codebase.
