# Review Summary: Worktrees Trait

**Spec:** specs/007-worktrees-trait/spec.md | **Plan:** specs/007-worktrees-trait/plan.md
**Generated:** 2026-03-20

---

## Executive Summary

When using the SDD plugin, running `speckit.specify` creates a new git branch and switches to it. This disrupts every other Claude Code session pointing at the same repository, because they all share the same working tree and suddenly find themselves on a different branch. For developers who brainstorm and specify on `main` and then want to work on features in isolation (or work on multiple features simultaneously), this is a significant workflow problem.

The worktrees trait solves this by automatically creating a git worktree after specification completes. Git worktrees allow multiple branches to be checked out simultaneously in separate directories, each with its own working tree. After `speckit.specify` finishes, the trait creates a worktree for the feature branch in a sibling directory (e.g., `../007-my-feature`), restores the original repository to `main`, and writes a "context handoff" file into the worktree. This handoff file bridges the gap between the brainstorm/specify session and the new Claude session the developer will start in the worktree directory. It contains a brief summary of decisions made during brainstorming, a pointer to the spec file, and a suggested next step.

The feature also includes a listing command (`sdd:worktree list`) to show all active worktrees and a cleanup command (`sdd:worktree cleanup`) that detects worktrees whose branches have been merged and offers to remove them.

The implementation follows the established SDD trait pattern: a small overlay file appends post-specify instructions to the `speckit.specify` command, delegating to a new `sdd:worktree` skill. A new `sdd:worktree` command provides the listing and cleanup capabilities. The trait is independent and composable with existing traits (superpowers, teams).

A key design decision was to use a "context handoff" pattern rather than Claude Code's built-in `EnterWorktree` tool. `EnterWorktree` was ruled out because it creates its own branch names (incompatible with spec-kit's `NNN-feature-name` requirement), places worktrees in a fixed location, and session resume is directory-scoped. The handoff approach accepts that the user starts a fresh Claude session in the worktree, with the handoff file providing continuity.

## Review Recipe (30 minutes)

### Step 1: Understand the problem (5 min)
- Read the Executive Summary above
- Skim `spec.md` User Story 1 (the core value proposition)
- Ask yourself: Is worktree isolation the right approach for this problem?

### Step 2: Check critical references (10 min)
- Review each item in the **Critical References** table below
- The handoff file design and the overlay delegation pattern carry the most risk
- For each: read the referenced section, check the reasoning, flag concerns

### Step 3: Evaluate technical decisions (8 min)
- Review the **Technical Decisions** section below
- The EnterWorktree rejection and config schema decisions are the most important
- Pay attention to whether the handoff file provides sufficient context continuity

### Step 4: Validate coverage and risks (5 min)
- Check the edge cases in spec.md (5 cases) for completeness
- Review **Risk Areas**: Is the "fresh session" trade-off acceptable?
- Check **Scope Boundaries**: Should anything else be in/out of scope?

### Step 5: Complete the checklist (2 min)
- Work through the **Reviewer Checklist** below
- Mark items as checked, flag concerns as PR comments

## PR Contents

| Artifact | Description |
|----------|-------------|
| `spec.md` | Defines worktree creation, listing, and cleanup requirements (10 FRs, 3 user stories) |
| `plan.md` | Implementation plan using standard SDD trait pattern (overlay + skill + command) |
| `tasks.md` | 21 tasks across 6 phases, organized by user story |
| `REVIEWERS.md` | This file |
| `checklists/requirements.md` | Spec quality checklist (all items passing) |

## Technical Decisions

### Context Handoff vs. Session Resume
- **Chosen approach:** Write a handoff file to `<worktree>/.claude/handoff.md` and have the user start a fresh Claude session
- **Alternatives considered:**
  - `EnterWorktree` (built-in tool): Rejected because it creates its own branch names (spec-kit requires `NNN-feature-name`), fixed worktree location (`.claude/worktrees/`), and no worktree placement control
  - `claude -r <session-id>` from worktree: Rejected because session resume is directory-scoped (sessions stored under `~/.claude/projects/<encoded-path>/`), so resuming from a different directory fails
  - Session file symlinks: Rejected as fragile, depending on internal Claude Code storage format
