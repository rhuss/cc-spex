# Feature Specification: Review Idea Inbox

**Feature Branch**: `031-review-idea-inbox`
**Created**: 2026-06-29
**Status**: Draft
**Input**: Brainstorm 26 — Review Idea Inbox

## User Scenarios & Testing

### User Story 1 - Triage Captures Out-of-Scope Ideas to Inbox (Priority: P1)

As a developer running PR comment triage, when reviewers flag issues that are valid but out of scope for the current PR, those ideas are captured to a persistent inbox instead of being lost.

**Why this priority**: This is the primary entry point for ideas. Triage is the structured review workflow where most bot and human review comments are processed, and the existing Step 15 mechanism already exists but rarely triggers.

**Independent Test**: Run `/speckit-spex-collab-triage` on a PR with at least 2 deferred findings on the same theme. Verify that the idea inbox file is created/updated with an entry for that theme.

**Acceptance Scenarios**:

1. **Given** a PR with 2 deferred findings about the same theme (e.g., "interface evolution"), **When** triage Step 15 runs, **Then** the findings are grouped by theme and the user is prompted to select which themes to capture
2. **Given** the user selects a theme for capture, **When** the selection is confirmed, **Then** an entry is appended to `brainstorm/idea-inbox.md` with source `triage`, the current date, PR reference, summary, and context snippet
3. **Given** a PR with 1 deferred and 1 rejected finding about the same theme, **When** triage Step 15 runs, **Then** both findings are grouped together (the threshold is 2+ findings per theme regardless of verdict mix, not 3+ rejected)
4. **Given** themes are presented to the user and the user selects "Skip all", **When** the selection is confirmed, **Then** no entries are written to the inbox and the triage completes normally

---

### User Story 2 - Brainstorm Skill Consumes Inbox Items (Priority: P1)

As a developer starting a brainstorm session, the brainstorm skill checks the idea inbox and offers accumulated ideas as seeds before starting its normal clarification flow.

**Why this priority**: Without consumption, the inbox is a write-only graveyard. The brainstorm skill is the natural consumer that turns captured seeds into actionable brainstorm documents.

**Independent Test**: Populate `brainstorm/idea-inbox.md` with 2-3 entries manually, then invoke `/speckit-spex-brainstorm`. Verify that the skill presents inbox items as brainstorm seeds before asking its normal "what do you want to brainstorm?" question.

**Acceptance Scenarios**:

1. **Given** `brainstorm/idea-inbox.md` exists with 3 entries, **When** the user invokes `/speckit-spex-brainstorm` without arguments, **Then** the skill presents the inbox items grouped by theme and asks which to explore
2. **Given** the user selects an inbox item to explore, **When** the brainstorm session completes and a brainstorm document is written, **Then** the consumed item is removed from the inbox file
3. **Given** `brainstorm/idea-inbox.md` does not exist or is empty, **When** the user invokes `/speckit-spex-brainstorm`, **Then** the skill proceeds with its normal clarification flow unchanged
4. **Given** the user declines all inbox items, **When** the brainstorm proceeds, **Then** the inbox items remain untouched and the normal flow begins

---

### User Story 3 - Deep Review Captures Notable Observations (Priority: P2)

As a developer running a deep code review, design-level observations that are not bugs are classified as "Notable" and captured to the idea inbox automatically.

**Why this priority**: The deep review's 5 agents often notice design patterns worth revisiting but currently have no way to surface them beyond Critical/Important/Minor bug classifications.

**Independent Test**: Run `/speckit-spex-deep-review-run` on code that has a design-level concern (e.g., an interface that will need to evolve). Verify that a Notable finding appears in `review-findings.md` and an entry is appended to the idea inbox.

**Acceptance Scenarios**:

1. **Given** a deep review agent identifies a design-level observation that is not a bug, **When** the agent classifies it, **Then** it uses the "Notable" verdict instead of Minor
2. **Given** a deep review completes with Notable findings, **When** the review findings are written, **Then** Notable findings appear in a dedicated "Notable Observations" section of `review-findings.md`
3. **Given** Notable findings exist after a deep review, **When** the findings report is finalized, **Then** each Notable finding is appended to `brainstorm/idea-inbox.md` with source `deep-review`

---

### User Story 4 - Conversational Nudge After Review Discussion (Priority: P3)

As a developer who processed PR reviews conversationally (outside the triage pipeline), a gentle nudge reminds me to capture any out-of-scope ideas that surfaced.

**Why this priority**: This is the lightest-touch intervention. It covers the conversational path but relies on the user to act — no automatic capture.

**Independent Test**: Process a PR review conversationally where comments include phrases like "out of scope" or "worth considering later". Verify that a suggestion appears at the end of the discussion mentioning the idea inbox.

**Acceptance Scenarios**:

1. **Given** a review discussion contains deferred-idea signals ("out of scope", "worth considering later", "design tension", "follow-up", "for a future PR"), **When** the review discussion concludes, **Then** a one-line suggestion is displayed mentioning the idea inbox and `/speckit-spex-brainstorm`
2. **Given** a review discussion has no deferred-idea signals, **When** the review discussion concludes, **Then** no nudge is displayed
3. **Given** the nudge is displayed, **When** the user reads it, **Then** no automatic action is taken — the user decides whether to act

