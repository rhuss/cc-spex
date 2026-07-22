# Feature Specification: Brainstorm Directory Sync

**Feature Branch**: `044-brainstorm-sync`
**Created**: 2026-07-15
**Status**: Draft
**Input**: User description: "Add --sync option for brainstorm directory maintenance"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Sync and Archive Completed Brainstorms (Priority: P1)

A user with 40+ brainstorm documents wants to clean up the directory so only active and parked brainstorms remain visible. They invoke the brainstorm skill with `--sync`, which scans all documents, detects which ones have been implemented (matching specs exist) or are in terminal states, presents a summary table, and moves confirmed documents to `brainstorm/attic/` after the user approves.

**Why this priority**: This is the core value of the feature. Without it, brainstorm directories grow unbounded and become noisy.

**Independent Test**: Can be fully tested by creating a brainstorm directory with documents in various states (active, spec-created, abandoned, parked), running `--sync`, and verifying the correct documents are moved to attic while active and parked ones remain.

**Acceptance Scenarios**:

1. **Given** a brainstorm directory with documents in mixed states (active, spec-created, abandoned, completed, parked), **When** `--sync` is invoked, **Then** a summary table is displayed showing each document's name, current status, inferred status (if changed), and proposed action (move/keep)
2. **Given** the summary table is displayed, **When** the user confirms the batch, **Then** terminal-state documents are moved to `brainstorm/attic/` and active/parked documents remain in `brainstorm/`
3. **Given** a brainstorm document with status "active" but a matching spec exists in `specs/`, **When** `--sync` scans it, **Then** the status is inferred as "spec-created" and the document is proposed for attic

---

### User Story 2 - Auto-detect Spec Matches by Filename (Priority: P1)

The sync process cross-references brainstorm documents against the `specs/` directory using filename slug overlap. A brainstorm like `04-rename-to-cc-spex.md` matches `specs/008-rename-to-cc-spex/` based on shared slug keywords. The overview table's Spec column is also checked for existing mappings.

**Why this priority**: Without spec cross-referencing, the sync would only work for documents whose status was manually updated, missing the majority of completed brainstorms.

**Independent Test**: Can be tested by creating brainstorm documents and matching spec directories with overlapping slugs, then verifying the sync correctly identifies the matches.

**Acceptance Scenarios**:

1. **Given** brainstorm `09-traits-to-extensions.md` and spec directory `specs/016-traits-to-extensions/`, **When** `--sync` runs, **Then** the brainstorm is identified as having a matching spec and proposed for attic
2. **Given** the overview table shows `| 17 | ... | backpressure-loops | spec-created | 024 |`, **When** `--sync` runs, **Then** the overview Spec column mapping is also used to confirm the match
3. **Given** a brainstorm with no matching spec slug and no overview mapping, **When** `--sync` runs, **Then** the document's status is taken as-is from its header metadata

---

### User Story 3 - Overview Regeneration After Sync (Priority: P2)

After moving documents to attic, the overview document (`brainstorm/00-overview.md`) is regenerated. Open threads from attic'd brainstorms are removed. The sessions table only lists documents still in the main directory. Parked ideas from parked documents remain.

**Why this priority**: The overview is the primary navigation tool for the brainstorm directory. Stale entries and orphaned threads undermine its usefulness.

**Independent Test**: Can be tested by running `--sync`, moving several documents to attic, and verifying the overview no longer references them in the sessions table or open threads section.

**Acceptance Scenarios**:

1. **Given** brainstorm #01 (spec-created) was moved to attic, **When** the overview is regenerated, **Then** #01 does not appear in the Sessions table
2. **Given** brainstorm #01 had 3 open threads in the overview, **When** #01 is moved to attic, **Then** those 3 threads are removed from the Open Threads section
3. **Given** brainstorm #31 is parked and stays in the main directory, **When** the overview is regenerated, **Then** #31 appears in both the Sessions table and the Parked Ideas section

---

### User Story 4 - Handle Unnumbered Brainstorm Files (Priority: P3)

The brainstorm directory may contain unnumbered files (e.g., `sdd-showcase-projects.md`, `worktree-flow-wrong.md`) that don't follow the `NN-*.md` convention. The sync process includes these files in the scan, classifies them by their Status field, and moves them to attic if they are in a terminal state.

**Why this priority**: Unnumbered files are an edge case but should not be silently ignored, as they may contain stale content.

**Independent Test**: Can be tested by creating unnumbered brainstorm files with various statuses and verifying the sync handles them correctly.

**Acceptance Scenarios**:

1. **Given** an unnumbered file `worktrees-trait.md` with status `spec-created`, **When** `--sync` runs, **Then** it appears in the summary table and is proposed for attic
2. **Given** an unnumbered file `sdd-showcase-projects.md` with status `active`, **When** `--sync` runs, **Then** it appears in the summary table with action "keep"

---

### Edge Cases

