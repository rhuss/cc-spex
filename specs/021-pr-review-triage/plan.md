# Implementation Plan: PR Review Comment Triage

**Branch**: `021-pr-review-triage` | **Date**: 2026-05-31 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/021-pr-review-triage/spec.md`

## Summary

Add a `/speckit-spex-collab-triage` command to the spex-collab extension that triages PR review comments. The skill fetches review threads via the GitHub API (GraphQL for threads + resolution, REST for replies), partitions comments by author type (bot vs human), autonomously processes bot comments (assess, apply valid fixes, reject invalid, reply, optionally auto-resolve), and interactively presents human comments for approval. State is tracked in `.specify/.pr-triage-state.json` to support loop mode without re-processing handled comments.

## Technical Context

**Language/Version**: Bash (POSIX-compatible), Markdown (skill file)
**Primary Dependencies**: `gh` CLI (authenticated), `jq`, `git`
**Storage**: JSON state file (`.specify/.pr-triage-state.json`), YAML config override (`.specify/collab-config.yml`)
**Testing**: Manual testing via real PRs with bot and human comments
**Target Platform**: Claude Code CLI (macOS/Linux)
**Project Type**: Claude Code plugin (spec-kit extension command)
**Performance Goals**: Full triage of 20 bot comments in under 5 minutes (SC-006)
**Constraints**: GitHub API rate limits (5000 req/hr for authenticated users), GraphQL required for thread resolution
**Scale/Scope**: Typical PR has 1-30 review comments; edge case handling for 100+

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-Guided Development | PASS | Following full SDD workflow |
| II. Extension Architecture | PASS | New command in existing spex-collab extension with manifest update |
| III. Extension Composability | PASS | Self-contained command, no cross-extension modification |
| IV. Quality Gates | PASS | Spec reviewed and clarified before planning |
| V. Naming Discipline | PASS | Command: `speckit.spex-collab.triage`, skill prefix: `speckit-spex-collab-triage` |
| VI. Skill Autonomy | PASS | Single purpose: triage PR comments. No mixing of workflow/review/infrastructure roles |
| VII. State as Scripts | PASS | State management will use a dedicated script (`spex-triage-state.sh`) for state file operations |

## Project Structure

### Documentation (this feature)

```text
specs/021-pr-review-triage/
├── plan.md              # This file
├── research.md          # Phase 0 output (complete)
├── data-model.md        # Phase 1 output (complete)
├── quickstart.md        # Phase 1 output
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```text
spex/
├── extensions/
│   └── spex-collab/
│       ├── extension.yml                              # Update: add triage command
│       ├── config-template.yml                        # Update: add triage bot-profiles section
│       └── commands/
│           └── speckit.spex-collab.triage.md           # New: triage skill
├── scripts/
│   └── spex-triage-state.sh                           # New: state file management script
```

**Structure Decision**: The triage command lives under the existing spex-collab extension. One new command file, one new state management script, and updates to the extension manifest and config template.

## Design Decisions

### D-001: GraphQL-primary for thread fetching

Use GraphQL `reviewThreads` as the primary data source for fetching PR review threads. This provides thread-level grouping, resolution status, and node IDs for mutations in a single query. REST is used only for posting replies (no GraphQL mutation for threaded replies).

### D-002: AI-driven fix application

Bot suggestions come in diverse formats (GitHub suggestion blocks, prose descriptions, code snippets). Rather than parsing each format, the AI agent reads the suggestion, understands intent, and applies the fix using the Edit tool. This is the natural approach for a skill running inside Claude Code.

### D-003: Two-tier processing

Bot comments are processed first (autonomous), then human comments (interactive). This matches the user story priorities and ensures the batch commit contains only bot-suggested fixes. Human comment fixes (if any) would be separate commits.

### D-004: State script per constitution

Per Constitution VII (State as Scripts), all state file operations (create, read, update, query) go through `spex-triage-state.sh`. The skill markdown delegates to this script rather than embedding `jq` pipelines.

### D-005: Reply-based detection as primary, state file as cache

The `<!-- spex-triage -->` signature in posted replies is the source of truth for "already handled." The state file is a performance cache to avoid re-scanning all replies on every invocation. If the state file is deleted, the skill can reconstruct state from reply signatures (slower but correct).

## Implementation Phases

### Phase 1: Bot Comment Triage (User Story 1, P1)

**Scope**: FR-001 through FR-007a, FR-009, FR-011, FR-012, FR-013, FR-014, FR-016, FR-017, error handling, state management.

**Deliverables**:
1. `spex-triage-state.sh` script (create, read, update, query operations)
2. `speckit.spex-collab.triage.md` skill with bot triage flow
3. Updated `extension.yml` with triage command registration
4. Updated `config-template.yml` with triage bot-profiles section

**Acceptance**: Run on a PR with bot comments, verify replies posted, fixes applied in single commit, state tracked.

### Phase 2: Human Comment Review (User Story 2, P2)

**Scope**: FR-008, interactive presentation with assessment verdict.

**Deliverables**:
1. Interactive human comment section in triage skill
2. AskUserQuestion integration for approve/edit/skip flow

**Acceptance**: Run on a PR with human comments, verify interactive presentation with verdict, only approved replies posted.

### Phase 3: Loop Mode + Spec-Aware Assessment (User Stories 3 & 4, P2/P3)

**Scope**: FR-010, FR-015, spec-aware assessment, loop mode summary.

**Deliverables**:
1. Re-evaluation logic for threads with new activity
2. Loop mode summary output
3. Spec loading and requirement-referenced rejections

**Acceptance**: Run twice on same PR, verify no re-processing. Run with spec, verify rejection replies reference spec requirements.

### Phase 4: Documentation & Polish

**Scope**: Update README.md, help.md, edge case handling.

**Deliverables**:
1. README.md command reference update
2. help.md quick reference update
3. Edge case handling (deleted files, conflicting fixes, summary comments, high volume)

## Complexity Tracking

No constitution violations. No complexity justifications needed.
