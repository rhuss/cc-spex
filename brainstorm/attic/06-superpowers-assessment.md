# Superpowers Integration Assessment

**Date:** 2026-03-30
**Trigger:** Honest evaluation of how much value spex extracts from obra/superpowers

## Context

spex builds on [obra/superpowers](https://github.com/obra/superpowers) for process discipline, anti-rationalization patterns, and verification gates. This brainstorm assessed how much of superpowers we actually use and whether the integration delivers meaningful value.

## Findings

### Coverage: ~33% directly adapted

Upstream superpowers has 12 skills. spex's adoption:

| Status | Count | Skills |
|--------|-------|--------|
| Adapted/merged | 4 | brainstorming, writing-plans (reference-only), verification-before-completion, using-superpowers |
| Previously referenced (now companion) | 2 | test-driven-development, systematic-debugging |
| Dropped references (spex has own) | 2 | using-git-worktrees (spex:worktree), dispatching-parallel-agents (spex:teams-orchestrate) |
| Not used | 4 | subagent-driven-development, executing-plans, requesting/receiving-code-review, finishing-a-development-branch |

Even within adapted skills, we cherry-pick specific patterns. Actual upstream content by line count is closer to 15-20%.

### What's genuinely valuable

1. **Anti-rationalization patterns** in using-superpowers ("This is too simple for a spec" = WRONG). Single most impactful piece.
2. **The Iron Law** from verification-before-completion: "Evidence before claims."
3. **Red flag scanning patterns** for detecting vague placeholder language in plans.
4. **Scope assessment** patterns for multi-subsystem detection.

These are all relatively stable upstream and don't change much between syncs.

### What's over-engineered

1. **Sync mechanism**: 373-line `update-superpowers` command for marginal upstream changes. Latest sync integrated 3 improvements.
2. **"Referenced" skills were a fiction**: Listed 4 upstream skills as "compatible" but never shipped them. Users had no way to use them without installing superpowers separately.
3. **Overlay content is thin**: 3 superpowers overlays total ~50-60 lines of actual content. The trait machinery (763-line script) is dramatically heavier.

### Honest verdict

| Aspect | Rating |
|--------|--------|
| Core discipline patterns (anti-rationalization, Iron Law) | High value |
| Overlay quality gates (review-spec, review-code, verification) | Medium value |
| Sync mechanism | Low value, over-engineered |
| Ongoing sync ROI | Marginal, upstream is mature |

## Decisions

### Companion plugin model (adopted)

Instead of copying upstream skills (drift, duplication), recommend superpowers as a companion plugin:

- **init-time detection**: spex:init checks available skills for upstream superpowers presence
- **Hint when missing**: Shows install recommendation for TDD and systematic-debugging
- **No conflicts**: Skills are namespaced (`spex:verification-before-completion` vs `verification-before-completion`)
- **Hooks don't interfere**: Different lifecycle events (spex: PreToolUse/UserPromptSubmit, superpowers: SessionStart)

### Trimmed referenced skills to 2

Dropped `using-git-worktrees` and `dispatching-parallel-agents` from recommendations. spex has its own implementations (`spex:worktree`, `spex:teams-orchestrate`) that are tailored to the spec workflow.

### Open question: sync mechanism future

The sync mechanism remains for now. Future consideration: absorb-and-freeze (final sync, then remove the mechanism). The valuable patterns are stable and unlikely to change significantly.

## Changes Made

- `spex/commands/init.md`: Added Step 3b for superpowers companion detection and hint
- `spex/skills/using-superpowers/SKILL.md`: Replaced "Compatible Superpowers Skills" (4 items) with "Companion: Superpowers Plugin" (2 items, explicit install instructions)
- `spex/.superpowers-sync`: Renamed `referenced_skills` to `companion_skills`, added `dropped_references` with rationale