- **Trade-off:** We lose full conversation context continuity but gain reliable directory isolation and spec-kit compatibility
- **Reviewer question:** Is the 5-10 line handoff summary sufficient for context continuity, or should the handoff include more structured data?

### Config Schema Extension
- **Chosen approach:** Keep `"worktrees": true` as boolean in the `traits` object, add separate `"worktrees_config"` top-level key
- **Alternatives considered:**
  - Change `"worktrees"` to an object `{"enabled": true, "base_path": ".."}`: Rejected because it breaks the existing pattern where all trait values are boolean
- **Trade-off:** Slightly more complex JSON structure but preserves backward compatibility
- **Reviewer question:** Is the separate `worktrees_config` key clean enough, or should we plan for a more general trait config pattern?

### Worktree Placement
- **Chosen approach:** Sibling directory at `<base_path>/<branch-name>` (default `..`)
- **Alternatives considered:**
  - Inside `.claude/worktrees/` (EnterWorktree default): Rejected because less discoverable and doesn't match existing cc-deck pattern
  - Configurable via environment variable: Deferred; config file is sufficient for now
- **Trade-off:** Sibling directories are more visible and IDE-friendly but create directories outside the repo

## Critical References

| Reference | Why it needs attention |
|-----------|----------------------|
| `spec.md` FR-002: Branch restore with uncommitted changes | Defines error handling for the most likely failure mode; reviewers should verify the abort-and-warn behavior is the right choice |
| `spec.md` FR-003: Handoff file content | The handoff is the only bridge between sessions; reviewers should evaluate whether 5-10 lines is sufficient |
| `plan.md` Component 1: Config schema | The `worktrees_config` top-level key is a new pattern; reviewers should assess if this is the right precedent |
| `plan.md` Component 2: Overlay | Must be < 30 lines per constitution; reviewers should verify the overlay is minimal and delegates correctly |
| `spec.md` Edge Cases: Already in worktree | Detection logic (`.git` file vs directory) is critical for preventing worktree nesting |

## Reviewer Checklist

### Verify
- [ ] The overlay file design stays under 30 lines and delegates to the skill (constitution Principle II)
- [ ] The trait has no dependencies on other traits (constitution Principle III)
- [ ] The handoff file location (`.claude/handoff.md`) is gitignored in worktrees
- [ ] The config schema extension (`worktrees_config`) is backward-compatible with existing `sdd-traits.json` consumers
- [ ] All 5 edge cases from spec.md have corresponding tasks in tasks.md

### Question
- [ ] Is 5-10 lines enough for the handoff file, or should it capture more brainstorm context?
- [ ] Should the trait support restoring to the original branch (not just `main`) if the user was on a different branch?
- [ ] Is `worktrees_config` the right pattern, or should trait-specific config be nested under the trait key?

### Watch out for
- [ ] The skill file (`SKILL.md`) grows across 3 user stories and could become large; may need splitting later
- [ ] `git worktree add` behavior differences across git versions (minimum git version not specified)
- [ ] Sibling directory placement may conflict with other worktree-based workflows the user has

## Scope Boundaries
- **In scope:** Worktree creation after specify, context handoff file, listing, cleanup, trait configuration
- **Out of scope:** Session resume across directories (Claude Code limitation), IDE integration, automatic cleanup triggers, worktree creation for non-specify workflows
- **Why these boundaries:** The feature solves the immediate disruption problem with minimal complexity. Session resume is blocked by Claude Code architecture. Automatic triggers add complexity without clear value.

## Risk Areas

| Risk | Impact | Mitigation |
|------|--------|------------|
| Handoff file provides insufficient context | Medium | Handoff includes spec pointer and next-step suggestion; full spec is available in worktree via git |
| Config schema precedent is awkward | Low | Can be refactored later without breaking existing traits |
| Worktree path conflicts with user's existing directory layout | Low | Error detection (FR-008) prevents overwriting; base_path is configurable |
| Git version compatibility for worktree operations | Low | Git worktree support has been stable since git 2.5 (2015); unlikely to be an issue |

---
*Share this with reviewers. Full context in linked spec and plan.*
