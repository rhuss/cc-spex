# Feature Specification: Autonomous Full-Cycle Workflow (spex:ship)

**Feature Branch**: `010-yolo-autonomous-workflow`
**Created**: 2026-03-29
**Status**: Draft
**Input**: Brainstorm document `brainstorm/05-yolo-autonomous-workflow.md`

## User Scenarios & Testing

### User Story 1 - Run Full Pipeline After Brainstorm (Priority: P1)

A developer has completed a brainstorming session and has a brainstorm document in `brainstorm/`. They invoke `/spex:ship` to run the entire spex workflow autonomously, from specification through implementation and review, without manually triggering each stage.

**Why this priority**: This is the core value proposition. Without autonomous chaining, users must manually invoke 8+ commands with confirmation between each step.

**Independent Test**: Can be tested by creating a brainstorm document and running `/spex:ship brainstorm/05-test-feature.md`. The skill should execute specify, clarify, review-spec, plan, review-plan, tasks, implement, deep-review, and verify in sequence, producing a working implementation.

**Acceptance Scenarios**:

1. **Given** a brainstorm document exists at `brainstorm/05-yolo-autonomous-workflow.md` and both `superpowers` and `deep-review` traits are enabled, **When** the user runs `/spex:ship brainstorm/05-yolo-autonomous-workflow.md`, **Then** the skill executes the full pipeline: specify, clarify, review-spec, plan, review-plan, tasks, implement, deep-review, verify.
2. **Given** the pipeline is running in `smart` ask mode, **When** a review stage finds a clear formatting issue, **Then** the skill auto-fixes it and re-runs the review without stopping.
3. **Given** the pipeline is running in `smart` ask mode, **When** a review stage finds an ambiguous architectural issue, **Then** the skill pauses and presents the finding to the user for guidance.
4. **Given** the user answers a blocking question, **Then** the pipeline automatically resumes from where it paused.

---

### User Story 2 - Control Ask Level (Priority: P2)

A developer wants to control how aggressively the pipeline auto-fixes issues. They choose between `always` (stop at every finding), `smart` (auto-fix clear issues, stop when uncertain), and `never` (fix everything, stop only on genuine blockers).

**Why this priority**: Different situations call for different levels of autonomy. A critical feature needs cautious oversight; a well-scoped feature after thorough brainstorming can run on autopilot.

**Independent Test**: Run `/spex:ship --ask always` and verify it stops at each review finding. Run `/spex:ship --ask never` and verify it only stops on genuine blockers.

**Acceptance Scenarios**:

1. **Given** the user invokes `/spex:ship --ask always`, **When** review-spec finds any issue (even minor), **Then** the pipeline stops and presents the finding before proceeding.
2. **Given** the user invokes `/spex:ship --ask never`, **When** deep-review finds fixable issues, **Then** the skill auto-fixes all of them and only stops if implementation is genuinely blocked.
3. **Given** no `--ask` flag is provided, **Then** the default `smart` mode is used.

---

### User Story 3 - Control External Review Tools (Priority: P2)

A developer wants to skip or force specific external review tools (CodeRabbit, Copilot) during the deep-review stage of the pipeline.

**Why this priority**: External tools may not be configured, may cost money, or may not be appropriate for all features.

**Independent Test**: Run `/spex:ship --no-coderabbit` and verify CodeRabbit is skipped during deep-review. Run `/spex:ship --coderabbit` and verify CodeRabbit is explicitly included.

**Acceptance Scenarios**:

1. **Given** the user invokes `/spex:ship --no-external`, **When** the pipeline reaches deep-review, **Then** only internal review perspectives run (no CodeRabbit, no Copilot).
2. **Given** the user invokes `/spex:ship --coderabbit`, **When** CodeRabbit auth check fails, **Then** the pipeline stops at startup with a clear error message before any work begins.
3. **Given** the user invokes `/spex:ship` without review flags, **Then** the deep-review trait's default configuration determines which external tools run.

---

### User Story 4 - Worktree Isolation (Priority: P3)

A developer with the worktrees trait enabled runs `/spex:ship`. The specify stage creates a worktree as usual, and the entire remaining pipeline runs inside that worktree.

**Why this priority**: Worktree isolation is an existing trait behavior. Ship must integrate correctly with it but does not change how worktrees work.

**Independent Test**: Enable worktrees trait, run `/spex:ship`. Verify specify creates the worktree and subsequent stages run inside it.

**Acceptance Scenarios**:

1. **Given** the worktrees trait is enabled, **When** `/spex:ship` runs, **Then** specify creates the feature branch and worktree, and plan, tasks, implement, and review stages all execute inside the worktree.
2. **Given** the worktrees trait is disabled, **When** `/spex:ship` runs, **Then** all stages execute in the current working directory on the feature branch.

---

### User Story 5 - Optional PR Creation (Priority: P3)

A developer wants the pipeline to create a pull request after successful completion.

**Why this priority**: PR creation is a common final step but should remain opt-in since some developers prefer to review locally first.

**Independent Test**: Run `/spex:ship --create-pr` and verify a PR is created after verify succeeds.

**Acceptance Scenarios**:

1. **Given** the user invokes `/spex:ship --create-pr`, **When** all pipeline stages succeed, **Then** a pull request is created for the feature branch.
2. **Given** the user invokes `/spex:ship` without `--create-pr`, **When** all stages succeed, **Then** no PR is created and the user is informed of successful completion.

