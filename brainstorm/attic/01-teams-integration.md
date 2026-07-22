# Brainstorm: Claude Code Agent Teams for SDD

**Date:** 2026-02-27
**Status:** spec-created
**Spec:** specs/005-teams-traits/

## Problem Framing

The SDD plugin executes implementation tasks sequentially within a single Claude Code session. Features with many independent tasks leave parallelism on the table. Claude Code Agent Teams (experimental) enables multi-session coordination where teammates work simultaneously, each in their own context window. The question: how should SDD integrate with this capability?

Key sub-questions explored:
- Which SDD workflow phase benefits most? (Answer: implementation)
- Should the lead implement or purely coordinate? (Answer: spec guardian for advanced use)
- Should integration be default or opt-in? (Answer: opt-in trait, due to experimental status and token cost)
- How to handle file conflicts? (Answer: git worktrees for isolation)
- How does beads fit? (Answer: bridge pattern, bootstrap before spawn, sync on completion)

## Approaches Considered

### A: Single "teams" trait with full spec guardian
- Pros: Maximum SDD integration, spec compliance enforcement, worktree isolation
- Cons: Most complex, highest token cost, all-or-nothing

### B: Single "teams" trait with lightweight coordination
- Pros: Simpler, file ownership instead of worktrees
- Cons: File conflicts possible, less rigorous spec compliance

### C: Pure CLAUDE.md-based guidance (no custom tooling)
- Pros: Simplest to implement, leverages CC Teams as designed
- Cons: Less control, no beads integration, no worktree enforcement

## Decision

Split into two traits with a dependency chain:
- **`teams-vanilla`** (Approach C): Pure CC Teams orchestration via overlay + skill. No worktrees, no beads, just parallel task execution.
- **`teams-spec`** (Approach A): Full spec guardian with worktree isolation, review-code integration, and beads bridge. Depends on teams-vanilla + superpowers + beads.

This gives users a progressive adoption path: start with vanilla parallelism, upgrade to spec guardian when ready. The trait dependency model was introduced to support this layering.

## Open Threads

- Constitution Principle III (Trait Composability) may warrant a formal amendment to acknowledge trait dependencies as a valid pattern
- The "5 teammate maximum" could be made configurable in a future iteration
- CC Teams is experimental; traits will need updating if the API changes significantly
