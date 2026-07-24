# Feature Specification: First-Class Codex Plugin Support

**Feature Branch**: `047-codex-plugin-support`

**Created**: 2026-07-24

**Status**: Draft

**Input**: User description: "Provide first-class Codex support from the same repository as the Claude plugin, including a marketplace-installed Codex plugin, interactive `spex:init`, selectable extensions and project-wide security levels, reliable worktree and state continuity, Codex-native progress and subagents, and a hardened ship pipeline that continues autonomously through recoverable blockers. Preserve a shared Spex core and allow an OpenCode adapter later."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Install and Initialize Spex in Codex (Priority: P1)

A Codex user installs Spex as a personal plugin, invokes `spex:init` in a repository, chooses recommended extensions and a security level, and receives a ready-to-use project configuration without needing Claude Code files or manual repair.

**Why this priority**: Users cannot benefit from any Codex workflow until installation and initialization are reliable, understandable, and native to Codex.

**Independent Test**: Install the Codex plugin in a clean Codex environment, initialize an unconfigured repository, accept the recommended extension selection and Safe security level, restart if instructed, and successfully invoke a Spex help or specification command.

**Acceptance Scenarios**:

1. **Given** a Codex user has installed the personal Spex plugin, **When** the user invokes `spex:init` in an uninitialized repository, **Then** the workflow identifies Codex, initializes the repository, presents extension and security choices, and reports the resulting configuration.
2. **Given** the initialization questionnaire is displayed, **When** the user accepts recommended extensions, **Then** gates, deep review, and worktrees are selected while Teams, collaboration, and detach remain optional.
3. **Given** the user selects Safe, Autonomous, or YOLO, **When** initialization completes, **Then** the effective project-wide behavior and remaining approval boundaries match the selected level and are explained to the user.
4. **Given** the repository was already initialized, **When** the user invokes `spex:init` again, **Then** existing selections are preserved by default and the workflow can safely refresh or change them without duplicating configuration.

---

### User Story 2 - Run Reliable Codex Workflows in a Feature Worktree (Priority: P1)

A Codex user starts a Spex workflow from the main checkout and continues working on the generated feature in its worktree without state, specification discovery, hooks, or subsequent stages falling back to the main checkout.

**Why this priority**: The observed worktree-state failure can send later stages to the wrong repository view, making autonomous execution unreliable and potentially modifying the wrong branch.

**Independent Test**: Start a specification workflow with worktrees enabled from the main checkout, allow it to create a feature worktree, complete at least two subsequent stages including a delegated review, interrupt and resume once, and verify that all feature artifacts and state mutations occur only in the active feature worktree.

**Acceptance Scenarios**:

1. **Given** a workflow creates a feature worktree, **When** the creation step completes, **Then** the active worktree, feature branch, specification directory, repository root, and workflow state location are durably recorded before the main-checkout state is cleared.
2. **Given** the active feature is in a worktree, **When** any later command, hook, review, or subagent runs, **Then** it resolves artifacts and performs in-scope mutations against that worktree rather than the main checkout.
3. **Given** a delegated stage returns control to the orchestrator, **When** the next stage begins, **Then** it uses the recorded active worktree even if the host resets the apparent working directory.
4. **Given** the workflow is interrupted in a worktree, **When** the user resumes it from either the main checkout or the feature worktree, **Then** the same active feature and unfinished stage are recovered without creating competing state files.

---

### User Story 3 - Ship Continuously Through Recoverable Blockers (Priority: P1)

A user starts `ship` with Autonomous or YOLO behavior and can rely on it to keep progressing through review findings, feasibility uncertainty, and bounded retries without turning safe recovery work into another confirmation prompt.

**Why this priority**: The promise of ship is an autonomous end-to-end workflow. Pausing after ordinary retry exhaustion or asking permission to perform an in-scope feasibility spike breaks that promise.

**Independent Test**: Use a fixture whose specification review exposes a resolvable feasibility concern after normal fix retries. Verify that ship performs a bounded investigation, revises the affected artifact, reruns the required gate, and advances without asking the user whether to continue.

**Acceptance Scenarios**:

