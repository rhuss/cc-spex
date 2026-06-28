# Implementation Plan: Post-Implementation Workflow Redesign (Submit + Finish)

## Overview

Split the current monolithic `/speckit-spex-finish` command into two focused commands (`submit` and `finish`) and update the ship pipeline's Stage 8 from a smoke-test invocation to a choice prompt.

## Architecture

### Current State

```
finish.md (793 lines) = verification + PR creation + merge + watch mode + worktree cleanup
ship.md Stage 8 = smoke-test invocation
```

### Target State

```
submit.md (new, ~400 lines) = verification + PR creation + watch mode
finish.md (redesigned, ~500 lines) = smoke test gate + squash + merge + worktree cleanup  
ship.md Stage 8 = choice prompt (submit/finish/stop)
```

## Critical Files

### New Files

| File | Purpose |
|------|---------|
| `spex/extensions/spex/commands/speckit.spex.submit.md` | New submit command skill |

### Modified Files

| File | Lines | Change Scope | What Changes |
|------|-------|-------------|--------------|
| `spex/extensions/spex/commands/speckit.spex.finish.md` | 793 | Major | Remove PR creation (Options B1/B2/D), remove watch mode (Phase 7), remove `--create-pr`/`--watch` flags, add smoke test gate, add squash step with conventional commit message |
| `spex/extensions/spex/commands/speckit.spex.ship.md` | 976 | Moderate | Redesign Stage 8 from smoke-test to choice prompt, update pipeline completion text |
| `.specify/extensions.yml` | 283 | Minor | Remove `before_finish` smoke-test hook, add `before_submit`/`after_submit` hook points |
| `spex/scripts/spex-ship-state.sh` | 438 | Minor | Add `--commit-hash` parameter to `do_smoke_test_record`, store as `smoke_test_commit_hash` field |
| `spex/docs/help.md` | 270 | Minor | Update workflow diagram, commands table, closing-out-a-feature section |
| `README.md` | - | Minor | Update commands reference table and workflow description |

### Unchanged Files (stable interfaces)

- `spex-finish-context.sh` (61 lines) — used by both submit and finish
- `speckit.spex.smoke-test.md` (413 lines) — invoked by finish, interface unchanged
- `speckit.spex-collab.triage.md` (545 lines) — invoked by submit watch mode, interface unchanged
- `speckit.spex-worktrees.manage.md` (527 lines) — standalone, unaffected
- `spex-flow-state.sh` (169 lines) — after_finish hook, unchanged

## Implementation Strategy

### Phase 1: Create the Submit Command (New File)

Create `spex/extensions/spex/commands/speckit.spex.submit.md` by extracting and reorganizing content from the current finish skill:

**Structure:**

1. **Argument parsing**: `--watch` flag (extracted from finish), no positional args
2. **Ship pipeline guard**: Read `.spex-state`, detect autonomous mode (same pattern as finish)
3. **Pre-execution hooks**: Read `before_submit` hooks from extensions.yml
4. **Prerequisites check**: Verify `gh` CLI is installed, verify not on default branch
5. **Phase 1 — Verification**: Invoke `/speckit-spex-gates-verify` (same as current finish Phase 1)
6. **Phase 2 — Commit outstanding changes**: `git add -A` + commit (same as current finish Phase 2)
7. **Phase 3 — Context detection**: Run `spex-finish-context.sh` (same as current finish Phase 3)
8. **Phase 4 — PR action**: Detect existing PR vs new PR
   - Existing PR: push to it (extracted from finish Option B1)
   - New PR: create via `gh pr create` (extracted from finish Option B2)
   - Handle fork workflows via upstream remote detection (extracted from finish Option B2)
   - Handle spex-detach PR push (extracted from finish Option D)
   - Handle collab-config labels and REVIEWERS.md linking
   - Handle brainstorm file exclusion from PR branch
9. **Post-execution hooks**: Read `after_submit` hooks
10. **Phase 5 — Watch mode** (if `--watch`): Entire Phase 7 from current finish, including CI polling, auto-fix loop (max 2 attempts), triage integration, timeout handling

**Source material**: Finish Options B1 (~18 lines), B2 (~78 lines), D (~47 lines), Phase 7 watch mode (~218 lines), plus verification and commit phases (~30 lines each).

### Phase 2: Redesign the Finish Command (Major Modification)

Modify `spex/extensions/spex/commands/speckit.spex.finish.md`:

**Remove:**
- `--create-pr` and `--watch` argument parsing
- Option B1 (push to existing PR)
- Option B2 (create new PR)
- Option D (detach PR push)
- Phase 7 (watch mode) — entire section (~218 lines)
- Watch mode guard in Phase 6

**Add:**
- `--no-smoke-test` argument parsing
- **Smoke test gate** (new phase, after verification, before squash):
  1. Check `.spex-state` for prior smoke test result via `spex-ship-state.sh`
  2. If passed and `git rev-parse HEAD` matches recorded commit hash: skip with message
  3. If passed but HEAD differs from recorded hash: warn user with commit count since smoke test, offer re-run or skip choice
  4. If `--no-smoke-test` flag: skip unconditionally
  5. If never run: invoke `/speckit-spex-smoke-test` interactively
