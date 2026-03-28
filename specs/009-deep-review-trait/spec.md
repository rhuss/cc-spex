# Feature Specification: Deep-Review Trait

**Feature Branch**: `009-deep-review-trait`
**Created**: 2026-03-28
**Status**: Draft
**Input**: User description: "Deep-review trait: multi-perspective code review with autonomous fix loop, inspired by obra/superpowers, Anthropic pr-review-toolkit, and AgentCheck patterns"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Enhanced Review After Implementation (Priority: P1)

A plugin user completes `/speckit.implement` with the `superpowers` and `deep-review` traits enabled. When `spex:review-code` runs as part of the superpowers quality gate, it first performs the standard spec compliance check. After spec compliance passes, the deep-review trait activates multi-perspective review agents that analyze the code from different angles: correctness, architecture, security, production readiness, and test quality. Each agent produces findings classified by severity (Critical, Important, Minor). Critical and Important findings trigger an autonomous fix loop where the implementation agent addresses each issue and the reviewer re-verifies. The loop runs until no Critical or Important findings remain, or a maximum of 3 rounds is reached. A `review-findings.md` artifact is written to the spec directory documenting what was found and fixed.

**Why this priority**: This is the core value proposition. Without multi-perspective review agents and an autonomous fix loop, the trait does not exist.

**Independent Test**: Can be tested by enabling the `deep-review` trait, running `/speckit.implement` on a small feature with known code quality issues, and verifying that the review agents detect issues, the fix loop addresses them, and `review-findings.md` is produced.

**Acceptance Scenarios**:

1. **Given** the `deep-review` trait is enabled and `superpowers` triggers `review-code`, **When** spec compliance passes (>= 95%), **Then** Stage 2 (multi-perspective review) starts automatically with all configured review agents.
2. **Given** review agents produce Critical or Important findings, **When** the fix loop starts, **Then** findings are auto-fixed and re-reviewed for up to 3 rounds until no Critical/Important findings remain.
3. **Given** review agents produce only Minor findings (or no findings), **When** Stage 2 completes, **Then** the review gate passes and minor findings are listed in `review-findings.md` for awareness.
4. **Given** the fix loop reaches the maximum of 3 rounds with Critical/Important findings still remaining, **When** the loop terminates, **Then** the remaining findings are reported to the user and the gate does NOT pass (blocks completion).

---

### User Story 2 - Manual Review with Hints (Priority: P2)

A plugin user manually runs `/spex:review-code focus on mutation safety and resource cleanup` to trigger a deep review with a specific focus area. The hint text ("focus on mutation safety and resource cleanup") is injected as additional context into each review agent's prompt, steering attention without replacing the base checklist. The review proceeds with the same multi-perspective agents and fix loop as the automated flow.

**Why this priority**: Manual invocation with hints gives users control over review focus for specific concerns, without requiring a separate command.

**Independent Test**: Can be tested by running `/spex:review-code` with argument text and verifying that all review agents receive the hint text in their prompts and findings reflect the requested focus.

**Acceptance Scenarios**:

1. **Given** a user runs `/spex:review-code check CRD validation completeness`, **When** review agents execute, **Then** each agent's prompt includes the hint text as additional review focus alongside its standard checklist.
2. **Given** a user runs `/spex:review-code` with no arguments, **When** the deep-review trait is enabled, **Then** the full multi-perspective review runs with default focus areas (no hint injection).

---

### User Story 3 - Parallel Review via Teams (Priority: P2)

When both the `deep-review` and `teams` traits are enabled, review agents run in parallel using Claude Code Agent Teams. Each agent operates in its own isolated context (no shared session history) and produces independent findings. Findings from all agents are merged, deduplicated, and classified after all agents complete.

**Why this priority**: Parallel execution reduces review time significantly for large implementations. Equal priority with manual hints as both enhance the core experience.

**Independent Test**: Can be tested by enabling both `deep-review` and `teams` traits, running a review, and verifying agents execute in parallel and findings are properly merged.

**Acceptance Scenarios**:

1. **Given** both `deep-review` and `teams` traits are enabled, **When** Stage 2 review starts, **Then** all internal review agents launch in parallel via Agent Teams.
2. **Given** agents run in parallel, **When** all agents complete, **Then** findings are merged, deduplicated (same issue found by multiple agents counted once), and classified by severity.
3. **Given** the `teams` trait is NOT enabled, **When** Stage 2 review starts, **Then** review agents run sequentially (one at a time) in the main conversation context.

---

### User Story 4 - External CodeRabbit Integration (Priority: P3)

When the CodeRabbit CLI is installed on the user's system, the deep-review trait includes it as an additional review perspective alongside the internal agents. CodeRabbit provides an independent AI review from a different model, catching blind spots that Claude-based agents might miss. If the CLI is not installed, the trait works without it (graceful degradation).