1. **Given** a ship stage reports correctable findings, **When** its normal fix cycles are exhausted, **Then** ship selects and performs a bounded recovery action rather than pausing solely because the retry count was reached.
2. **Given** a reviewer recommends a safe in-scope research task or feasibility spike, **When** ship is running under Autonomous or YOLO behavior, **Then** ship performs the work, incorporates the result into the appropriate artifact, and reruns affected stages without seeking confirmation.
3. **Given** recovery changes an earlier artifact, **When** the change is accepted, **Then** every downstream artifact and gate affected by that change is revisited before implementation continues.
4. **Given** repeated recovery attempts make no material progress, **When** the configured recovery budget is exhausted, **Then** ship stops with a terminal report containing attempted actions, evidence, residual risk, and an exact resume point.
5. **Given** progress requires new user authority, unavailable credentials or infrastructure, an irreversible external action, or a material product decision unsupported by existing requirements, **When** ship encounters that boundary, **Then** it pauses with one focused request describing why autonomous continuation is unsafe.

---

### User Story 4 - Understand Progress and Recover State in Codex (Priority: P2)

A Codex user can see which workflow stage is running, which stages completed, and whether recovery activity is underway using Codex-native progress presentation, without depending on a Claude-specific custom status line.

**Why this priority**: Long autonomous workflows need visible progress, but Codex and Claude expose different presentation capabilities.

**Independent Test**: Run a multi-stage workflow in Codex and observe stage transitions, delegated activity, recovery attempts, and completion through native progress surfaces; then interrupt and verify that the persisted state matches the last reported stage.

**Acceptance Scenarios**:

1. **Given** a Spex workflow is active in Codex, **When** it enters or completes a stage, **Then** Codex-native task progress and a concise transition message reflect the change.
2. **Given** ship begins autonomous recovery, **When** recovery work runs, **Then** the user can distinguish it from the normal stage and see its bounded objective.
3. **Given** Codex does not support the Claude custom status-line command, **When** Spex initializes, **Then** it does not install or advertise that integration as available.
4. **Given** visible progress and durable state disagree after interruption, **When** the workflow resumes, **Then** durable validated state determines recovery and the discrepancy is reported.

---

### User Story 5 - Use Optional Codex Parallel Teams Safely (Priority: P2)

A Codex user who explicitly enables the experimental Teams extension can parallelize independent research or implementation while preserving isolation, dependency ordering, review, and a safe sequential fallback.

**Why this priority**: Codex supports subagents, but its model differs from Claude Agent Teams. Parallelism is valuable only when it does not compromise feature correctness or worktree safety.

**Independent Test**: Enable Teams for a task set containing two independent write groups and one dependent task. Verify that independent groups run in isolated workspaces, accepted results are reviewed and reconciled before the dependent task begins, and disabling subagents causes a sequential fallback.

**Acceptance Scenarios**:

1. **Given** Teams is not explicitly selected during initialization, **When** Spex is configured, **Then** Teams remains disabled and is described as optional and experimental for Codex.
2. **Given** Teams is enabled and at least two independent research topics exist, **When** research begins, **Then** Codex subagents may run those topics concurrently and return bounded summaries to the orchestrator.
3. **Given** Teams is enabled and independent code-writing groups exist, **When** they are dispatched, **Then** each group receives an isolated workspace, an explicit working location, and only its assigned tasks and required context.
4. **Given** a subagent completes work, **When** the orchestrator receives it, **Then** the result is reviewed against the specification before it is accepted and dependent work proceeds.
5. **Given** parallel execution is unavailable, unsafe, or not beneficial, **When** orchestration evaluates the work, **Then** it continues sequentially without treating the absence of Teams as a blocker.

---

### User Story 6 - Maintain Multiple Harness Plugins Together (Priority: P3)

A Spex maintainer can evolve Claude and Codex support in the same repository from a shared workflow core, test each distribution independently and together, and later add OpenCode without copying the entire methodology.

**Why this priority**: Shared ownership prevents workflow drift and makes future harness support sustainable, but it follows the user-facing Codex reliability work.

**Independent Test**: Build or install the Claude and Codex plugin distributions separately and together, verify that each contains only valid harness-specific material, and add a representative third adapter fixture without changing shared workflow semantics.

