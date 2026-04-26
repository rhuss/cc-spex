# Research: spex-collab Extension

**Date**: 2026-04-26

## Phase Boundary Mechanism

**Decision**: User-invocable `phase-manager` command, coordinated via `before_implement` hook instructions.

**Rationale**: spec-kit has no `after_implement_phase` lifecycle hook. Adding one requires upstream changes. A user-invocable command is pragmatic and works within the existing architecture. The `before_implement` hook (phase-split) instructs the user on when to invoke phase-manager.

**Alternatives considered**:
- Wrapping `/speckit-implement`: Violates transparency requirement (FR-009) and constitution VI (skill autonomy)
- Upstream `after_implement_phase` hook: Out of scope, requires spec-kit changes
- Automatic detection via file watching: Overly complex for a Markdown+Bash extension

## Task Phase Detection

**Decision**: Parse `tasks.md` for heading-based groupings (`## US1:`, `## Phase 1:`, etc.).

**Rationale**: Matches existing task format from `/speckit-tasks`. User story grouping is the natural phase boundary since each story is independently testable.

**Parsing approach**: Read `tasks.md`, extract `##` headings, group tasks under each heading. Task IDs follow the `### T001` pattern.

## REVIEWERS.md Content Sourcing

**Decision**: Compose from existing artifacts rather than re-analyzing source material.

**Sources for spec PR**:
- `spec.md`: feature overview, scope boundaries, requirements summary
- `plan.md`: technical approach, key decisions
- `REVIEW-SPEC.md`: areas of concern flagged by spec review

**Sources for code PR**:
- `REVIEW-CODE.md`: compliance findings, focus areas
- `git diff --stat`: files changed summary
- `.spex-state`: phase plan for context

**Rationale**: Reusing review artifacts avoids duplicating analysis. REVIEWERS.md adds the human-readable narrative layer that guides reviewers through the material.

## State File Extension Strategy

**Decision**: Namespace spex-collab state under a `collab` key in `.spex-state`.

**Rationale**: Avoids polluting the top-level state namespace. Other extensions can add their own namespaced keys without collision. Uses `jq` for atomic updates consistent with existing state management.

**Update pattern**:
```bash
tmp=$(mktemp) && jq '.collab.completed_phases += [1]' .specify/.spex-state > "$tmp" && mv "$tmp" .specify/.spex-state
```

## PR Creation Strategy

**Decision**: Use `gh pr create --base main` with REVIEWERS.md content in PR body.

**Fallback**: If `gh` is not installed, warn and print the manual PR creation steps.

**PR body format**: Include the relevant REVIEWERS.md sections (spec or code phase) directly in the PR description so reviewers see guidance without navigating to a separate file.