**Why this priority**: External review adds value but is optional. The trait must work fully without external dependencies.

**Independent Test**: Can be tested by installing the CodeRabbit CLI, enabling the `deep-review` trait, running a review, and verifying CodeRabbit findings are included in the merged results.

**Acceptance Scenarios**:

1. **Given** the CodeRabbit CLI is installed, **When** Stage 2 review starts, **Then** `coderabbit review --plain --type uncommitted` runs alongside internal agents and its findings are parsed and merged into the consolidated findings.
2. **Given** the CodeRabbit CLI is NOT installed, **When** Stage 2 review starts, **Then** only internal agents run without error or warning about the missing CLI.
3. **Given** CodeRabbit and an internal agent find the same issue, **When** findings are merged, **Then** the duplicate is consolidated into a single finding with both sources noted.

---

### User Story 5 - Review Without Superpowers (Priority: P3)

A user has the `deep-review` trait enabled but NOT the `superpowers` trait. They manually invoke `/spex:review-code`. The deep-review enhancement still activates, running the multi-perspective agents and fix loop. The trait does not depend on superpowers; it enhances `review-code` regardless of how it is triggered.

**Why this priority**: Independence from superpowers broadens the trait's applicability.

**Independent Test**: Can be tested by enabling only the `deep-review` trait (not superpowers), manually running `/spex:review-code`, and verifying multi-perspective review runs correctly.

**Acceptance Scenarios**:

1. **Given** only the `deep-review` trait is enabled (no superpowers), **When** the user runs `/spex:review-code`, **Then** the full multi-perspective review with fix loop executes.
2. **Given** neither `deep-review` nor `superpowers` is enabled, **When** the user runs `/spex:review-code`, **Then** the standard spec-compliance-only review runs (no change to existing behavior).

---

### Edge Cases

- What happens when the spec compliance check fails (< 95%) in Stage 1? Stage 2 does NOT start. The user is directed to fix spec compliance issues first, same as current behavior.
- What happens when CodeRabbit CLI times out or returns an error? The error is logged in `review-findings.md` but does not block the review. Internal agent findings are still processed normally.
- What happens when the fix loop introduces new issues while fixing existing ones? New issues found in re-review rounds are treated the same as original findings. The 3-round maximum prevents infinite loops.
- What happens when multiple agents find the same issue? Findings are deduplicated by matching file path + line range + issue category. The finding with the most detail is kept, and other sources are noted.
- What happens when no spec exists (e.g., reviewing code outside the spex workflow)? Stage 1 (spec compliance) is skipped. Stage 2 (code quality review) runs on the changed files in the current branch.

## Requirements *(mandatory)*

### Functional Requirements

#### Trait Infrastructure

- **FR-001**: System MUST implement a `deep-review` trait as a spex overlay that enhances the `spex:review-code` skill when enabled.
- **FR-002**: System MUST detect the `deep-review` trait status at the start of `review-code` execution and branch accordingly (enhanced vs. standard review).
- **FR-003**: The trait MUST be independent of the `superpowers` trait. It enhances `review-code` regardless of whether superpowers triggered it or the user invoked it manually.

#### Two-Stage Review Pipeline

- **FR-010**: System MUST execute a two-stage review pipeline: Stage 1 (spec compliance) followed by Stage 2 (multi-perspective code quality review).
- **FR-011**: Stage 2 MUST NOT start unless Stage 1 passes with a compliance score of 95% or higher.
- **FR-012**: If no spec exists for the current feature, Stage 1 MUST be skipped and Stage 2 MUST run on changed files in the current branch.

#### Review Agents

- **FR-020**: System MUST define five internal review agents, each with a distinct focus area:
  - **Correctness Agent**: Mutation safety, shared references, logic errors, resource cleanup, error path correctness.
  - **Architecture & Idioms Agent**: Dead code, unnecessary complexity, duplication that will diverge, misleading naming, comment accuracy.
  - **Security Agent**: Input validation, injection risks, secret handling, RBAC scope, CRD/CEL validation gaps, authentication/authorization patterns.
  - **Production Readiness Agent**: Performance implications (goroutine leaks, unbounded channels, large critical sections), memory patterns (slice retention, pool misuse), operator patterns (reconciler concurrency, work queue depth).
  - **Test Quality Agent**: Coverage gaps, weak assertions, tests passing for wrong reasons, missing edge case tests, missing regression tests.

- **FR-021**: Each review agent prompt MUST include:
  - Role and scope gate ("you ARE responsible for X, you are NOT responsible for Y")
  - Distrust instruction ("do NOT trust the implementer's report, verify by reading code")
  - Failure modes section ("do NOT inflate nits, do NOT invent issues for clean code, do NOT repeat the same finding")
  - Confidence scoring (0-100 scale, only report findings with confidence >= 70)
  - Fix requirement ("every finding must include file:line, what's wrong, why it matters, and how to fix it")
  - Self-verification checklist (agent runs before returning results)