**Acceptance Scenarios**:

1. **Given** both Claude and Codex plugins originate from the repository, **When** they are packaged or installed, **Then** their manifests, configuration, hooks, generated artifacts, and caches do not overwrite or misidentify one another.
2. **Given** behavior is common across harnesses, **When** it changes, **Then** maintainers update one canonical source and verify both materialized distributions.
3. **Given** a behavior depends on harness capabilities, **When** it is materialized, **Then** the owning adapter provides explicit native behavior or an explicit documented degradation.
4. **Given** a plugin artifact is produced, **When** compatibility validation runs, **Then** it contains no unresolved harness markers, unavailable tool names, or commands belonging only to another harness.

### Edge Cases

- Initialization runs where both Claude and Codex project configuration already exist.
- A user changes security level after the repository has been initialized.
- The installed Codex version does not support a requested permission or subagent capability.
- A worktree is created successfully but state transfer fails before the main-checkout copy is removed.
- Main and worktree state files both exist after a crash and disagree about the active stage.
- A feature worktree is outside the initial writable workspace boundary.
- A delegated reviewer completes after its worktree has moved or been removed.
- Autonomous recovery discovers that the original requirement is infeasible rather than merely underspecified.
- Recovery revises the specification after planning or implementation has already begun.
- Recovery repeatedly alternates between two incompatible fixes without convergence.
- Teams identifies nominally parallel tasks that modify the same files or shared contract.
- A subagent fails after making partial changes in its isolated workspace.
- Claude and Codex plugins are both installed but only one harness is active for the current project.
- A future harness supports workflows but lacks equivalent hooks, interactive choices, progress UI, or parallel agents.

## Requirements *(mandatory)*

### Functional Requirements

#### Plugin distribution and initialization

- **FR-001**: Spex MUST provide a Codex plugin distribution installable as a personal plugin through the supported Codex plugin discovery experience.
- **FR-002**: The Codex plugin MUST expose `spex:init` as the repository initialization and refresh entry point.
- **FR-003**: Initialization MUST detect the active harness and modify only the active harness's project configuration unless the user explicitly requests cross-harness changes.
- **FR-004**: Initialization MUST present extension selection with gates, deep review, and worktrees recommended by default, while Teams, collaboration, and detach remain optional.
- **FR-005**: Initialization MUST describe Codex Teams as experimental and MUST NOT enable it without explicit user selection.
- **FR-006**: Initialization MUST be repeatable without duplicating configuration, losing valid existing selections, or requiring a fresh repository.
- **FR-007**: Initialization MUST report enabled extensions, effective security level, unavailable capabilities, and any restart or refresh required before use.

#### Security profiles

- **FR-008**: Initialization MUST ask the user to select exactly one project-wide security level: Safe, Autonomous, or YOLO.
- **FR-009**: Safe MUST retain normal approval and sandbox safeguards for Spex operations.
- **FR-010**: Autonomous MUST allow routine in-workspace Spex operations to proceed without repeated approval while preserving approval requirements for destructive actions, external side effects, and actions outside granted authority.
- **FR-011**: YOLO MUST broadly suppress routine approvals for project work while continuing to block destructive actions outside the workspace and other actions requiring authority the user has not granted.
- **FR-012**: Before persisting Autonomous or YOLO, initialization MUST clearly state which safeguards remain and what additional autonomy is granted.
- **FR-013**: The selected security level MUST apply consistently to Spex commands, ship stages, delegated reviews, implementation work, and Codex subagents within the project.
- **FR-014**: If the active Codex version cannot express the selected security behavior, initialization MUST fail safely or offer the closest safer supported level rather than silently weakening or broadening it.

#### Worktree and state reliability

