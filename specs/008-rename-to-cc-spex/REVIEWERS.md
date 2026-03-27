# Review Summary: Rename Plugin to cc-spex

**Spec:** specs/008-rename-to-cc-spex/spec.md | **Plan:** specs/008-rename-to-cc-spex/plan.md
**Generated:** 2026-03-27

---

## Executive Summary

The SDD plugin for Claude Code currently uses the name `cc-sdd` and the command prefix `sdd:`. A separate, unrelated project (`gotalab/cc-sdd`, 2,980 stars) has taken the same name for its own spec-driven development tooling, creating confusion in the developer tooling space.

This feature renames the plugin to `cc-spex` with a full command prefix change from `sdd:` to `spex:`. The rename touches approximately 70 files across the plugin directory, hook scripts, documentation, and project configuration. The methodology name "SDD" (Spec-Driven Development) remains unchanged in prose throughout; only tooling identifiers change.

The rename includes three notable aspects beyond the mechanical find-replace. First, the plugin root directory itself renames from `sdd/` to `spex/`, which affects every path reference in settings, hooks, and build configuration. Second, the Python hook scripts emit XML context tags (like `<sdd-context>`) that consumer projects parse, requiring coordinated updates. Third, a backwards-compatible migration path ensures existing projects with `sdd-traits.json` configuration files upgrade smoothly when running `/spex:init`, with the old config file detected and copied to the new name automatically.

The implementation is organized into five user stories by priority: core internal rename (P1), backwards-compatible migration (P2), documentation updates (P3), GitHub repo rename (P4), and consumer project updates (P5, separate effort). The P1 story alone produces a working plugin under the new name. The consumer project updates are explicitly scoped as a follow-up activity in a separate repository.

## Review Recipe (30 minutes)

### Step 1: Understand the problem (5 min)
- Read the Executive Summary above
- Skim `spec.md` User Story 1 for the core rename scope
- Ask yourself: Is "spex" a good name? Does it avoid future collisions?