- **Squash step** (new phase, after smoke test, before merge):
  1. Detect default branch and compute merge base: `git merge-base $DEFAULT_BRANCH HEAD`
  2. Count commits to squash: `git rev-list --count $MERGE_BASE..HEAD`
  3. If only 1 commit: skip squash, proceed to merge
  4. Read spec.md for feature context
  5. Generate conventional commit message:
     - Title: `<type>(<scope>): <description>` (AI-generated from spec + diff summary)
     - Body: summary of key changes from spec
     - Tagline: `Assisted-By: 🤖 Claude Code`
  6. Present message to user for approval/editing
  7. Execute squash: `git reset --soft $MERGE_BASE && git commit -m "$MESSAGE"`
  8. Force-push: `git push --force-with-lease`

**Modify:**
- Phase 4 (Select Action): Remove PR creation options, keep Merge and Keep
- Add new option for merge when PR exists: `gh pr merge --squash` (or inform user branch is ready for upstream maintainer)
- Worktree cleanup: prompt before cleanup (already the behavior from memory constraint)

### Phase 3: Update Ship Pipeline Stage 8

Modify `spex/extensions/spex/commands/speckit.spex.ship.md`:

**Replace Stage 8 content** with a choice prompt:

After Stage 7 (review-code) completes and advances, the pipeline presents:

```
## Pipeline Complete (Stages 0-7)

All automated stages have passed. How would you like to proceed?

A) Submit PR — Create a pull request for team review
B) Merge directly — Run smoke test, squash, and merge to main
C) Stop here — Run /speckit-spex-submit or /speckit-spex-finish later
```

- If A: invoke submit logic inline (verify, create PR)
- If B: invoke finish logic inline (smoke test, squash, merge, cleanup)
- If C: end pipeline, print instructions

**Also update:**
- Pipeline completion text to reference both commands
- Integration section to list submit
- Stage table description for Stage 8

### Phase 4: Update Hook Configuration

Modify `.specify/extensions.yml`:

- Remove the `before_finish` smoke-test hook entry (smoke test is now built into finish)
- Add `before_submit` hook point (empty initially, extensibility for future extensions)
- Add `after_submit` hook point (empty initially)
- Keep `after_finish` flow-state cleanup hook unchanged

### Phase 5: Update Documentation

Modify `spex/docs/help.md`:

- Update workflow diagram to show submit as a separate step from finish
- Add `/speckit-spex-submit` entry to commands table with description and flags
- Update `/speckit-spex-finish` entry: new description, new flags (`--no-smoke-test`), remove old flags
- Rewrite "CLOSING OUT A FEATURE" section to describe the two-command flow
- Update backpressure configuration references

## Key Design Decisions

### Squash Implementation

Use `git reset --soft` + `git commit` instead of `git rebase -i` because:
- Non-interactive (no editor needed)
- Predictable behavior (no conflict resolution)
- Works in all git versions
- The merge-base approach cleanly identifies the divergence point

### Conventional Commit Message Generation

The AI reads:
- The spec's feature name and key requirements
- The git diff summary (`git diff --stat $MERGE_BASE..HEAD`)
- The list of changed files to determine scope

Type detection heuristic:
- If spec title contains "fix" or brainstorm was about a bug: `fix`
- If spec involves refactoring existing code: `refactor`
- If spec adds documentation: `docs`
- Default: `feat`

Scope is derived from the primary directory of change (e.g., `extensions`, `scripts`, `docs`).

### Watch Mode Ownership

Watch mode moves entirely to submit. Finish has no watch mode. The rationale:
- Watch mode monitors PR review state (CI, comments, triage)
- PR review happens after submit, before finish
- Watch mode belongs to the command that creates/manages the PR

### Smoke Test State Tracking

The existing `spex-ship-state.sh smoke-test-record` stores:
- `smoke_test_completed`: boolean
- `smoke_test_at`: ISO timestamp
- `smoke_test_scenarios`, `smoke_test_total`, `smoke_test_skipped`: counts

**This must be extended** to also accept `--commit-hash` and store `smoke_test_commit_hash` (the HEAD at time of recording). This enables staleness detection: finish compares the recorded hash against current HEAD to detect new commits since the smoke test passed.

The script modification is small: add `--commit-hash)` to the argument parser in `do_smoke_test_record` and include the field in the `jq` update expression.

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| Breaking existing finish workflows | Keep the merge and worktree cleanup paths intact; only move PR-related code out |
| Ship pipeline state file compatibility | Stage name stays as `smoke-test` in the STAGES array; only behavior changes |
| Force-push after squash fails on protected branches | Use `--force-with-lease` for safety; report clear error on failure |
| Smoke test state not persisted across sessions | Already stored in `.spex-state` which is gitignored but copied to worktrees |

## Testing Strategy

- Test submit with fresh branch (new PR creation)
- Test submit with existing PR (push to existing)
- Test submit with fork workflow (upstream remote)
- Test finish with no prior smoke test (triggers interactive smoke test)
- Test finish with stale smoke test (warns about new commits)
- Test finish squash with multiple commits
- Test finish direct merge (no PR)
- Test finish worktree cleanup prompt
- Test ship pipeline Stage 8 choice prompt