- **FR-015**: Workflow state MUST durably identify the active repository root, worktree, feature branch, specification directory, state location, current stage, and recovery status.
- **FR-016**: Spex MUST NOT depend on shell working-directory or environment changes persisting between Codex operations.
- **FR-017**: Every worktree-sensitive operation MUST receive or resolve the explicit active worktree location from durable workflow context.
- **FR-018**: Worktree creation MUST return a machine-readable identity that downstream orchestration consumes directly.
- **FR-019**: State transfer to a feature worktree MUST be verified before stale main-checkout state is removed.
- **FR-020**: Specification discovery, extension configuration, hook execution, artifact validation, and state mutation MUST resolve against the active feature worktree after transfer.
- **FR-021**: The orchestrator MUST re-establish and validate active worktree context after every delegated stage returns.
- **FR-022**: Resume MUST recover the same active feature and unfinished activity when invoked from either the main checkout or the feature worktree.
- **FR-023**: When competing state files exist, recovery MUST detect the conflict, select a validated authoritative state using deterministic rules, and preserve diagnostic evidence.
- **FR-024**: Spex MUST refuse feature mutations when it cannot establish which checkout and state are authoritative.

#### Continuous ship execution

- **FR-025**: Ship MUST execute its defined stages continuously until completion, an explicit terminal failure, or a boundary requiring new user authority.
- **FR-026**: Stage completion, delegated-agent return, retry exhaustion, context compression, and recoverable findings MUST NOT independently terminate or pause ship.
- **FR-027**: After normal correction attempts fail, ship MUST select a bounded recovery activity appropriate to the finding, such as focused research, a feasibility check, artifact revision, alternative implementation, or finding decomposition.
- **FR-028**: In Autonomous and YOLO modes, ship MUST execute safe in-scope recovery recommendations without asking whether to proceed.
- **FR-029**: Recovery results MUST be incorporated into the artifact responsible for the finding and MUST trigger revalidation of every affected downstream artifact and gate.
- **FR-030**: Ship MUST persist recovery objectives, attempts, outcomes, and the exact resume point.
- **FR-031**: Ship MUST enforce finite attempt and elapsed-work budgets for each recovery episode to prevent infinite loops.
- **FR-032**: Ship MUST detect non-converging recovery, including repeated equivalent findings and oscillation between incompatible remedies.
- **FR-033**: On terminal failure, ship MUST report the evidence gathered, actions attempted, remaining blockers or exposure, affected artifacts, and a precise resume action.
- **FR-034**: Ship MUST pause for user input only when continuation requires new authority, unavailable credentials or infrastructure, an irreversible external action, or a material product decision not supported by current requirements.
- **FR-035**: A ship pause MUST ask one focused question and MUST distinguish a genuine decision boundary from ordinary technical uncertainty.

#### Codex-native progress and subagents

- **FR-036**: Codex workflows MUST present stage, delegated-work, recovery, pause, and completion progress through Codex-supported native progress surfaces and concise transcript updates.
- **FR-037**: Codex initialization MUST NOT install, require, or advertise the Claude custom status-line command.
- **FR-038**: Durable workflow state MUST remain authoritative for resume even when visible progress presentation is unavailable or stale.
- **FR-039**: Codex subagents MUST inherit the effective project security level and receive only the context and task scope required for their assignment.
- **FR-040**: Parallel work MUST be dispatched only when at least two work groups are independent under file, contract, and dependency analysis.
- **FR-041**: Parallel code-writing groups MUST use isolated workspaces with explicit working locations; read-only research groups MAY share the repository view.
- **FR-042**: The orchestrator MUST wait for assigned subagents, review returned work against the specification, and reconcile accepted work before dependent tasks begin.
- **FR-043**: Failed or unavailable subagents MUST be replaceable or degradable to sequential execution without losing completed valid work.
- **FR-044**: Teams MUST fall back to sequential execution when isolation, independence, capability availability, or coordination safety cannot be established.

#### Multi-harness compatibility

- **FR-045**: Claude and Codex plugin distributions MUST coexist in the same repository and installation environment without overwriting each other's manifests, hooks, configuration, generated artifacts, or caches.
- **FR-046**: Behavior shared by supported harnesses MUST have one canonical source of truth.
- **FR-047**: Harness-specific behavior MUST be owned by an explicit harness adapter or specialization layer.
- **FR-048**: Materialized artifacts MUST contain no unresolved harness directives and no references to unavailable tools, commands, paths, or UI capabilities.
- **FR-049**: The project MUST validate Claude-only, Codex-only, and combined installation scenarios.
- **FR-050**: Compatibility validation MUST cover interactive choices, hooks, permissions, progress, context lifecycle, shell persistence assumptions, worktrees, subagents, command names, and plugin discovery.
- **FR-051**: Each harness adapter MUST publish a capability and degradation summary identifying which shared behaviors are native, adapted, unavailable, or safely reduced.
- **FR-052**: Adding a future OpenCode adapter MUST NOT require copying or forking the complete shared Spex workflow set.

