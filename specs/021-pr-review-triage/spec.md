# Feature Specification: PR Review Comment Triage

**Feature Branch**: `021-pr-review-triage`
**Created**: 2026-05-30
**Status**: Draft
**Input**: User description: "PR review comment triage skill for the spex-collab extension"

## User Scenarios & Testing

### User Story 1 - Autonomous Bot Comment Triage (Priority: P1)

A developer has pushed a PR and CodeRabbit/Copilot left review comments. The developer runs `/speckit-spex-collab-triage` to handle all bot comments in one pass. The skill fetches the PR comments, partitions them by author type, assesses each bot comment against the spec and code, applies valid fixes, rejects invalid ones with brief justification, and replies to each comment on the PR. All fixes are batched into a single commit and pushed.

**Why this priority**: Bot comments are the highest-volume, lowest-friction feedback. Automating their triage eliminates the most repetitive manual work.

**Independent Test**: Can be tested by creating a PR with bot review comments and running the skill. Verify: each bot comment gets a reply, valid fixes are applied in a single commit, invalid suggestions get a rejection with reasoning.

**Acceptance Scenarios**:

1. **Given** a PR with 5 CodeRabbit comments (3 valid, 2 invalid), **When** the user runs `/speckit-spex-collab-triage`, **Then** the 3 valid fixes are applied in one commit, all 5 comments receive replies, and rejected comments include a brief justification with spec reference when available.
2. **Given** a PR with Copilot review comments, **When** the skill handles them, **Then** handled comment threads are auto-resolved (Copilot is a single-pass reviewer).
3. **Given** a PR with CodeRabbit comments, **When** the skill handles them, **Then** comment threads are NOT auto-resolved (CodeRabbit self-resolves when satisfied).

---

### User Story 2 - Interactive Human Comment Review (Priority: P2)

A developer has a PR with comments from a human reviewer. The developer runs `/speckit-spex-collab-triage`. After processing bot comments, the skill enters interactive mode: for each human comment, it presents the comment, its assessment, and a proposed reply. The developer can approve, edit, or skip each reply before it is posted.

**Why this priority**: Human comments require careful handling. Auto-posting responses to human reviewers is inappropriate, but the skill can still draft replies and assess validity to save the developer time.

**Independent Test**: Can be tested by creating a PR with human review comments and running the skill interactively. Verify: each comment is presented with an assessment and proposed reply, only approved/edited replies are posted, skipped comments remain open.

**Acceptance Scenarios**:

1. **Given** a PR with 3 human review comments, **When** the user runs `/speckit-spex-collab-triage`, **Then** each comment is presented individually with the skill's assessment and a proposed reply, and the user must approve/edit/skip before the reply is posted.
2. **Given** the user skips a human comment, **When** the skill continues, **Then** no reply is posted for that comment and it remains open for the next triage pass.
3. **Given** the user edits a proposed reply, **When** they approve it, **Then** the edited version is posted as the reply.

---

### User Story 3 - Looped Bot Triage (Priority: P2)

A developer wants to continuously handle bot feedback as it arrives. They run `/loop 5m /speckit-spex-collab-triage`. The skill runs periodically, processes new or re-opened bot comments each pass, and reports a summary. When no open bot comments remain, the loop reports completion.

**Why this priority**: Bots may leave new comments after fixes are pushed (e.g., CodeRabbit re-reviews). The loop ensures all feedback is handled without manual re-invocation.

**Independent Test**: Can be tested by running the skill twice. First pass handles initial comments. After pushing fixes, the second pass picks up new comments from bots that re-reviewed. Verify: already-handled comments are not re-processed (unless new replies appeared).

**Acceptance Scenarios**:

1. **Given** a PR where all bot comments have been handled, **When** the skill runs again, **Then** it reports "0 open bot comments" and the loop can exit.
2. **Given** a handled comment receives a new reply from a bot, **When** the skill runs again, **Then** it re-evaluates that comment thread.
3. **Given** a bot comment thread that was resolved (by the bot or by the skill), **When** the skill runs again, **Then** it skips that thread.

---

### User Story 4 - Spec-Aware Assessment (Priority: P3)

A developer working on a spex-managed feature runs triage on a PR that has a spec. The skill uses the spec to validate bot suggestions, referencing specific requirements when rejecting invalid suggestions.