- **FR-022**: Each review agent MUST operate in isolated context (fresh prompt, no session history from implementation) to prevent groupthink and ensure independent analysis.

- **FR-023**: Review agents MUST be language-aware: they adapt their checklists based on the programming language detected in the changed files.

#### Findings Management

- **FR-030**: System MUST classify all findings by severity: Critical (must fix, blocks gate), Important (should fix, blocks gate), Minor (optional, does not block gate).
- **FR-031**: System MUST merge findings from all agents (internal and external) into a single consolidated list, deduplicating by file path + line range + issue category.
- **FR-032**: System MUST write a `review-findings.md` artifact to the spec directory documenting all findings, their status (fixed/remaining), round number, and source agent.

#### Autonomous Fix Loop

- **FR-040**: System MUST auto-fix Critical and Important findings and re-review changed files after each fix round.
- **FR-041**: The fix loop MUST be bounded to a maximum of 3 rounds.
- **FR-042**: The review gate MUST pass when no Critical or Important findings remain after any round.
- **FR-043**: If Critical or Important findings persist after 3 rounds, the gate MUST NOT pass, and the remaining findings MUST be reported to the user.

#### Teams Integration

- **FR-050**: When the `teams` trait is also enabled, review agents MUST run in parallel using Claude Code Agent Teams.
- **FR-051**: When the `teams` trait is NOT enabled, review agents MUST run sequentially in the main conversation context.

#### CodeRabbit Integration

- **FR-060**: When the CodeRabbit CLI is installed (detectable via `which coderabbit` or `npx @coderabbitai/cli --version`), the system MUST include it as an additional review perspective.
- **FR-061**: CodeRabbit MUST be invoked with `coderabbit review --plain --type uncommitted` to review local changes before PR submission.
- **FR-062**: When the CodeRabbit CLI is NOT installed, the system MUST proceed without it, using only internal agents.
- **FR-063**: CodeRabbit findings MUST be parsed and merged into the consolidated findings list alongside internal agent findings.

#### Manual Invocation with Hints

- **FR-070**: When `/spex:review-code` is invoked with argument text, the argument text MUST be injected as additional review focus into each review agent's prompt.
- **FR-071**: Hint injection MUST supplement (not replace) each agent's standard checklist and focus area.

#### Anti-Sycophancy Measures

- **FR-080**: All review agent prompts MUST include anti-sycophancy instructions: no positive affirmations ("Great implementation!"), zero findings is a red flag requiring re-read, and all findings must include concrete evidence.
- **FR-081**: Review agents MUST NOT trust test results as proof of correctness. They MUST read assertions and verify what is actually being tested.

### Key Entities

- **Review Agent**: A specialized sub-agent with a focused review perspective, its own prompt template, and isolated context. Five agents defined (correctness, architecture, security, production-readiness, test-quality).
- **Finding**: A code quality issue identified by a review agent. Has: severity (Critical/Important/Minor), confidence (0-100), file path, line number, description, rationale, fix suggestion, source agent.
- **Review Round**: One complete cycle of agent review + fix. Maximum 3 rounds per review session.
- **Review Findings Artifact**: The `review-findings.md` file documenting all findings across rounds, their resolution status, and gate outcome.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The deep-review trait catches at least 80% of the issue categories that Eoin's manual review found on PR #266 (mutation bugs, dead code, missing cleanup, logic errors, missing validation, duplication) when run on equivalent code.
- **SC-002**: The autonomous fix loop resolves at least 70% of Critical and Important findings without human intervention within 3 rounds.
- **SC-003**: Review with the trait enabled completes within 10 minutes for implementations under 2000 lines of changed code (sequential mode).
- **SC-004**: When the `teams` trait is active, parallel review completes at least 2x faster than sequential review.
- **SC-005**: The `review-findings.md` artifact provides sufficient detail for a human reviewer to understand what was machine-reviewed and what was fixed, reducing human review effort by at least 30%.
- **SC-006**: False positive rate stays below 20% (fewer than 1 in 5 reported findings are not actual issues).

## Assumptions

- The plugin user has Claude Code installed and configured with a model that supports Agent Teams (for parallel mode).
- The `spex:review-code` skill exists and functions as documented (spec compliance check with compliance scoring).
- The existing trait overlay mechanism (`spex/overlays/`) supports adding a new `deep-review` trait with command append files.
- CodeRabbit CLI, if used, requires the user to have an account and API key configured. The free tier (2 CLI reviews/hour) is sufficient for most single-feature reviews.
- The fix loop operates within the same conversation context. Each round's fixes are committed (or staged) before re-review.
- Review agents are language-aware: they adapt their checklists based on the programming language detected in the changed files (e.g., Go-specific patterns for Go code, Python-specific patterns for Python code).
