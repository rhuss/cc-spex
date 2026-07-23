# Feature Specification: Smart Phase Splitting

**Feature Branch**: `046-smart-phase-splitting`

**Created**: 2026-07-23

**Status**: Draft

**Input**: User description: "Make collab phase splitting size-aware, merge small phases, and run single-phase mode without interruptions"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Small Feature Skips Phase Split Prompt (Priority: P1)

A developer runs `/speckit-implement` on a feature with 12 tasks that will touch approximately 15 files. The phase-split hook estimates the file count, determines it is below the threshold (default: 20), and silently defaults to single-phase mode. The developer is never shown a phase split prompt and implementation runs uninterrupted from start to finish. The phase-manager fires once at the end to offer a PR creation opportunity.

**Why this priority**: This is the most common scenario. Most features are small to medium. Eliminating the unnecessary phase split prompt for these features removes the primary source of friction.

**Independent Test**: Can be tested by creating a tasks.md with 12 tasks under 3 Phase headings, a plan.md referencing 15 files, and running the phase-split hook. Verify no interactive prompt appears and the phase plan is set to single phase.

**Acceptance Scenarios**:

1. **Given** a feature with tasks.md containing 12 tasks across 3 phases and plan.md listing 15 file paths, **When** the phase-split hook runs, **Then** no phase split prompt is shown and the phase plan is set to a single phase named "Full Implementation"
2. **Given** the `phases.file_threshold` config is set to 20 and the estimated file count is 18, **When** the phase-split hook runs, **Then** it defaults to single phase silently
3. **Given** a feature where plan.md lists only 3 file paths (below the 5-file fallback threshold), **When** the phase-split hook estimates files, **Then** it falls back to the task-count heuristic (tasks * 1.5) to estimate file count

---

### User Story 2 - Single Phase Runs Without Interruption (Priority: P1)

A developer selects "Single phase (no split)" or the threshold gate defaults to single phase. During implementation, the phase-manager hook does not fire at any phase boundary. Implementation runs continuously through all tasks. After all tasks complete, phase-manager fires exactly once to offer the review gate and PR creation.

**Why this priority**: Equal priority with US1 because stopping after each phase in single-phase mode is the most disruptive bug. Even when the user explicitly chose single phase, the current system still interrupts.

**Independent Test**: Can be tested by setting up single-phase mode in `.spex-state` and running implement. Monitor that phase-manager does not fire during implementation but fires once afterward.

**Acceptance Scenarios**:

1. **Given** a feature in single-phase mode (either user-selected or threshold-defaulted), **When** `/speckit-implement` runs through all tasks, **Then** the phase-manager hook does not fire during implementation
2. **Given** a feature in single-phase mode, **When** all implementation tasks complete, **Then** phase-manager fires once offering the review gate and PR creation
3. **Given** a feature where the user explicitly selected "Single phase (no split)" from the phase-split prompt, **When** implementation begins, **Then** behavior is identical to threshold-defaulted single phase (no interruptions)

---

### User Story 3 - Large Feature Gets Merged Phase Proposal (Priority: P2)

A developer runs `/speckit-implement` on a large feature with 30 tasks across 7 Phase headings in tasks.md, estimated to touch 45 files. The phase-split hook determines this exceeds the threshold, reads the existing phase groupings from tasks.md, and merges adjacent small phases until each phase is substantial (at least ~10 files). The developer sees a proposal with 3 merged phases instead of 7, and can confirm, adjust, or choose single phase.

**Why this priority**: This scenario only applies to large features. It improves the experience when phases are offered, but the primary value (US1, US2) comes from not offering phases when they are not needed.

**Independent Test**: Can be tested by creating a tasks.md with 7 phases (2-5 tasks each) and a plan.md listing 45 file paths distributed across phases. Verify the merge produces fewer phases, each touching 10+ files.

**Acceptance Scenarios**:

1. **Given** a feature with 7 phases in tasks.md and an estimated 45 files, **When** the phase-split hook runs, **Then** it proposes merged phases where each phase touches at least ~10 files
2. **Given** merged phases are proposed, **When** the user sees the prompt, **Then** they can choose "Confirm as-is", "Adjust groupings", or "Single phase (no split)"
3. **Given** two adjacent phases each touching 4 files, **When** the merge logic runs, **Then** they are combined into a single phase
4. **Given** a phase that already touches 15 files, **When** the merge logic runs, **Then** it is kept as its own phase (not merged further)

---

### User Story 4 - Configurable File Threshold (Priority: P3)

A developer customizes the file threshold by setting `phases.file_threshold: 30` in collab-config.yml. Features estimated to touch up to 30 files now default to single phase. The default value (20) works for most projects without configuration.

**Why this priority**: Configuration is a nice-to-have. The default of 20 files is a sensible universal threshold. Only power users with specific project characteristics need to tune this.

**Independent Test**: Can be tested by setting different `phases.file_threshold` values in collab-config.yml and verifying the phase-split hook uses the configured value instead of the default.

**Acceptance Scenarios**:

1. **Given** `phases.file_threshold: 30` is set in collab-config.yml, **When** the phase-split hook runs on a 25-file feature, **Then** it defaults to single phase
2. **Given** no `phases.file_threshold` is set in collab-config.yml, **When** the phase-split hook runs, **Then** it uses the default threshold of 20
3. **Given** `phases.file_threshold: 10` is set, **When** the phase-split hook runs on a 15-file feature, **Then** it proposes phases (since 15 > 10)