### Key Entities

- **Plugin Distribution**: An installable harness-specific Spex package with its manifest, entry points, and specialized behavior, linked to the shared Spex core.
- **Harness Adapter**: The explicit mapping from shared workflow intent to one harness's interaction, hook, permission, progress, worktree, and agent capabilities.
- **Initialization Profile**: The repository's selected extensions, security level, active harness, capability observations, and refresh state.
- **Security Level**: Safe, Autonomous, or YOLO, including the granted autonomy and approval boundaries that remain in force.
- **Workflow State**: The durable authority for active feature identity, worktree location, stage, completed gates, recovery activity, and resume information.
- **Recovery Episode**: A bounded autonomous attempt to resolve a finding after normal correction cycles, including its objective, evidence, actions, budget, and outcome.
- **Work Group**: A dependency- and conflict-checked unit of research or implementation suitable for sequential or parallel assignment.
- **Capability Report**: The declared and observed support level for required Spex behaviors on a particular harness version.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In clean-environment acceptance tests, at least 95% of users can install the Codex plugin, complete `spex:init` with recommended settings, and invoke their first Spex workflow without manual file editing.
- **SC-002**: Across 100 automated worktree lifecycle runs containing delegated stages and interruption/resume points, zero feature mutations or state advances occur in the wrong checkout.
- **SC-003**: In every tested recoverable review-blocker scenario, Autonomous and YOLO ship runs either complete recovery and continue or reach a bounded terminal report without asking a routine “should I continue?” question.
- **SC-004**: Every terminal ship failure test ends with a validated resume point and a report of attempted recovery actions, residual blockers, and affected artifacts.
- **SC-005**: No tested ship recovery episode exceeds its configured attempt or elapsed-work budget, and all injected oscillation scenarios are detected before an additional equivalent cycle begins.
- **SC-006**: Users can identify the active stage and whether normal, delegated, or recovery work is running within one progress update of a transition in all supported Codex clients.
- **SC-007**: Static compatibility validation reports zero unresolved harness markers and zero known cross-harness tool, command, path, or status-line references in released Claude and Codex artifacts.
- **SC-008**: Claude-only, Codex-only, and combined installation suites complete successfully on every supported release platform.
- **SC-009**: In parallel Teams acceptance tests, 100% of concurrent code-writing agents operate in distinct isolated workspaces, and no dependent task starts before its prerequisite results are accepted.
- **SC-010**: When parallel execution is disabled or unavailable, 100% of eligible Teams scenarios continue through the sequential fallback without loss of required work.
- **SC-011**: A representative OpenCode adapter can reuse all shared workflow definitions while supplying only harness-specific packaging and behavior specialization.
- **SC-012**: Existing Claude Spex acceptance workflows retain their pre-feature pass rate after the Codex plugin is introduced.

## Assumptions

- The target Codex releases support personal plugins, project configuration, lifecycle hooks, native task progress, and subagents; version-specific gaps are handled through capability detection and safe degradation.
- Safe is the default security level when a user does not make an explicit selection.
- YOLO remains bounded by workspace scope and user authority; it is not consent for destructive actions outside the workspace or uncontrolled external side effects.
- Gates, deep review, and worktrees are the recommended extension baseline for first-class Codex use.
- Teams remains optional and experimental until its isolation, reconciliation, and fallback success criteria are consistently met.
- Claude and Codex may expose different user experiences while preserving the same observable Spex workflow guarantees.
- OpenCode support is limited in this feature to architectural extensibility and a representative adapter proof; a production OpenCode plugin is separate future work.
- Existing Spex feature specifications remain historical records and are not rewritten as part of this feature.

