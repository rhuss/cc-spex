# Brainstorm: Post-Implementation Workflow Redesign (Submit + Finish)

**Date:** 2026-06-28
**Status:** active

## Problem Framing

The current post-implementation UX is unintuitive. After the ship pipeline completes, users must run `/speckit-spex-finish` multiple times with different outcomes depending on hidden state: first invocation creates a PR, second invocation (after reviews resolve) merges and cleans up. The command name doesn't change but the intent does. There's no squash merge option, so commit history is messy. The smoke test placement is awkward -- it interrupts the ship pipeline but doesn't gate the actual landing of code.

The goal is a streamlined two-command model where each command has clear, predictable intent.

## Approaches Considered

### A: One Smart Command (status quo evolution)

Keep `/speckit-spex-finish` as the single command. It detects context (no PR yet → create one; PR with unresolved reviews → triage; PR approved → merge + cleanup) and always does "the right next thing."

- Pros: Fewer commands to learn; no naming decisions
- Cons: Same command means different things depending on state; unpredictable; user can't express intent clearly; "what will this do?" uncertainty

### B: Two Commands -- Submit + Finish

Split into `/speckit-spex-submit` (create PR, start review cycle) and `/speckit-spex-finish` (land the code after reviews). "Finish" means the true end.

- Pros: Clear intent per command; predictable behavior; "finish" means done; smoke test gates landing not PR creation; natural place for squash
- Cons: Two commands to learn; need to handle the direct-merge case (no PR)

### C: Three Commands -- Submit + Triage + Finish

Maximum separation: submit creates the PR, triage handles the review cycle, finish lands the code.

- Pros: Maximum clarity per command
- Cons: Too many commands; triage already exists as `/speckit-spex-collab-triage`; over-engineered

## Decision

**Approach B: Two commands -- Submit + Finish.**

"Submit" = "I'm done implementing, here's my work for review."
"Finish" = "Land the code, I'm done."

Direct merge (no PR) skips submit and goes straight to finish.

## Key Requirements

### `/speckit-spex-submit`

1. Run automated verification gates (tests, spec compliance, drift check)
2. Commit any outstanding changes
3. Create PR via `gh pr create` with spec-linked body and REVIEWERS.md reference
4. Support `--watch` flag to enter triage polling loop after PR creation
5. Handle fork workflows (upstream remote detection)
6. Handle existing PR detection (push to existing PR instead of creating new)

### `/speckit-spex-finish`

1. **Smoke test gate**: Check `.spex-state` for prior smoke test result.
   - If passed and no new commits since recorded hash: skip
   - If passed but new commits exist since: warn user ("smoke test passed at commit X but Y commits added since"), let user choose to re-run or skip
   - If never run: run the smoke test interactively
2. **Squash**: Collapse all feature branch commits into one clean commit
   - AI-generated commit message using conventional commit format for the title (e.g., `feat(extensions): add hot-reload support`)
   - Body summarizes the spec and key changes
   - User approves/edits the message before squashing
   - Force-push the squashed branch
3. **Merge**: 
   - If PR exists and user has merge permissions: merge via `gh pr merge --squash` (or the squashed branch is already clean, so `--merge` works too since it's one commit)
   - If PR exists but user doesn't control merge: inform user the branch is squashed and ready for upstream maintainer to merge
   - If no PR (direct merge): merge branch to main locally
4. **Worktree cleanup** (prompted, never automatic):
   - Show what will happen: remove worktree, delete feature branch, sync main
   - Ask for confirmation before proceeding
   - If uncommitted changes exist: warn and offer rescue commit
5. **State cleanup**: Remove `.specify/.spex-state`, dismiss status line

### Ship Pipeline Integration

Ship runs Stages 0-7 autonomously (specify → review-code). Then presents a choice:

- **"Submit PR"** → invokes submit logic, creates PR, pipeline ends
- **"Merge directly"** → invokes finish logic (smoke test → squash → merge → cleanup)
- **"Stop here"** → pipeline ends, user runs commands manually later

The smoke test is no longer a ship pipeline stage. It moves into `finish` as a pre-landing gate.

### Smoke Test State Tracking

The smoke test result records the commit hash at which it passed. This allows `finish` to detect staleness when triage fixes add new commits after the smoke test ran.

### Squash Commit Message Format

```
<type>(<scope>): <description>

<body - summarizes spec and key changes>

Assisted-By: 🤖 Claude Code
```

Type follows conventional commits: feat, fix, refactor, docs, chore, etc.
Scope is optional, derived from the primary area of change.

## Complete Lifecycle

```
ship (stages 0-7: specify → implement → review-code)
  │
  ├─ "Submit PR" ──→ submit ──→ [triage cycle] ──→ finish ──→ done
  │                                                   │
  │                                          smoke test (if needed)
  │                                          squash + approve message
  │                                          merge PR (if permissions)
  │                                          cleanup worktree (prompted)
  │
  ├─ "Merge directly" ──→ finish ──→ done
  │                          │
  │                 smoke test (if needed)
  │                 squash + approve message
  │                 merge to main
  │                 cleanup worktree (prompted)
  │
  └─ "Stop here" ──→ user runs submit or finish later
```

## Open Questions

- Should `submit` also run `before_submit` hooks (extensibility point for future extensions)?
- Should `finish` support a `--no-smoke-test` flag for cases where the user explicitly wants to skip?
- How should the existing `/speckit-spex-collab-triage` integrate -- does `submit --watch` invoke it directly, or should the watch loop live in a separate concern?
- Should the squash step be extractable as a standalone command (e.g., for users who want to squash mid-triage without landing)?