**Why this priority**: Spec-aware triage produces higher-quality rejections and catches cases where a bot suggestion would violate a spec requirement. But the skill must also work without a spec.

**Independent Test**: Can be tested by running triage on a PR with a spec directory. Verify: rejection replies reference spec requirements. Then test on a PR without a spec: verify the skill still works using code-only analysis.

**Acceptance Scenarios**:

1. **Given** a PR with spec at `specs/021-pr-review-triage/spec.md` and a bot comment suggesting a change that violates FR-003, **When** the skill assesses the comment, **Then** the rejection reply references FR-003 and explains the conflict.
2. **Given** a PR without any spec directory, **When** the skill runs, **Then** it operates using code-only analysis without errors.

---

### Edge Cases

- What happens when a bot comment references a file that was deleted in the PR?
- How does the skill handle a bot comment on a line that was already changed by another fix in the same batch?
- What happens when `gh` CLI is not authenticated or the PR is in a different repo?
- How does the skill behave when a bot leaves a summary comment (not attached to a specific line) vs. an inline code review comment?
- What happens when the PR has hundreds of bot comments (rate limiting)?

## Requirements

### Functional Requirements

- **FR-001**: The skill MUST auto-detect the open PR for the current branch via `gh pr view`, with `--pr <number>` override
- **FR-002**: The skill MUST partition PR comments into bot and human categories using the GitHub API author type (bot flag)
- **FR-003**: For each open bot comment, the skill MUST assess validity against the spec (when available) and the actual code
- **FR-004**: For valid bot suggestions, the skill MUST apply the fix to the local codebase
- **FR-005**: All applied fixes MUST be batched into a single commit and pushed at the end of the bot tier
- **FR-006**: For each bot comment (accepted or rejected), the skill MUST post a reply on the PR thread
- **FR-007**: Rejection replies MUST include a 1-2 sentence justification, with spec requirement reference when applicable
- **FR-008**: For human comments, the skill MUST present the comment, its assessment, and a proposed reply to the user for approval before posting
- **FR-009**: The skill MUST track handled comments via reply-based detection (check if we already replied) combined with a state file cache at `.specify/.pr-triage-state.json`
- **FR-010**: The skill MUST re-evaluate comment threads where new replies appeared after our last response
- **FR-011**: The skill MUST respect GitHub thread resolution status (resolved threads are skipped)
- **FR-012**: The skill MUST auto-resolve threads for single-pass bots (Copilot) after handling
- **FR-013**: The skill MUST NOT auto-resolve threads for self-resolving bots (CodeRabbit)
- **FR-014**: Bot resolution behavior MUST be configurable via hardcoded profiles with override in `collab-config.yml`
- **FR-015**: When running in loop mode, the skill MUST report a summary including count of open bot comments, handled comments, and pending human comments
- **FR-016**: The skill MUST work without a spec, falling back to code-only analysis

### Key Entities

- **PR Comment**: A review comment or inline code comment on a GitHub PR, with author, body, thread ID, resolution status, and associated file/line
- **Bot Profile**: Configuration for a known bot reviewer, including name, author login pattern, whether it self-resolves, and whether the skill should auto-resolve after handling
- **Triage State**: Per-PR state tracking which comment IDs have been handled, the timestamp of our last reply, and whether re-evaluation is needed

## Success Criteria

### Measurable Outcomes

- **SC-001**: All open bot comments on a PR are triaged (replied to with acceptance or rejection) in a single invocation
- **SC-002**: Valid bot suggestions result in working code fixes that pass existing tests
- **SC-003**: Rejection replies are concise (under 3 sentences) and reference the relevant spec requirement when one exists
- **SC-004**: Human reviewer comments are never auto-replied to without explicit user approval
- **SC-005**: Repeated invocations (loop mode) do not re-process already-handled comments unless new activity occurred on the thread
- **SC-006**: The skill completes a full triage pass on a PR with 20 bot comments in under 5 minutes

## Assumptions

- The `gh` CLI is authenticated and has access to the target repository
- Bot authors are identifiable via the GitHub API `type` field (value `"Bot"`)
- The skill runs in a git working directory that matches the PR's branch
- CodeRabbit and GitHub Copilot are the primary bot reviewers; other bots are handled with conservative defaults (no auto-resolve)
- The state file (`.specify/.pr-triage-state.json`) is gitignored and local to the working directory
- Reply detection uses a consistent signature pattern in posted replies to identify our own responses
