# Feature Specification: Harden Deep Review Process

**Feature Branch**: `019-harden-deep-review`
**Created**: 2026-05-22
**Status**: Draft
**Input**: Brainstorm 12 - Hardening the Spec-Driven Review Process

## User Scenarios & Testing

### User Story 1 - Fix Loop Catches Regressions via Test Suite (Priority: P1)

A developer runs the deep review on their feature branch. The review finds a Critical issue and the fix loop applies a correction. After the fix is applied, the fix loop runs the project's test suite before re-reviewing the code. The test suite catches a regression introduced by the fix (e.g., the fix broke an existing test). The regression is reported as a new Critical finding and enters the next fix round.

**Why this priority**: This is the highest-impact intervention. The incident that motivated this feature was caused by a fix-loop-introduced regression that was never caught because the test suite was never run. Running tests after fixes is the single most effective safety net.

**Independent Test**: Can be tested by running a deep review on a project with a known fix that breaks a test. Verify the test failure appears as a Critical finding.

**Acceptance Scenarios**:

1. **Given** a deep review is running and the fix loop applies a code fix, **When** the fix loop completes applying fixes for a round, **Then** the project's test suite is executed before re-dispatching review agents.
2. **Given** the test suite fails after a fix is applied, **When** the test results are processed, **Then** each test failure is converted to a Critical finding with the test name, file, and failure message.
3. **Given** a project with a Makefile containing a `test` target, **When** the fix loop needs to run tests, **Then** the test command `make test` is auto-detected and used.
4. **Given** a project with `go.mod` but no Makefile test target, **When** the fix loop needs to run tests, **Then** the test command `go test ./...` is auto-detected and used.
5. **Given** a project with `package.json` containing a `test` script, **When** the fix loop needs to run tests, **Then** the test command `npm test` is auto-detected and used.
6. **Given** no recognizable test command can be detected, **When** the fix loop reaches the test execution step, **Then** the test step is skipped with a logged warning ("no test command detected, skipping post-fix test run") and the fix loop proceeds to re-review.
7. **Given** the test suite passes after a fix, **When** the fix loop continues, **Then** the review agents are re-dispatched as normal (existing behavior unchanged).

---

### User Story 2 - Test Quality Agent Validates Against Spec Acceptance Scenarios (Priority: P2)

A developer has a spec with acceptance scenarios like "confirm `status.card` is populated via `kubectl get agentruntime -o yaml`". The test-quality review agent reads the spec's acceptance scenarios and cross-references them against the actual test code. The agent flags that the test only checks an in-memory object instead of reading back from the API server as the spec requires.

**Why this priority**: This directly prevents the class of bug that motivated this feature. The spec had the right acceptance criteria, but tests didn't match them. Enforcing alignment between spec verification methods and test assertions catches weak tests before they give false confidence.

**Independent Test**: Can be tested by providing a spec with an acceptance scenario that specifies a particular verification method and a test that uses a different method. Verify the agent flags the mismatch.

**Acceptance Scenarios**:

1. **Given** a spec with acceptance scenarios that describe verification methods (e.g., "confirm via kubectl get", "verify the HTTP response body"), **When** the test-quality agent reviews the code, **Then** it finds the corresponding tests and checks whether the test's assertions match the spec's verification method.
2. **Given** a spec says "confirm via kubectl get" and the test only checks an in-memory object, **When** the test-quality agent reviews, **Then** it produces a finding: "Spec acceptance scenario requires verification via [method], but test only checks [actual method]."
3. **Given** a spec with acceptance scenarios that don't specify a verification method (e.g., "card data is populated"), **When** the test-quality agent reviews, **Then** it checks that a test exists for the scenario but does not flag a verification method mismatch.
4. **Given** no spec is available for the review, **When** the test-quality agent runs, **Then** it skips spec-anchored validation and performs its standard checklist review only.

---

### User Story 3 - Correctness Agent Detects Swallowed Errors (Priority: P3)

