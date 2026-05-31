# Tasks: PR Review Comment Triage

**Input**: Design documents from `specs/021-pr-review-triage/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: Register the new command in the spex-collab extension

- [X] T001 [P] Update extension manifest to register triage command in `spex/extensions/spex-collab/extension.yml`
- [X] T002 [P] Add triage bot-profiles section to config template in `spex/extensions/spex-collab/config-template.yml`

---

## Phase 2: Foundational (State Management)

**Purpose**: State management script that all user stories depend on

- [X] T003 Create state management script at `spex/scripts/spex-triage-state.sh` with operations: init (create empty PR entry), get (read comment state), set (mark comment handled), list-unhandled (find new comments), cleanup (remove old PR entries). Schema per `data-model.md` TriageState/HandledComment entities. File location: `.specify/.pr-triage-state.json`, keyed by PR number.
- [X] T003a [P] Add `.specify/.pr-triage-state.json` to `.gitignore` (state file is local-only per spec assumptions)

**Checkpoint**: State script ready. User story implementation can begin.

---

## Phase 3: User Story 1 - Autonomous Bot Comment Triage (Priority: P1) MVP

**Goal**: Triage all bot comments on a PR in one pass: fetch, assess, apply valid fixes, reject invalid, reply, batch commit and push.

**Independent Test**: Create a PR with bot review comments, run `/speckit-spex-collab-triage`, verify each bot comment gets a reply, valid fixes applied in single commit, invalid suggestions rejected with reasoning.

### Implementation for User Story 1

- [X] T004 [US1] Create triage skill file at `spex/extensions/spex-collab/commands/speckit.spex-collab.triage.md` with frontmatter, PR detection via `gh pr view` with `--pr <number>` override (FR-001), and GraphQL query to fetch all review threads with resolution status, comments, and author types (FR-002, FR-011). Include bot/human partitioning logic using `user.type == "Bot"`.
- [X] T005 [US1] Add bot comment assessment and fix application section to `spex/extensions/spex-collab/commands/speckit.spex-collab.triage.md`: for each unresolved bot thread, assess the suggestion against the actual code (FR-003), apply valid fixes using the Edit tool (FR-004), track which fixes were applied for the batch commit.
- [X] T006 [US1] Add batch commit and push section to `spex/extensions/spex-collab/commands/speckit.spex-collab.triage.md`: after processing all bot comments, stage all changes, create single commit with message `fix: apply bot review suggestions (#<PR>)` and body listing each addressed comment ID with 1-line summary (FR-005), push to remote.
- [X] T007 [US1] Add reply posting section to `spex/extensions/spex-collab/commands/speckit.spex-collab.triage.md`: for each bot comment, post reply via REST `POST /repos/{owner}/{repo}/pulls/{pull_number}/comments/{comment_id}/replies` with `<!-- spex-triage -->` signature (FR-006). Acceptance replies include 1-sentence summary + commit SHA link (FR-007a). Rejection replies include 1-2 sentence justification (FR-007).
- [X] T008 [US1] Add bot profile matching and thread resolution to `spex/extensions/spex-collab/commands/speckit.spex-collab.triage.md`: match bot login against hardcoded profiles (CodeRabbit: no auto-resolve, Copilot: auto-resolve) and config overrides from `.specify/collab-config.yml` (FR-014). Auto-resolve threads for Copilot via GraphQL `resolveReviewThread` mutation (FR-012). Skip resolution for CodeRabbit (FR-013). Unknown bots use conservative defaults (FR-017).
- [X] T009 [US1] Add state tracking integration to `spex/extensions/spex-collab/commands/speckit.spex-collab.triage.md`: call `spex-triage-state.sh` to check handled comments before processing, update state after each reply is posted (FR-009). Skip already-handled comments where no new replies appeared.
- [X] T010 [US1] Add error handling section to `spex/extensions/spex-collab/commands/speckit.spex-collab.triage.md`: gh auth failure detection and exit (no partial processing), GitHub API rate limit detection (save progress to state, exit cleanly), fix application failure (skip fix, reply noting failure, continue), commit/push failure (report error, keep changes in working tree, skip reply posting for accepted comments), no open PR (report and exit).

**Checkpoint**: Bot comment triage fully functional. Run on a PR with CodeRabbit/Copilot comments to validate. Time the triage pass to verify SC-006 (20 comments in under 5 minutes).

---

## Phase 4: User Story 2 - Interactive Human Comment Review (Priority: P2)

**Goal**: Present each human review comment with an assessment verdict and proposed reply for user approval before posting.

**Independent Test**: Create a PR with human review comments, run the skill, verify each comment is presented with assessment (agree/disagree/partial + reasoning) and proposed reply, only approved/edited replies posted, skipped comments remain open.

### Implementation for User Story 2

- [X] T011 [US2] Add human comment interactive flow to `spex/extensions/spex-collab/commands/speckit.spex-collab.triage.md`: after bot tier completes, process human comment threads. For each unresolved human thread, present the comment text, assessment verdict (agree/disagree/partial with 1-2 sentence reasoning), and proposed reply. Use AskUserQuestion for approve/edit/skip. Post approved or edited replies with signature. Skip leaves comment open. Update state file for each handled human comment (FR-008).

**Checkpoint**: Full two-tier triage works (bot autonomous + human interactive).

---

## Phase 5: User Story 3 - Looped Bot Triage (Priority: P2)

**Goal**: Support repeated invocations that process only new or re-opened comments, with summary output for loop mode.

**Independent Test**: Run skill twice on same PR. First pass handles initial comments. Second pass picks up new comments only. Verify already-handled comments not re-processed unless new replies appeared.

### Implementation for User Story 3

- [X] T012 [US3] Add re-evaluation logic to `spex/extensions/spex-collab/commands/speckit.spex-collab.triage.md`: for handled comment threads, check if new replies appeared after our last response timestamp by comparing thread comment timestamps against `handledAt` in state (FR-010). If new activity detected, re-process the thread.
- [X] T013 [US3] Add loop mode summary output to `spex/extensions/spex-collab/commands/speckit.spex-collab.triage.md`: at the end of each triage pass, report counts of open bot comments remaining, comments handled this pass (accepted/rejected), and pending human comments (FR-015). When 0 open bot comments remain, report completion so the loop can exit.

**Checkpoint**: Loop mode works. `/loop 5m /speckit-spex-collab-triage` processes incrementally.

---

## Phase 6: User Story 4 - Spec-Aware Assessment (Priority: P3)

**Goal**: Use the feature spec to validate bot suggestions and reference specific requirements in rejection replies.

**Independent Test**: Run triage on PR with spec, verify rejection replies reference spec requirements. Run on PR without spec, verify code-only analysis works without errors.

### Implementation for User Story 4

- [X] T014 [US4] Add spec-aware assessment to `spex/extensions/spex-collab/commands/speckit.spex-collab.triage.md`: detect spec via `.specify/scripts/bash/check-prerequisites.sh --json --paths-only`, load spec.md if found, include spec requirements as context when assessing bot suggestions. Rejection replies reference specific FR/requirement IDs when the suggestion conflicts with a spec requirement. Fall back to code-only analysis when no spec exists (FR-016 already handled, this enhances FR-003 and FR-007).

**Checkpoint**: Spec-aware rejections work. All four user stories functional.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Edge cases, documentation, and validation

- [X] T015 Add edge case handling to `spex/extensions/spex-collab/commands/speckit.spex-collab.triage.md`: deleted file reference (skip fix, reply noting file deleted), conflicting fixes within batch (skip later fix, reply noting conflict, report in summary), summary comments (skip non-inline bot comments), high volume batching (process in batches of 50 for PRs with 100+ comments, respect rate limits), draft PR support (no behavior change).
- [X] T016 [P] Update README.md: add triage command to Commands Reference table, update spex-collab extension description, add triage to workflow section if applicable.
- [X] T017 [P] Update `spex/docs/help.md`: add triage to quick reference commands under spex-collab extension.
- [X] T018 Run quickstart.md validation against implemented skill to verify usage instructions are accurate.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies, can start immediately
- **Foundational (Phase 2)**: No dependency on Phase 1 (different files), but logically should complete first
- **User Story 1 (Phase 3)**: Depends on Phase 1 (extension registered) and Phase 2 (state script exists)
- **User Story 2 (Phase 4)**: Depends on User Story 1 (skill file must exist with bot tier)
- **User Story 3 (Phase 5)**: Depends on User Story 1 (state tracking must exist)
- **User Story 4 (Phase 6)**: Depends on User Story 1 (assessment logic must exist to enhance)
- **Polish (Phase 7)**: Depends on User Story 1 at minimum; ideally after all stories

### User Story Dependencies

- **User Story 1 (P1)**: Independent after foundational. This is the MVP.
- **User Story 2 (P2)**: Adds to US1's skill file (human tier after bot tier). Sequential dependency.
- **User Story 3 (P2)**: Adds re-evaluation logic on top of US1's state tracking. Sequential dependency.
- **User Story 4 (P3)**: Enhances US1's assessment logic with spec context. Sequential dependency.

### Within Each User Story

- T004 creates the skill file, T005-T010 add sections to it (sequential within US1)
- T011 adds human tier (after bot tier exists)
- T012-T013 add loop mode features
- T014 enhances assessment with spec awareness

### Parallel Opportunities

- T001 and T002 can run in parallel (different files in Phase 1)
- T003 can run in parallel with T001/T002 (different file)
- T016 and T017 can run in parallel (different doc files in Phase 7)

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001, T002)
2. Complete Phase 2: Foundational (T003)
3. Complete Phase 3: User Story 1 (T004-T010)
4. **STOP and VALIDATE**: Test on a real PR with bot comments
5. The skill is usable at this point for the most common use case

### Incremental Delivery

1. Setup + Foundational -> Extension registered, state script ready
2. Add User Story 1 -> Bot triage works -> **MVP complete**
3. Add User Story 2 -> Human comments handled interactively
4. Add User Story 3 -> Loop mode supported for continuous triage
5. Add User Story 4 -> Spec-aware rejections
6. Polish -> Edge cases, documentation

### Notes

- All user stories modify the same skill file (`speckit.spex-collab.triage.md`), so they are sequential
- The skill file is a markdown command file, not compiled code. Each task adds a section.
- State management uses `spex-triage-state.sh` per Constitution VII (State as Scripts)
