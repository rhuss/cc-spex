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

- **Deleted file reference**: When a bot comment references a file that was deleted in the PR, the skill MUST skip the fix, reply noting the target file no longer exists, and continue processing remaining comments.
- **Conflicting fixes within a batch**: When a bot comment targets a line already changed by another fix in the same batch, the skill MUST skip the later fix, reply noting the conflict, and continue. The skipped fix is reported in the summary for manual review.
- **Summary comments vs. inline comments**: When a bot leaves a summary comment (not attached to a specific file/line), the skill MUST skip it during triage (summary comments are informational, not actionable code suggestions).
- **High volume (rate limiting)**: When a PR has more than 100 bot comments, the skill MUST process them in batches of 50, respecting GitHub API rate limits. If a rate limit is hit, the skill pauses, reports progress, and resumes on the next invocation.
- **Draft PRs**: The skill MUST work on draft PRs the same as regular PRs. PR state does not affect triage behavior.

## Clarifications

### Session 2026-05-30

- Q: What should acceptance replies contain when a bot suggestion is applied? → A: 1-sentence summary of the change applied, plus a link to the batch commit SHA
- Q: How is the state file keyed to avoid collisions across PRs? → A: Single file with PR number as top-level key (e.g., `{"142": {...}, "145": {...}}`)
- Q: What does the human comment assessment presentation include? → A: Validity verdict (agree/disagree/partial) with 1-2 sentence reasoning, then proposed reply
- Q: Should the skill support autonomous mode (`.spex-state`)? → A: No, this skill is always user-invoked (directly or via `/loop`), never part of the autonomous ship pipeline
- Q: What should the batch commit message format be? → A: Structured: `fix: apply bot review suggestions (#PR)` with body listing each addressed comment ID and 1-line summary

## Dependencies

- **`gh` CLI**: Authenticated and with access to the target repository (for PR detection, comment fetching, reply posting, thread resolution)
- **`jq`**: For JSON parsing of GitHub API responses and state file management
- **`git`**: For applying fixes, committing, and pushing
- **GitHub API**: REST API access for PR comments, reviews, and thread operations
- **spex-collab extension**: This skill is part of the spex-collab extension bundle

## Out of Scope

- **PR description comments**: Only review comments (inline and conversation) are processed, not comments on the PR description itself
- **Commit comments**: Comments on individual commits (outside the PR review context) are not processed
- **Cross-repo PRs**: The skill only operates on PRs in the current repository
- **Comment authoring**: The skill does not create new review comments, only replies to existing ones
- **Merge conflict resolution**: If a fix cannot be applied cleanly, it is skipped, not force-applied

## Requirements

### Functional Requirements

- **FR-001**: The skill MUST auto-detect the open PR for the current branch via `gh pr view`, with `--pr <number>` override
- **FR-002**: The skill MUST partition PR comments into bot and human categories using the GitHub API author type (bot flag)
- **FR-003**: For each open bot comment, the skill MUST assess validity against the spec (when available) and the actual code
- **FR-004**: For valid bot suggestions, the skill MUST apply the fix to the local codebase
- **FR-005**: All applied fixes MUST be batched into a single commit with message `fix: apply bot review suggestions (#<PR>)` and a body listing each addressed comment ID with a 1-line summary, then pushed at the end of the bot tier
- **FR-006**: For each bot comment (accepted or rejected), the skill MUST post a reply on the PR thread
- **FR-007**: Rejection replies MUST include a 1-2 sentence justification, with spec requirement reference when applicable
- **FR-007a**: Acceptance replies MUST include a 1-sentence summary of the change applied and a link to the batch commit SHA
- **FR-008**: For human comments, the skill MUST present the comment with an assessment (validity verdict: agree/disagree/partial, plus 1-2 sentence reasoning) and a proposed reply, requiring user approval before posting
- **FR-009**: The skill MUST track handled comments via reply-based detection (check if we already replied) combined with a state file cache at `.specify/.pr-triage-state.json`, keyed by PR number (single file, PR number as top-level JSON key)
- **FR-010**: The skill MUST re-evaluate comment threads where new replies appeared after our last response
- **FR-011**: The skill MUST respect GitHub thread resolution status (resolved threads are skipped)
- **FR-012**: The skill MUST auto-resolve threads for single-pass bots (Copilot) after handling
- **FR-013**: The skill MUST NOT auto-resolve threads for self-resolving bots (CodeRabbit)
- **FR-014**: Bot resolution behavior MUST be configurable via hardcoded profiles with override in `collab-config.yml`
- **FR-015**: When running in loop mode, the skill MUST report a summary including count of open bot comments, handled comments, and pending human comments
- **FR-016**: The skill MUST work without a spec, falling back to code-only analysis
- **FR-017**: For bots not matching a known profile, the skill MUST use conservative defaults: process comments normally but do NOT auto-resolve threads

### Error Handling

- **`gh` CLI not authenticated**: The skill MUST detect authentication failure on first API call, report a clear error message ("gh CLI not authenticated, run `gh auth login`"), and exit without partial processing
- **GitHub API rate limit**: The skill MUST detect 403/429 responses, report remaining rate limit info, save progress to the state file, and exit cleanly so the next invocation resumes where it left off
- **Fix application failure**: When a suggested code fix cannot be applied (file changed, line mismatch, syntax error), the skill MUST skip that fix, reply to the comment noting the fix could not be applied automatically, and continue processing
- **Commit/push failure**: If the batch commit or push fails (e.g., branch protection, remote rejection), the skill MUST report the error, keep the applied fixes in the working tree (do not revert), and skip reply posting for accepted comments (since the fixes aren't on the remote yet)
- **No open PR for branch**: If `gh pr view` finds no open PR for the current branch, the skill MUST report "No open PR found for branch `<branch>`" and exit

### Reply Signature

All replies posted by the skill MUST include a signature footer to enable reply-based detection on subsequent runs:

```
<!-- spex-triage -->
```

This HTML comment is invisible in rendered markdown but detectable via the GitHub API. The skill identifies its own prior replies by checking for this marker.

### Bot Profiles and Configuration

Hardcoded bot profiles:

| Bot | Login Pattern | Self-Resolves | Auto-Resolve After Handling |
|-----|--------------|---------------|----------------------------|
| CodeRabbit | `coderabbitai[bot]` | Yes | No |
| GitHub Copilot | `copilot[bot]` | No | Yes |

Override via `.specify/collab-config.yml` (optional, created manually):

```yaml
triage:
  bot-profiles:
    - login: "my-custom-bot[bot]"
      self-resolves: false
      auto-resolve: true
  # Override built-in profiles
  overrides:
    coderabbitai[bot]:
      auto-resolve: true  # Override default behavior
```

The config file lives at `.specify/collab-config.yml` within the project root. If absent, only hardcoded profiles are used.

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
- CodeRabbit and GitHub Copilot are the primary bot reviewers; other bots are handled per FR-017
- The state file (`.specify/.pr-triage-state.json`) is gitignored and local to the working directory
- Reply detection uses the `<!-- spex-triage -->` signature (see Reply Signature section)
