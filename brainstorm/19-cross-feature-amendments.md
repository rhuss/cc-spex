# Brainstorm: Cross-Feature Spec Amendments

**Date:** 2026-06-11
**Status:** active

## Problem Framing

Specifications in cc-spex are per-feature and historical. When feature 024 changes behavior originally described in spec 018, nothing updates spec 018 automatically. It silently becomes stale. The `spex-evolve` command detects code-vs-spec drift reactively, but there is no proactive mechanism to detect spec-vs-spec impact during the specify/review workflow.

Brainstorm 02 (spec-evolution) identified three drift scenarios and proposed solutions, but the cross-feature amendment system (scenario 2: "a new spec supersedes parts of an earlier spec") was never implemented.

This brainstorm was triggered by evaluating OpenSpec's delta-spec model (from the heise/iX article on SDD tools, June 2026). After analysis, the delta.md concept was found to be a weak fit for cc-spex's per-feature spec architecture. OpenSpec's deltas solve a problem inherent to living system specs (one spec per domain, continuously maintained). In cc-spex, specs are per-feature and historical, so the real gap is cross-feature staleness, not change-level diffing.

## Approaches Considered

### A: Delta as Diff View (auto-generated delta.md)

Generate a `delta.md` file by diffing previous and current spec.md versions after revisions. For cross-feature changes, auto-detect entity overlaps and generate structured ADDED/MODIFIED/REMOVED sections.

- Pros: Zero ceremony for revisions, inspired by OpenSpec's proven model
- Cons: For revisions, spec.md is already updated in place and git diff shows changes. The delta.md adds marginal formatting value over raw diffs. For cross-feature, the delta is temporary (resolved on finish), so the intermediate artifact has limited review value.
- Verdict: **Rejected.** The revision case doesn't need a delta (REVIEWERS.md revision history already exists). The cross-feature case doesn't need a separate file (amendments can be generated and applied directly).

### B: Delta as Authored Artifact

Explicitly author delta.md files when proposing changes to existing specs. Closer to OpenSpec's model where deltas are the primary brownfield artifact.

- Pros: Clean separation of "proposed change" vs. "current state"
- Cons: Changes the existing revise workflow, more ceremony, risk of delta/spec divergence
- Verdict: **Rejected.** Adds ceremony without proportional value in cc-spex's per-feature model.

### C: Cross-Feature Amendments via Existing Extensions (chosen)

Implement brainstorm 02's amendment system by enhancing existing extensions. No new extension, no new commands, no delta.md file. Each piece lands where it logically belongs.

- Pros: Zero UX weight (no new extension to enable), each capability enhances an existing workflow, works for solo and team developers
- Cons: Changes spread across three extensions (spex-gates, core spex, spex-evolve), requires coordination between them
- Verdict: **Chosen.** Lightest integration, addresses the real gap, follows extension composability principles.

## Decision

Implement cross-feature spec amendments by enhancing three existing extensions:

### 1. spex-gates/review-spec: Supersession Detection

When reviewing a new spec (the `after_specify` hook), scan older specs in `specs/` for entities, APIs, types, or interfaces that the new spec references or changes. If overlaps are found, add a "Supersession Warning" section to the review output listing the impacted specs and what changed. The user confirms which amendments should be applied.

Format (from brainstorm 02):
```
### Supersession Warning
This spec changes the VectorStoreBackend interface defined in spec 018.
Recommended: Add an amendment note to spec 018 linking to this spec.
```

Confirmed amendments are stored in the feature directory (e.g., `amendments.json` or a section in spec.md itself).

### 2. Core spex/finish: Amendment Application

On `/speckit-spex-finish`, before merge/PR, apply confirmed amendments to the referenced older specs. Each amendment becomes a standardized block at the top of the older spec:

```markdown
> **Amended by**: [Spec NNN - Title](../NNN-name/spec.md) (YYYY-MM-DD)
> Brief description of what changed.
```

The amended specs are included in the commit/PR so reviewers see the full impact.

### 3. spex-evolve: Spec-vs-Spec Drift

Extend `spex-evolve` to also detect cross-spec references. Today it checks code vs. spec. Add a mode that checks whether any spec references entities that have been superseded by newer specs (i.e., specs that have amendment blocks pointing elsewhere). This is the reactive complement to review-spec's proactive detection.

## Key Requirements

- Supersession detection must be non-blocking (warnings, not gates). The user decides which amendments to apply.
- Amendment blocks follow the standardized format from brainstorm 02.
- Amendments are applied atomically on finish (all or nothing per feature).
- The system must handle the case where the referenced older spec has already been amended by another feature (stacking amendments).
- No new extension, no new user-facing commands. Detection hooks into review-spec, application hooks into finish, manual check hooks into evolve.

## Open Questions

- How to store confirmed amendments between the review-spec step and the finish step? Options: `amendments.json` in the feature directory, a section in spec.md metadata, or `.specify/.spex-state`.
- How reliable is entity/API overlap detection via text scanning? May need heuristics (type names, endpoint patterns, interface names) rather than full semantic analysis.
- Should amendment blocks in older specs be machine-parseable (for evolve to detect stacking) or free-form markdown?
- What happens when an older spec is amended by two features concurrently (parallel branches)? Merge conflict on the amendment block?

## References

- [Brainstorm 02: Spec Evolution and Drift Management](02-spec-evolution.md) (the original proposal)
- [heise/iX: Five Tools for Spec-driven Development](https://www.heise.de/hintergrund/Fuenf-Tools-fuer-Spec-driven-Development-im-Ueberblick-11314972.html) (trigger for this analysis)
- [OpenSpec Delta Specs](https://github.com/Fission-AI/OpenSpec) (inspiration, ultimately rejected for cc-spex's architecture)
