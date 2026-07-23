# Brainstorm: Smart Phase Splitting

**Date:** 2026-07-23
**Status:** active

## Problem Framing

The collab extension's phase-split system is too fine-grained and creates unnecessary friction:

1. **Mechanical mapping**: Every `## Phase N` heading in tasks.md becomes a separate PR phase, regardless of size. A 23-task feature gets 7 phases with 2-3 tasks each, producing PR overhead without review benefit.

2. **Single-phase still interrupts**: When the user selects "Single phase (no split)", the phase-manager hook still fires at phase boundaries during implementation, stopping execution and asking about PR creation. The user has to manually continue after each pause.

3. **No size awareness**: There is no threshold heuristic. Phase splitting is proposed for every feature regardless of whether the feature is large enough to benefit from multiple PRs.

## Approaches Considered

### A: Smart Thresholds with Merge Logic

Add a file-count threshold gate and merge small phases:
- Estimate file count from plan.md (hybrid: parse file refs, fall back to ~1.5 files/task heuristic)
- Only propose splitting when estimated files exceed a configurable threshold (default: 20)
- When splitting, merge adjacent small phases until each phase is substantial (~15-20 files)
- Single-phase mode: skip phase-manager during implementation, fire once at end

- Pros: Preserves logical groupings from tasks.md, adapts to feature size, configurable
- Cons: File estimation is approximate, merging logic adds complexity

### B: Remove Phase Splitting Entirely

Simplify collab to always use a single phase. Remove the phase-split and phase-manager skills.

- Pros: Maximum simplicity, no configuration needed
- Cons: Loses value for genuinely large features (50+ files) where phased PRs help reviewers

### C: Manual-Only Phases

Never auto-propose phases. Only split when the user explicitly requests it via a command flag.

- Pros: No unwanted interruptions, user stays in control
- Cons: Users won't remember to split when they should, loses the "smart assistant" benefit

## Decision

**Approach A: Smart Thresholds with Merge Logic.**

Phase splitting has genuine value for large features, but needs to be size-aware and non-intrusive for small/medium features. The key changes:

1. **Threshold gate**: Estimate file count (hybrid: plan.md parsing with task-count fallback). Only propose multi-phase split when files exceed configurable threshold (`phases.file_threshold`, default: 20 in collab-config.yml). Below threshold, default to single phase silently.

2. **Merge small phases**: Start with tasks.md groupings but auto-merge adjacent phases that would touch fewer than ~10 files. Preserve logical structure while ensuring each phase is substantial enough for a meaningful PR.

3. **Single-phase runs uninterrupted**: When single phase is selected (or threshold not met), skip phase-manager hook during implementation. Fire phase-manager once at the end for the final review gate and PR creation. No mid-implementation interruptions.

## Key Requirements

- Configurable file threshold in collab-config.yml (`phases.file_threshold: 20`)
- Hybrid file estimation: parse plan.md file references, fall back to task-count heuristic if fewer than 5 files found
- Adjacent phase merging when phase would touch < ~10 files
- Phase-manager hook completely skipped during single-phase implementation
- Phase-manager fires once after implementation completes (for review gate + PR offer)
- Preserve interactive "Adjust groupings" option when phases are proposed

## Open Questions

- What is the right minimum files-per-phase threshold for merging? ~10 feels right but needs validation in practice.
- Should the file estimation also consider test files, or only production code?
- How to handle the case where plan.md lists files but some are shared across phases (counted once or per phase)?