A developer writes a function that calls an API server operation (e.g., `r.Patch()`), catches or checks the error, logs it, but does not return it to the caller. The correctness review agent flags this as a finding because silent error swallowing hides failures and prevents callers from reacting.

**Why this priority**: In the motivating incident, `persistCardFetchAnnotation` logged the Patch error but didn't return it. This meant the Patch failed silently in tests (object not in envtest), so the mutation side effect never triggered. Detecting swallowed errors catches this pattern.

**Independent Test**: Can be tested by submitting code with a function that logs an error from an I/O operation but doesn't return it. Verify the correctness agent produces a finding.

**Acceptance Scenarios**:

1. **Given** a function calls a fallible operation (API call, file I/O, network request) and logs the error but does not return or propagate it, **When** the correctness agent reviews the code, **Then** it produces a finding flagging the swallowed error with the specific function and line.
2. **Given** a function calls a fallible operation and explicitly documents why the error is intentionally ignored (e.g., best-effort cleanup), **When** the correctness agent reviews, **Then** it produces a Minor finding (not Critical) noting the intentional swallow with reduced confidence.
3. **Given** a function properly returns or wraps the error from a fallible operation, **When** the correctness agent reviews, **Then** no swallowed-error finding is produced for that function.

---

### User Story 4 - Review Agents Use Project-Specific Framework Hints (Priority: P4)

A project maintainer creates `.specify/review-hints.md` with framework-specific patterns (e.g., "controller-runtime's `client.Patch()` mutates the input object in-place from the API server response"). When the deep review runs, every review agent receives this content in its preamble, enabling it to catch framework-specific issues that would otherwise be invisible.

**Why this priority**: This addresses the root cause of the motivating incident (framework-specific side effects invisible to generic review). It's lower priority because it requires the project to create the hints file, and the bootstrapping problem means the first bug teaches you what hints you need. The other interventions catch bugs earlier in the chain.

**Independent Test**: Can be tested by creating a `.specify/review-hints.md` file and running a deep review. Verify the hints content appears in each agent's prompt context.

**Acceptance Scenarios**:

1. **Given** a project has a `.specify/review-hints.md` file, **When** the deep review dispatches review agents, **Then** the file's content is appended to every review agent's preamble (after the common preamble, before the agent-specific checklist).
2. **Given** a project does not have `.specify/review-hints.md`, **When** the deep review runs, **Then** review agents run with their standard prompts (no error, no warning, silent skip).
3. **Given** a `.specify/review-hints.md` file exists and contains framework-specific patterns, **When** a review agent encounters code matching a described pattern, **Then** the agent is able to reference the hint when producing findings (the hint content is in its context).
4. **Given** a `.specify/review-hints.md` file is empty, **When** the deep review runs, **Then** no content is injected and agents run normally.

---

### Edge Cases

- What happens when the test command times out during the fix loop? The fix loop should apply a timeout (configurable, default 5 minutes), treat a timeout as a test failure, and log the timeout as a Critical finding.
- What happens when the test command exits with a non-zero code but produces no parseable output? Treat it as a single Critical finding with the exit code and any available stderr.
- What happens when `.specify/review-hints.md` contains markdown that could be confused with the agent prompt format? The hints are injected as a clearly delimited block (e.g., wrapped in a "Project Review Hints" section header) to avoid prompt confusion.
- What happens when spec acceptance scenarios reference external systems not available in the test environment? The test-quality agent should note the scenario exists but cannot validate the verification method match (informational, not a finding).

## Requirements

### Functional Requirements