---

### User Story 5 - README Documents Idea Capture Workflow (Priority: P2)

As a new user of cc-spex, I can learn about the idea capture workflow from the README, understanding how ideas flow from reviews into the inbox and from the inbox into brainstorm documents.

**Why this priority**: Documentation makes the feature discoverable. Without it, users won't know the inbox exists or how to use it.

**Independent Test**: Read the README section and verify it explains: the problem, the inbox mechanism, all review sources, and how to consume inbox items.

**Acceptance Scenarios**:

1. **Given** the README exists, **When** a user reads the "Idea Capture During Reviews" section, **Then** they find an explanation of why review ideas get lost and how the inbox solves this
2. **Given** the README section exists, **When** a user reads it, **Then** it describes all three review sources (triage, deep review, conversational nudge) and how each feeds the inbox
3. **Given** the README section exists, **When** a user reads it, **Then** it explains how to consume inbox items via `/speckit-spex-brainstorm`

---

### Edge Cases

- What happens when the inbox file is deleted while items are pending? (The brainstorm skill and triage should handle a missing file gracefully — create it when writing, skip reading when absent)
- What happens when two concurrent triage sessions try to write to the inbox simultaneously? (Append-only operations minimize conflicts; last-write-wins is acceptable since entries are independent)
- What happens when an inbox entry references a PR that has been merged and deleted? (Entries are self-contained with enough context to be useful without the original PR)
- What happens when the deep review produces many Notable findings? (Each is a separate inbox entry; no aggregation — the brainstorm skill groups by theme when presenting)

## Requirements

### Functional Requirements

- **FR-001**: The idea inbox file MUST be located at `brainstorm/idea-inbox.md` and committed to the repository
- **FR-002**: Each inbox entry MUST contain: theme slug (as heading), source (triage/deep-review/conversation), date, PR/feature reference, summary (1-2 sentences), and context snippet
- **FR-003**: Triage Step 15 MUST group deferred and rejected findings by theme and trigger when any cluster has 2+ findings regardless of verdict mix
- **FR-004**: Triage Step 15 MUST write selected themes to the inbox instead of invoking the brainstorm skill directly
- **FR-005**: Unselected themes in triage Step 15 MUST be discarded without writing to the inbox
- **FR-006**: The deep review agent classification MUST include a "Notable" verdict alongside Critical, Important, and Minor
- **FR-007**: Notable findings MUST be collected into a dedicated "Notable Observations" section of `review-findings.md`
- **FR-008**: Notable findings MUST be appended to the idea inbox with source `deep-review`
- **FR-009**: The brainstorm skill MUST check the inbox during step 2 (explore context) and offer accumulated items as brainstorm seeds
- **FR-010**: Consumed inbox items MUST be removed from the inbox file when a brainstorm document is created from them
- **FR-011**: The conversational nudge MUST detect deferred-idea signals in review discussions and display a one-line suggestion
- **FR-012**: The conversational nudge MUST NOT take any automatic action — no writing to inbox, no blocking
- **FR-013**: The README MUST include an "Idea Capture During Reviews" section explaining the workflow
- **FR-014**: The inbox file MUST be created automatically when the first entry is written (no manual setup required)

### Key Entities

- **Inbox Entry**: A single idea captured from a review source, containing theme, source, date, reference, summary, and context
- **Theme Cluster**: A grouping of 2+ triage findings that share the same theme, used to trigger inbox capture
- **Notable Finding**: A deep review observation classified as design-level rather than a bug, captured to both review-findings.md and the inbox

## Success Criteria

### Measurable Outcomes

- **SC-001**: Out-of-scope ideas from reviews are captured to a persistent file instead of being lost in conversation history
- **SC-002**: The brainstorm skill surfaces accumulated inbox items within the first interaction turn when items exist
- **SC-003**: Triage Step 15 triggers on thematic clusters of 2+ findings instead of requiring 3+ rejected findings
- **SC-004**: Deep review agents can classify design-level observations separately from bugs
- **SC-005**: New users can discover the idea capture workflow from the README without prior knowledge

## Smoke Test

1. Run triage on a PR with deferred findings, verify the inbox prompt appears and entries are written to `brainstorm/idea-inbox.md`
2. With inbox entries present, invoke `/speckit-spex-brainstorm` and verify the skill offers inbox items as seeds before its normal flow
3. After creating a brainstorm doc from an inbox item, verify the consumed entry is removed from the inbox

## Assumptions

- The `brainstorm/` directory already exists in projects using cc-spex (created by the brainstorm skill)
- The inbox is a single flat file, not a directory of individual entry files
- Inbox entries are independent and append-only; no cross-referencing or deduplication is performed at write time
- The conversational nudge relies on signal detection in conversation text, which may have false positives or negatives
- Manual pruning of stale inbox entries is acceptable for the initial version (no automated cleanup)