---

### Edge Cases

- What happens when plan.md does not exist? Fall back to task-count heuristic (tasks * 1.5) for file estimation.
- What happens when plan.md exists but contains no file path references? Fall back to task-count heuristic if fewer than 5 file paths are found.
- What happens when all phases after merging result in only one phase? Treat as single phase (no prompt shown).
- What happens when tasks.md has no Phase/US headings at all? All tasks become a single phase (existing behavior preserved).
- What happens during ship pipeline mode? The phase-split hook detects ship mode from `.spex-state` and skips entirely (existing behavior preserved).
- What happens when the file threshold is set to 0? All features get phase proposals regardless of size (effectively disabling the threshold gate).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The phase-split hook MUST estimate the total file count for the feature before deciding whether to propose phases
- **FR-002**: File estimation MUST use a hybrid approach: parse file paths (including test files) from plan.md first, fall back to task-count heuristic (tasks * 1.5) if fewer than 5 file paths are found in plan.md
- **FR-003**: The phase-split hook MUST compare the estimated file count against a configurable threshold (default: 20) and only propose multi-phase split when the estimate exceeds the threshold
- **FR-004**: When estimated files are at or below the threshold, the hook MUST silently default to single-phase mode without showing any prompt to the user
- **FR-005**: When multi-phase split is proposed, the hook MUST merge adjacent phases from tasks.md groupings when a phase would touch fewer than 10 files (the per-phase merge minimum)
- **FR-006**: Phase merging MUST preserve the logical ordering from tasks.md (merge adjacent phases only, never reorder)
- **FR-007**: The merged phase proposal MUST still offer the interactive options: "Confirm as-is", "Adjust groupings", "Single phase (no split)"
- **FR-008**: In single-phase mode, the phase-manager hook MUST NOT fire during implementation (no inter-task interruptions)
- **FR-009**: In single-phase mode, the phase-split output instructions MUST include a single phase-manager invocation at the end (after all tasks), so the user or calling workflow runs phase-manager exactly once for the final review gate and PR creation offer
- **FR-010**: The file threshold MUST be configurable via `phases.file_threshold` in collab-config.yml with a default value of 20
- **FR-011**: The phase-split hook MUST continue to skip entirely when ship pipeline mode is detected in `.spex-state` (preserve existing behavior)

### Key Entities

- **Phase Plan**: The data structure in `.spex-state` tracking phase assignments, completion status, and whether single-phase mode is active
- **File Estimate**: The computed count of files the feature will touch, derived from plan.md or task-count heuristic
- **Collab Config**: The `collab-config.yml` file containing `phases.file_threshold` and other collab settings

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Features with fewer than 20 estimated files proceed to implementation without any phase-related prompt or interruption
- **SC-002**: Single-phase implementation runs from first task to last task without any phase-manager interruption, with phase-manager firing exactly once at the end
- **SC-003**: Large features (40+ files) receive merged phase proposals with no phase containing fewer than the per-phase merge minimum (10 files)
- **SC-004**: The `phases.file_threshold` configuration is read from collab-config.yml and respected by the phase-split hook
- **SC-005**: All existing phase-split tests continue to pass (no regressions)
- **SC-006**: Ship pipeline mode continues to bypass phase splitting entirely

## Clarifications

### Session 2026-07-23

- Q: Should file estimation count test files or only production code? → A: Count all files (test files also require PR review and contribute to reviewer cognitive load)
- Q: Should the per-phase merge minimum (~10 files) be configurable separately from the split threshold? → A: No, keep as internal heuristic. Only the split threshold (`phases.file_threshold`) is user-configurable to avoid configuration overload.

## Dependencies

- **spex-collab extension**: Existing `phase-split` and `phase-manager` commands in `spex/extensions/spex-collab/commands/`
- **collab-config.yml**: Existing config template at `spex/extensions/spex-collab/config-template.yml` (new `phases` section will be added)
- **`.spex-state`**: Existing state file format with `collab.phase_plan` structure
- **plan.md**: Generated by `/speckit-plan`, expected to contain file path references parseable by grep/regex
- **tasks.md**: Generated by `/speckit-tasks`, expected to contain Phase/US heading groupings

## Out of Scope

- Automatic detection of file dependencies or import graphs (estimation uses simple file path counting, not static analysis)
- Per-phase merge minimum configuration (the 10-file minimum is an internal heuristic, not user-configurable per clarification session)
- Changing how phase-manager handles multi-phase mode (only single-phase behavior changes)
- Modifications to the REVIEWERS.md generation or PR creation workflows

## Assumptions

- plan.md file references are primarily file paths or patterns that can be parsed with simple regex/grep (not prose descriptions of files)
- The 1.5 files-per-task heuristic is a reasonable approximation for estimating file count when plan.md is sparse
- Adjacent phase merging (not arbitrary reordering) is sufficient to produce well-sized phases in practice
- The ~10 files minimum per phase is a reasonable threshold for meaningful PR review granularity
- The phase-manager hook can detect single-phase mode from the phase plan stored in `.spex-state`