---

### Edge Cases

- What happens when the brainstorm document cannot be found? The skill fails with a clear error listing the expected location and available brainstorm files.
- What happens when a stage fails after max retries (2 cycles)? The pipeline stops, presents all findings, and asks the user for guidance. The user's response triggers automatic resume.
- What happens when the user interrupts the pipeline (Ctrl+C)? The state file (`.specify/.spex-ship-phase`) remains with the last completed stage. The user can resume with `/spex:ship --resume`.
- What happens when the user runs `--resume` but no state file exists? The skill fails with a clear error: "No interrupted pipeline found. Start a new pipeline with `/spex:ship <brainstorm-file>`."
- What happens when the user runs `--start-from` with an invalid stage name? The skill fails listing all valid stage names.
- What happens when `superpowers` or `deep-review` trait is not enabled? The skill fails at startup with a message listing the missing traits and how to enable them (`/spex:traits enable superpowers deep-review`).
- What happens when an external tool (CodeRabbit) is explicitly requested but not authenticated? The skill fails at startup before any pipeline work begins.
- What happens when the worktree is dirty before specify? The skill warns and asks the user to commit or stash changes before proceeding.

## Requirements

### Functional Requirements

- **FR-001**: System MUST validate that `superpowers` and `deep-review` traits are enabled before starting the pipeline
- **FR-002**: System MUST accept a brainstorm document path as input, or auto-detect the latest brainstorm file in `brainstorm/` by highest number prefix
- **FR-003**: System MUST execute the pipeline stages in order: specify, clarify, review-spec, plan, review-plan, tasks, implement, deep-review, verify
- **FR-004**: System MUST support three ask levels (`always`, `smart`, `never`) controlled via `--ask` flag, defaulting to `smart`
- **FR-005**: System MUST pass review tool flags (`--no-external`, `--no-coderabbit`, `--no-copilot`, `--external`, `--coderabbit`, `--copilot`) through to the deep-review stage
- **FR-006**: System MUST auto-fix review findings according to the selected ask level and re-run the review (max 2 retry cycles per stage)
- **FR-007**: System MUST pause and present findings to the user when the AI is uncertain about the correct fix (in `smart` mode) or when any finding is detected (in `always` mode)
- **FR-008**: System MUST automatically resume the pipeline after the user answers a blocking question
- **FR-009**: System MUST write current pipeline state to `.specify/.spex-ship-phase` as JSON for status line integration
- **FR-010**: System MUST support a `--create-pr` flag to create a pull request after successful pipeline completion
- **FR-011**: System MUST validate external tool authentication at startup when external tools are explicitly requested
- **FR-012**: System MUST produce full verbose output from each stage so the user can follow progress in real time
- **FR-013**: System MUST integrate with the worktrees trait: specify creates the worktree, subsequent stages run inside it
- **FR-014**: System MUST support a `--resume` flag that reads `.specify/.spex-ship-phase`, validates the state file exists and contains a valid interrupted pipeline, and resumes execution from the next uncompleted stage
- **FR-015**: System MUST support a `--start-from <stage>` flag that skips all stages before the named stage, validates the stage name is one of the 9 defined stages, and begins execution from that stage (assumes prior artifacts exist)

### Key Entities

- **Pipeline State**: Tracks current stage, total stages, ask level, start time, retry count. Persisted to `.specify/.spex-ship-phase` as JSON.
- **Ask Level**: One of `always`, `smart`, `never`. Determines when the pipeline pauses for human input.
- **Brainstorm Document**: A markdown file in `brainstorm/` containing the feature description and decisions from the brainstorming session.

## Success Criteria

### Measurable Outcomes

- **SC-001**: A well-scoped feature (under 10 tasks) completes the full pipeline in `never` mode without any human intervention
- **SC-002**: In `smart` mode, the pipeline auto-fixes at least 80% of review findings without stopping
- **SC-003**: The pipeline correctly identifies and pauses on genuinely ambiguous issues that require human judgment
- **SC-004**: The status file (`.specify/.spex-ship-phase`) accurately reflects the current pipeline state at all times during execution
- **SC-005**: All existing trait behaviors (superpowers quality gates, worktree creation, deep-review dispatch) function identically when invoked through ship vs. manual invocation

## Clarifications

### Session 2026-03-29

- Q: What should be explicitly out of scope? → A: Exclude custom stage ordering, parallelizing stages, and new trait registration. Include `--resume` and `--start-from` as in-scope features (FR-014, FR-015).

## Out of Scope

- **Custom stage ordering**: The 9 stages always run in the same fixed order. No way to reorder them.
- **Parallelizing stages**: Stages run sequentially. No concurrent execution of stages.
- **New trait registration**: Ship is a skill, not a trait. It has no overlays and does not appear in `/spex:traits list`.

## Assumptions

- The brainstorm document contains a sufficiently detailed feature description for the specify stage to produce a quality spec
- The `specify` CLI and all dependent scripts are installed and functional (verified by `spex:init`)
- External review tools (CodeRabbit, Copilot) are optional and the pipeline gracefully skips them if not configured (unless explicitly requested)
- The user's Claude Code session has sufficient context window to handle the full pipeline (multi-stage execution within a single session)
- The worktrees trait behavior remains unchanged: specify creates the branch and worktree, subsequent stages inherit the worktree context
