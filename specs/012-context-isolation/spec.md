# Feature Specification: Context Isolation for Workflow Transitions

**Feature Branch**: `012-context-isolation`
**Created**: 2026-04-03
**Status**: Draft
**Input**: Add context isolation warnings and forked subagent execution for workflow transitions

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Context Clear Warnings in Manual Workflow (Priority: P1)

A developer using the manual spex workflow (not /spex:ship) completes the spec review phase and is about to start implementation. The system displays a clear recommendation to run `/clear` before proceeding, explaining that a fresh context gives the implementation stage a full window and that spec-kit resolves artifacts from the branch name automatically. The same warning appears after implementation completes, before running `/spex:review-code`, explaining that an unbiased reviewer should not carry context from the implementation process.

**Why this priority**: Simplest, highest-impact change. A one-line warning at two transition points builds healthy habits and immediately improves review quality by encouraging context separation.

**Independent Test**: Run `/spex:review-plan`, verify the context clear message appears at the end. Run `/speckit.implement`, verify the context clear message appears after implementation completes.

**Acceptance Scenarios**:

1. **Given** spec review (review-plan) completes, **When** the skill finishes, **Then** a message is displayed recommending `/clear` before `/speckit.implement`, explaining why (fresh context for implementation, spec-kit resolves from branch)
2. **Given** implementation (speckit.implement) completes, **When** the skill finishes, **Then** a message is displayed recommending `/clear` before `/spex:review-code` or `/spex:deep-review`, explaining why (unbiased review requires no implementation context)
3. **Given** the user ignores the warning and proceeds without clearing, **When** the next skill runs, **Then** it works normally (warnings are informational, not blocking)

---

### User Story 2 - Branch-Based Spec Resolution for Spex Skills (Priority: P1)

A developer runs `/clear` after implementation, then invokes `/spex:review-code`. Instead of scanning for specs and asking the user to pick one, the skill detects the current git branch (e.g., `012-context-isolation`), resolves the spec directory (`specs/012-context-isolation/`), and proceeds automatically. This enables review skills to work seamlessly after a context clear.

**Why this priority**: Without this, the context clear warning from US1 creates friction because `review-code`, `deep-review`, and `stamp` currently require manual spec selection. Branch-based resolution removes that friction.

**Independent Test**: Check out a feature branch, run `/clear`, then invoke `/spex:review-code`. Verify it finds the spec without prompting.

**Acceptance Scenarios**:

1. **Given** the user is on feature branch `012-context-isolation` and spec exists at `specs/012-context-isolation/spec.md`, **When** `/spex:review-code` is invoked without arguments, **Then** it resolves the spec from the branch name and proceeds without interactive selection
2. **Given** the user is on feature branch `012-context-isolation` and spec exists, **When** `/spex:deep-review` is invoked, **Then** it resolves the spec from the branch name
3. **Given** the user is on `main` branch (not a feature branch), **When** `/spex:review-code` is invoked, **Then** it falls back to the existing interactive spec selection behavior
4. **Given** the user is on a feature branch but no matching spec directory exists, **When** `/spex:review-code` is invoked, **Then** it falls back to interactive spec selection

---

### User Story 3 - Forked Subagent Stages in Ship Pipeline (Priority: P2)

A developer runs `/spex:ship` for an autonomous pipeline. The implementation stage (stage 6) and review-code stage (stage 7) run as forked subagents via `context: fork`, each with their own isolated context window. The ship orchestrator stays lightweight, tracking state and handling stage transitions. File-based artifacts (spec.md, plan.md, tasks.md, REVIEWERS.md) are the handoff mechanism between forked stages.

**Why this priority**: The ship pipeline runs all 9 stages in one session. By stage 6-7, context degradation is a real risk. Forking heavy stages provides automatic isolation without requiring user intervention.

**Independent Test**: Run `/spex:ship` with a brainstorm file. Observe that implementation and review stages run in isolated subagent contexts (visible in the UI as separate agent sessions). Verify the orchestrator's context stays small.

**Acceptance Scenarios**:

