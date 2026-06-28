# Tasks: Post-Implementation Workflow Redesign (Submit + Finish)

## Task Dependency Graph

```
T0 (state script) ──┐
                     ├── T1 (submit command) ──┐
                     │                          ├── T3 (ship Stage 8) ── T5 (docs)
                     └── T2 (finish redesign) ─┘        │
                            │                            │
                            └── T4 (hooks config) ──────┘
```

## Tasks

- [x] **T0: Extend spex-ship-state.sh with commit hash tracking**
  Add `--commit-hash` parameter support to the `do_smoke_test_record` function in `spex/scripts/spex-ship-state.sh`.

  **Steps:**
  1. Read `spex/scripts/spex-ship-state.sh` and locate the `do_smoke_test_record` function
  2. Add `--commit-hash)` case to the argument parser (alongside `--completed`, `--scenarios`, `--total`, `--skipped`)
  3. Add `smoke_test_commit_hash` field to the `jq` update expression that writes to the state file
  4. Default value should be empty string if not provided

  **Acceptance:** `spex-ship-state.sh smoke-test-record --completed true --scenarios 3 --total 3 --skipped 0 --commit-hash abc123` stores `smoke_test_commit_hash: "abc123"` in `.spex-state`.

- [x] **T1: Create the submit command** [P]
  Create `spex/extensions/spex/commands/speckit.spex.submit.md` by extracting PR-related logic from the current finish skill.

  **Steps:**
  1. Read the current finish skill at `spex/extensions/spex/commands/speckit.spex.finish.md` to understand the sections being extracted
  2. Create the new submit command file with this structure:
     - Argument parsing: `--watch` flag
     - Ship pipeline guard: read `.spex-state`, detect autonomous mode
     - Prerequisites: verify `gh` CLI installed, verify not on default branch
     - Before_submit hooks: read from `.specify/extensions.yml`
     - Phase 1 — Verification: invoke `/speckit-spex-gates-verify`
     - Phase 2 — Commit outstanding changes: `git add -A` + commit
     - Phase 3 — Context detection: run `spex-finish-context.sh`
     - Phase 4 — PR action: detect existing PR vs new PR
       - Existing PR path: push to it (from finish Option B1)
       - New PR path: `gh pr create` with spec-linked body, REVIEWERS.md, collab-config labels, brainstorm exclusion (from finish Option B2)
       - Fork detection: upstream remote handling (from finish Option B2)
       - Detach PR push path (from finish Option D)
     - After_submit hooks
     - Phase 5 — Watch mode (if `--watch`): CI polling, auto-fix loop (max 2 attempts), triage integration via `/speckit-spex-collab-triage`, timeout handling (from finish Phase 7, ~218 lines)
  3. Ensure the command follows the same patterns as existing spex extension commands (header format, ship pipeline guard, hook reading boilerplate)

  **Source sections to extract from finish.md:**
  - Option B1 (push existing PR): ~18 lines
  - Option B2 (create new PR): ~78 lines
  - Option D (detach PR push): ~47 lines
  - Phase 7 (watch mode): ~218 lines
  - Verification + commit phases: reused pattern, ~30 lines each

  **Acceptance:** Submit command creates a PR when run on a feature branch. `--watch` enters triage loop.