- What happens when `brainstorm/attic/` already exists with files from a previous sync? New files are added alongside existing ones. Filename conflicts (same name already in attic) are handled by skipping the move and warning the user.
- What happens when a brainstorm document has no Status field in its header? Treat it as "active" (keep in main directory).
- What happens when the `specs/` directory does not exist? Skip spec cross-referencing entirely; only use the document's own status field.
- What happens when the user rejects the entire batch at confirmation? No files are moved, no overview changes, no commit. The sync exits cleanly.
- What happens when `brainstorm/` directory is empty or doesn't exist? Report "No brainstorm documents found" and exit.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The `--sync` option MUST scan all `.md` files in `brainstorm/` (both numbered `NN-*.md` and unnumbered), excluding `00-overview.md` and `idea-inbox.md`
- **FR-002**: For each document, the system MUST parse the `Status` field from the document's header metadata
- **FR-003**: The system MUST cross-reference brainstorm documents against the `specs/` directory by comparing filename slug tokens (hyphen-separated words after the number prefix), requiring at least 2 matching tokens or a complete slug substring match
- **FR-004**: The system MUST also check the overview table's Spec column for existing spec number mappings
- **FR-005**: When a matching spec is found but the document's status has not been updated, the system MUST infer the status as `spec-created` and display the inferred status in the summary
- **FR-006**: Documents in terminal states (`spec-created`, `abandoned`, `completed`, `resolved`, `decided`) MUST be proposed for moving to `brainstorm/attic/`
- **FR-007**: Documents with status `active`, `parked`, `draft`, or `idea` MUST remain in the main `brainstorm/` directory. Documents with no parseable Status field default to `active` (keep)
- **FR-008**: The system MUST present an interactive summary table using AskUserQuestion with multiSelect, pre-selecting all attic candidates, showing: document name, current status, inferred status (if changed), and proposed action. Users can deselect items to override.
- **FR-009**: The user MUST confirm the batch before any moves are executed
- **FR-010**: After moving files, the system MUST update `brainstorm/00-overview.md` by selectively removing attic'd documents from the Sessions table and their associated entries from the Open Threads and Parked Ideas sections, preserving all other curated content
- **FR-011**: Open threads from attic'd brainstorms MUST be removed from the overview's Open Threads section
- **FR-012**: The system MUST use `git mv` for file moves (preserving history) and commit all changes (moved files, updated overview) after sync completes with message format: `chore(brainstorm): sync - archive N documents to attic`
- **FR-013**: The `brainstorm/attic/` directory MUST be created if it does not exist
- **FR-014**: The `idea-inbox.md` file MUST NOT be modified by the sync process
- **FR-015**: If a filename conflict occurs during the move (file already exists in attic), the system MUST skip that file and warn the user
- **FR-016**: When `--sync` is passed, the brainstorm command MUST short-circuit its normal flow (skip steps 2-7 of the brainstorm checklist) and execute the sync process directly, then exit after the sync commit

### Key Entities

- **Brainstorm Document**: A markdown file in `brainstorm/` containing a Status field and structured brainstorm content. Identified by filename pattern and header metadata.
- **Spec Directory**: A numbered directory in `specs/` containing a `spec.md` file. Used for cross-referencing to detect implemented brainstorms.
- **Overview Document**: `brainstorm/00-overview.md`, an index file with a sessions table, open threads, and parked ideas.
- **Attic Directory**: `brainstorm/attic/`, the archive destination for terminal-state brainstorm documents.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After running `--sync`, all terminal-state brainstorm documents are moved to `brainstorm/attic/`, reducing main directory file count to only active and parked documents
- **SC-002**: Brainstorm documents with matching specs that were incorrectly marked as "active" are detected and proposed for archival with 100% accuracy for slug-based matches
- **SC-003**: The overview document after sync contains zero references to attic'd documents in either the Sessions table or Open Threads section
- **SC-004**: Users can review every proposed action before any file moves occur
- **SC-005**: The sync completes in a single interactive session with one confirmation step

## Smoke Test

1. Run `--sync` on a brainstorm directory with 10+ documents in mixed states and verify the summary table correctly classifies each one
2. Confirm the batch and verify that terminal-state documents are in `brainstorm/attic/` and active/parked ones remain in `brainstorm/`
3. Open `brainstorm/00-overview.md` and verify it only lists remaining documents, with no orphaned open threads from archived brainstorms

## Clarifications

### Session 2026-07-15

- Q: How many hyphen-separated slug tokens must overlap to consider a brainstorm-to-spec match? → A: At least 2 matching tokens or a complete slug substring match. Single-token overlap is too broad and would produce false positives.
- Q: Should the interactive confirmation use batch yes/no or per-item selection? → A: Use AskUserQuestion with multiSelect, pre-selecting all attic candidates. Users can deselect individual items to override.
- Q: Should file moves use filesystem operations or git mv? → A: Use git mv to preserve file history in the repository.

## Assumptions

- The brainstorm skill is the only entry point for the `--sync` option; it is not a standalone command
- Slug matching uses keyword overlap (splitting on hyphens and comparing tokens), not exact string matching
- The sync is a read-then-confirm-then-act operation; no partial moves occur
- The git commit message follows the project's existing convention for brainstorm-related commits
- Documents without a parseable Status field default to "active" status