1. **Given** `/spex:ship` is running and reaches stage 6 (implement), **When** the stage executes, **Then** it runs as a forked subagent with `context: fork`, receiving only the spec/plan/tasks file paths as input
2. **Given** `/spex:ship` is running and reaches stage 7 (review-code), **When** the stage executes, **Then** it runs as a forked subagent with no implementation context carried from stage 6
3. **Given** a forked stage completes, **When** results return to the orchestrator, **Then** only a summary is returned (not the full exploration/implementation context)
4. **Given** a forked stage fails, **When** results return to the orchestrator, **Then** the failure is reported and the pipeline applies oversight decision logic as normal

---

### Edge Cases

- What happens when spec-kit's branch resolution fails (malformed branch name)? Fall back to interactive selection.
- What happens if a forked subagent exceeds its context window during implementation? The subagent handles this via its own auto-compaction, independent of the orchestrator.
- What happens when the user runs `/spex:review-code` with an explicit spec path argument? The argument takes precedence over branch-based resolution.
- What happens when the `review-code` skill is invoked from a `speckit.implement` overlay (superpowers trait)? Branch resolution still works because the branch hasn't changed.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The superpowers overlay for `speckit.plan` (which invokes `review-plan`) MUST display a context clear recommendation after the plan review completes, suggesting the user run `/clear` before `/speckit.implement`
- **FR-002**: The `speckit.implement` overlay MUST display a context clear recommendation after implementation completes, suggesting the user run `/clear` before `/spex:review-code`
- **FR-003**: Context clear recommendations MUST always display (not conditional on context size)
- **FR-004**: Context clear recommendations MUST be informational only (not blocking)
- **FR-005**: Context clear messages MUST explain WHY clearing is beneficial (fresh context for implementation, unbiased review)
- **FR-006**: Context clear messages MUST note that spec-kit resolves artifacts from the branch name, so no context is lost
- **FR-007**: `review-code`, `review-spec`, `deep-review`, and `verification-before-completion` (stamp) MUST resolve the spec directory from the current git branch using spec-kit's existing branch resolution via `check-prerequisites.sh` or `common.sh`
- **FR-008**: When branch-based spec resolution succeeds, spex review skills MUST skip the interactive spec selection prompt
- **FR-009**: When branch-based spec resolution fails (not on feature branch, no matching spec directory), spex review skills MUST fall back to existing interactive spec selection
- **FR-010**: Explicit spec path arguments MUST take precedence over branch-based resolution
- **FR-011**: The ship skill MUST run stage 6 (implement) and stage 7 (review-code) as forked subagents via `context: fork`
- **FR-012**: Forked stages in the ship pipeline MUST receive spec/plan/tasks file paths as input, not raw conversation context
- **FR-013**: The ship orchestrator MUST remain lightweight, receiving only summarized results from forked stages

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After spec review completes in a manual workflow, a context clear recommendation is visible to the user
- **SC-002**: After implementation completes in a manual workflow, a context clear recommendation is visible to the user
- **SC-003**: Running `/spex:review-code` on a feature branch after `/clear` resolves the spec automatically without user interaction
- **SC-004**: Running `/spex:ship` does not trigger auto-compaction in the orchestrator during stages 6-8 (forked stages handle their own context independently)
- **SC-005**: Deep review after forked execution produces findings across all 5 review dimensions (correctness, architecture, security, production-readiness, test-quality)

## Assumptions

- Spec-kit's `check-prerequisites.sh --json` and `common.sh` branch resolution are stable APIs that spex can depend on
- Claude Code's `context: fork` in skill frontmatter works for plugin skills (not just project/user skills)
- The `context: fork` mechanism properly isolates the subagent's context from the parent
- Users understand `/clear` (built-in Claude Code command, no documentation needed)
- The ship pipeline's state file (`.specify/.spex-ship-phase`) provides sufficient handoff state between forked stages

## Out of Scope

- Automatic context clearing (no programmatic `/clear` invocation; users decide)
- Context size monitoring or thresholds
- Compaction-based approaches (`/compact` is lossy and imprecise)
- Changes to spec-kit's branch resolution logic
- Session restart or re-invocation flows