- **FR-001**: The fix loop (Step 7 in `speckit.spex-deep-review.run`) MUST execute the project's test suite after applying fixes in each round, before re-dispatching review agents.
- **FR-002**: Test command auto-detection MUST check the following sources in order: (1) Makefile with `test` target, (2) `go.mod` presence (use `go test ./...`), (3) `package.json` with `test` script (use `npm test`), (4) `pyproject.toml` or `setup.py` presence (use `pytest`). The first match wins.
- **FR-003**: Test failures MUST be converted to Critical findings with `source_agent = "test-suite"`, `category = "regression"`, and `confidence = 95`.
- **FR-004**: If no test command can be detected, the test step MUST be skipped with a warning logged for inclusion in `review-findings.md`.
- **FR-005**: A test execution timeout MUST be configurable in `deep-review-config.yml` under `test_timeout_seconds` (default: 300).
- **FR-005a**: A test command override MUST be configurable in `deep-review-config.yml` under `test_command`. When set, the configured command is used instead of auto-detection (FR-002).
- **FR-005b**: When the test suite fails after a fix round, the failure MUST consume a fix round (same as a review finding). Test failures become Critical findings and enter the next round for fixing.
- **FR-006**: The test-quality review agent MUST cross-reference spec acceptance scenarios against test verification methods when a spec is available.
- **FR-007**: Verification method mismatches between spec and tests MUST produce findings with `category = "test-quality"` and a description that quotes both the spec's expected method and the test's actual method.
- **FR-008**: When a spec acceptance scenario does not specify a verification method, the test-quality agent MUST verify a test exists for the scenario but MUST NOT flag a verification method mismatch.
- **FR-009**: The correctness review agent MUST flag functions that call fallible operations and log-but-don't-return the error, with `category = "correctness"`.
- **FR-010**: Intentionally swallowed errors (with explicit documentation/comments) MUST produce Minor findings with reduced confidence (50-60), not Critical.
- **FR-011**: If `.specify/review-hints.md` exists, its content MUST be injected into every review agent's preamble, after the common preamble and before the agent-specific checklist.
- **FR-012**: If `.specify/review-hints.md` does not exist or is empty, review agents MUST run with their standard prompts (no error, no warning).
- **FR-013**: Test suite findings MUST appear in the `review-findings.md` report and in the gate outcome summary table as a separate row ("Test Suite (regression)").

### Key Entities

- **Test Command**: Auto-detected shell command for running the project's test suite. Detected from project structure, not configured by users.
- **Review Hints**: Optional flat markdown file at `.specify/review-hints.md` containing framework-specific patterns injected into review agent prompts. Projects organize content with markdown headings as they see fit; the injection mechanism reads and injects the entire file without parsing sections.
- **Spec Acceptance Scenario**: A Given/When/Then acceptance block in the spec that describes how to verify a requirement, including the verification method.

## Success Criteria

### Measurable Outcomes

- **SC-001**: When the fix loop introduces a regression that breaks an existing test, the regression is detected and reported as a Critical finding before the gate outcome is determined.
- **SC-002**: When a spec acceptance scenario specifies a verification method and the corresponding test uses a different method, the test-quality agent flags the mismatch.
- **SC-003**: When a function swallows an error from an API/IO call, the correctness agent flags it as a finding.
- **SC-004**: When `.specify/review-hints.md` exists, all 5 review agents receive its content in their prompts.
- **SC-005**: When no test command can be detected, the deep review completes normally with a logged warning (no crash, no false findings).

## Clarifications

### Session 2026-05-22

- Q: How should fix loop test failures interact with the round counter? → A: A test failure consumes a fix round, same as a review finding. The failure becomes a Critical finding and enters the next round for fixing. This is consistent with the existing fix loop model and avoids complexity of reverting fixes.
- Q: Can projects override the auto-detected test command? → A: Yes. Projects can set `test_command` in `deep-review-config.yml` to override auto-detection. If set, the configured command is used instead of auto-detection.
- Q: Should review-hints.md support structured sections per language/framework? → A: No. It is a flat markdown file. Projects can use markdown headings to organize content by framework or language, but the injection mechanism reads and injects the entire file without parsing sections.

## Assumptions

- Projects that use the deep review have a test suite that can be run via a single shell command.
- The test command produces a non-zero exit code on failure (standard behavior for all major test frameworks).
- The spec's acceptance scenarios follow the Given/When/Then format used by the speckit specify template.
- The `.specify/review-hints.md` file is plain markdown with no special syntax requirements (free-form framework documentation).
- Test suite execution time is bounded (default 5-minute timeout is sufficient for most projects).