### Step 2: Check critical references (10 min)
- Review each item in the **Critical References** table below
- Pay special attention to the hook script changes (they define the plugin's runtime behavior)
- Check the sentinel marker decision (kept as `<!-- SDD-TRAIT:name -->`)

### Step 3: Evaluate technical decisions (8 min)
- Review the backwards-compatible migration approach
- Check the sentinel marker preservation decision
- Evaluate whether the execution order (internal first, GitHub last) makes sense

### Step 4: Validate coverage and risks (5 min)
- Check the edge cases in spec.md: Are the migration scenarios complete?
- Verify FR-018/FR-019 (historical files and methodology prose are preserved)
- Scan the Risk Areas table for anything missing

### Step 5: Complete the checklist (2 min)
- Work through the **Reviewer Checklist** below
- Mark items as checked, flag concerns as PR comments

## PR Contents

| Artifact | Description |
|----------|-------------|
| `spec.md` | Defines the rename scope: 21 functional requirements across 5 user stories |
| `plan.md` | Implementation approach: 5 phases mapped to user stories, file-by-file scope |
| `tasks.md` | 87 tasks across 8 phases, heavily parallelizable |
| `research.md` | Pattern inventory: 28 distinct pattern types, 60+ locations |
| `data-model.md` | Rename mapping table (old identifiers to new) |
| `REVIEWERS.md` | This file |

## Technical Decisions

### Sentinel Marker Format Preserved
- **Chosen approach:** Keep `<!-- SDD-TRAIT:name -->` sentinel markers unchanged
- **Alternatives considered:**
  - Change to `<!-- SPEX-TRAIT:name -->`: Rejected because it would break existing consumer projects that already have sentinels applied in their overlay files
  - Recognize both old and new formats, emit new format going forward: Rejected for added complexity with little benefit
- **Trade-off:** The renamed `spex-traits.sh` script emits `SDD-TRAIT` sentinels, which is intentionally inconsistent. Backwards compatibility wins over naming purity.
- **Reviewer question:** Is this inconsistency acceptable, or should we plan a future migration?

### Copy-on-Init Migration Strategy
- **Chosen approach:** When `/spex:init` detects `sdd-traits.json` without a `spex-traits.json`, it copies the old file to the new name and prints a migration message. The old file is left in place.
- **Alternatives considered:**
  - Auto-delete old file: Rejected because it could break concurrent sessions using the old plugin version
  - Symlink: Rejected as fragile across platforms
  - Rename in-place: Rejected because it breaks old plugin if still installed
- **Trade-off:** Slightly messy (two files exist temporarily) but zero risk of data loss
- **Reviewer question:** Should there be guidance on when users can safely delete `sdd-traits.json`?

### Execution Order (Internal First, GitHub Last)
- **Chosen approach:** Rename all internal references first, test locally, then rename the GitHub repo and parent directory as final steps
- **Alternatives considered:**
  - Rename GitHub first: Rejected because testing would be harder if the remote changes before local is ready
- **Trade-off:** Standard, low-risk approach. No concerns.

## Critical References

| Reference | Why it needs attention |
|-----------|----------------------|
| `spec.md` FR-007/FR-008: Hook script changes | Hooks define runtime behavior, incorrect prefix matching breaks all commands |
| `spec.md` FR-011/FR-012: Migration logic | Core backwards-compatibility guarantee, must handle all three scenarios (old only, both, new only) |
| `spec.md` FR-019: SDD prose preservation | Must distinguish tooling prefix (`sdd:`) from methodology name ("SDD") in every file |
| `plan.md` Phase 3 Step 1.6: context-hook.py | Most complex single file change (6+ pattern types, XML tags, marker files, path references) |
| `tasks.md` T045: spex-traits.sh | Densest file (400+ occurrences), highest risk of missed references |
| `spec.md` Assumptions: Sentinel markers | Decision to keep `SDD-TRAIT` sentinels while renaming everything else needs explicit reviewer buy-in |

## Reviewer Checklist

### Verify
- [ ] The name "spex" has no naming conflicts (spec says no GitHub repos exist)
- [ ] All 21 functional requirements map to implementing tasks
- [ ] Migration logic covers all three scenarios (FR-011, FR-012)
- [ ] Historical files are explicitly excluded (FR-018)
- [ ] "SDD" methodology prose preservation is clear and consistent (FR-019)

### Question
- [ ] Is the sentinel marker inconsistency (`spex-traits.sh` emitting `SDD-TRAIT`) acceptable long-term?
- [ ] Should the migration include a deprecation timeline for `sdd-traits.json`?
- [ ] Are there consumer projects beyond cc-deck that need updating?

### Watch out for
- [ ] context-hook.py has 6+ pattern types; a missed one breaks command discovery
- [ ] spex-traits.sh has 400+ references; bulk replacement could miss context-specific patterns
- [ ] Parent directory rename (FR-021) may break other Claude Code sessions running in the same directory

## Scope Boundaries
- **In scope:** Plugin internal rename, migration logic, repo-root documentation, GitHub repo rename, parent directory rename
- **Out of scope:** Consumer project updates (cc-deck), automated test creation, `specify` CLI changes
- **Why these boundaries:** The plugin rename must be self-contained and testable before propagating to dependents. Consumer projects are separate repos with their own change cycles.

## Risk Areas

| Risk | Impact | Mitigation |
|------|--------|------------|
| Missed `sdd:` reference causes runtime error | High | Automated grep verification (T082, T083), manual smoke testing (T084-T087) |
| context-hook.py pattern incomplete | High | Detailed research identified all 6 pattern types; task T040 is not parallelizable to ensure careful review |
| Consumer projects break on plugin update | Medium | Migration logic in init script; old sentinel recognition; consumer updates as separate effort |
| Parent directory rename disrupts sessions | Medium | Coordinate with active sessions; do last in execution order |
| Git history harder to follow after `git mv` | Low | Single atomic commit for directory rename; clear commit messages |

---
*Share this with reviewers. Full context in linked spec and plan.*