- [x] **T2: Redesign the finish command** [P]
  Modify `spex/extensions/spex/commands/speckit.spex.finish.md` to remove PR creation logic and add smoke test gate + squash step.

  **Removals:**
  1. Remove `--create-pr` and `--watch` from argument parsing
  2. Remove Option B1 (push to existing PR) from Phase 5
  3. Remove Option B2 (create new PR) from Phase 5
  4. Remove Option D (detach PR push) from Phase 5
  5. Remove Phase 7 (watch mode) entirely (~218 lines)
  6. Remove watch mode guard from Phase 6

  **Additions:**
  1. Add `--no-smoke-test` to argument parsing
  2. Add smoke test gate (new phase after verification, before merge):
     - Read smoke test state from `.spex-state` via `spex-ship-state.sh`
     - If passed and HEAD matches recorded `commit_hash`: skip with message
     - If passed but HEAD differs: warn user with count of new commits, offer re-run or skip
     - If `--no-smoke-test`: skip unconditionally
     - If never run: invoke `/speckit-spex-smoke-test`
  3. Add squash step (new phase after smoke test, before merge):
     - Compute merge base: `git merge-base $DEFAULT_BRANCH HEAD`
     - Count commits: `git rev-list --count $MERGE_BASE..HEAD`
     - If 1 commit: skip squash
     - Generate conventional commit message (AI-generated from spec + diff):
       - Title: `<type>(<scope>): <description>`
       - Body: spec summary + key changes
       - Tagline: `Assisted-By: 🤖 Claude Code`
     - Present to user for approval/editing
     - Execute: `git reset --soft $MERGE_BASE && git commit -m "$MESSAGE"`
     - Force-push: `git push --force-with-lease`
  4. Add merge option for when PR exists: `gh pr merge` or inform user branch is ready for upstream maintainer

  **Modifications:**
  1. Phase 4 (Select Action): simplify to Merge / Keep options only (remove PR creation options)
  2. Ship pipeline guard: remove `AUTO_CREATE_PR` logic (moves to submit)

  **Acceptance:** Finish runs smoke test (if needed), squashes commits with conventional commit message, and merges or informs user. No PR creation capability.

- [x] **T3: Update ship pipeline Stage 8**
  Modify `spex/extensions/spex/commands/speckit.spex.ship.md` to replace Stage 8 (smoke-test) with an end-of-pipeline choice prompt.

  **Depends on:** T1, T2 (needs to reference both commands)

  **Steps:**
  1. Replace the Stage 8 section content (currently ~67 lines for smoke-test logic) with:
     - Pipeline completion announcement
     - Three-way choice prompt: "Submit PR" / "Merge directly" / "Stop here"
     - If "Submit PR": invoke submit logic (verify, create PR)
     - If "Merge directly": invoke finish logic (smoke test, squash, merge, cleanup)
     - If "Stop here": print instructions for running commands manually
  2. Update the stage table description for Stage 8
  3. Update the Pipeline Completion section text to reference both `/speckit-spex-submit` and `/speckit-spex-finish`
  4. Update the Integration section to list submit

  **Note:** The `STAGES` array in `spex-ship-state.sh` keeps `smoke-test` as the stage name (no script change needed). Only the ship skill's behavior at Stage 8 changes.

  **Acceptance:** Ship pipeline presents choice after Stage 7, each option works correctly.

- [x] **T4: Update hook configuration**
  Modify `.specify/extensions.yml` and related config.

  **Depends on:** T2 (finish no longer uses smoke-test hook)

  **Steps:**
  1. Remove the `before_finish` smoke-test hook entry from `.specify/extensions.yml`
  2. Add `before_submit` hook point (empty list initially)
  3. Add `after_submit` hook point (empty list initially)
  4. Keep `after_finish` flow-state cleanup hook unchanged
  5. Update the spex extension manifest to register the new `speckit.spex.submit` command

  **Acceptance:** Extensions.yml has correct hook points. Submit command is registered.

- [x] **T5: Update documentation**
  Update `spex/docs/help.md`, `README.md`, and related docs to reflect the new two-command workflow.

  **Depends on:** T1, T2, T3

  **Steps:**
  1. Update `spex/docs/help.md`:
     - Update the workflow diagram to show submit as a separate path from finish
     - Add `/speckit-spex-submit` to the spex commands table with description "Push and create PR for team review" and flags `--watch`
     - Update `/speckit-spex-finish` entry: description becomes "Smoke test + squash + merge/keep (land the code)", flags change to `--no-smoke-test`
     - Rewrite "CLOSING OUT A FEATURE" section to describe:
       - PR path: `/speckit-spex-submit` → triage → `/speckit-spex-finish`
       - Direct merge: `/speckit-spex-finish`
     - Update any backpressure/ship references to Stage 8
  2. Update `README.md`:
     - Update commands reference table with new submit command and updated finish description
     - Update workflow section/flowchart to show the two-command model

  **Acceptance:** Help docs and README accurately describe the new workflow. No stale references to old finish behavior.

## Parallel Execution

T0 runs first (small script change). Then T1 and T2 (marked `[P]`) can execute in parallel — they modify different files. T3 depends on T1 and T2, T4 depends on T2, and T5 depends on all others.
