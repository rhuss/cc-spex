# Flow Status Line

## Problem

The spex status line currently only works during `spex:ship` (when `.spex-ship-phase` exists). Outside of ship, there's no visibility into where you are in the spex lifecycle. When working manually through specify, plan, implement, review steps, you lose track of progress and what the next logical step should be.

## Vision

A persistent status line that shows your position in the spex workflow, which quality gates you've passed, and what the next recommended step is. Works for both autonomous (ship) and manual flows, with a clear visual distinction between modes.

## Design Decisions

### Two Modes, One Status Line

The status line operates in **either** ship mode or flow mode, never both simultaneously. This keeps the display concise and makes the operating mode immediately obvious.

- **Ship mode** (`🧬 spex:ship`): Existing behavior with linear stage progression, progress bar, ask level indicator. Driven by the ship pipeline.
- **Flow mode** (`🧬 spex`): New artifact-driven progress tracker with review checklist. Driven by speckit commands and review skills.

### Artifact-Based Progress Detection

Instead of managing a state file for flow tracking, detect progress from artifacts in the spec directory. Artifacts are the source of truth since they can't go stale.

Linear milestones (detected by file existence):
- `spec.md` exists = specify done
- `plan.md` exists = plan done
- `tasks.md` exists = tasks done
- Code changes on branch vs spec-only changes = implement in progress/done

Quality gates (detected by review artifact files):
- `REVIEW-SPEC.md` exists = spec review done
- `REVIEW-PLAN.md` exists = plan review done
- `REVIEW-CODE.md` exists = code review done

This requires splitting the current `REVIEWERS.md` into three separate files, one per review phase. Each file maps directly to its spex command (`/spex:review-spec` produces `REVIEW-SPEC.md`, etc.).

### State File Generalization

Generalize `.spex-ship-phase` to serve both modes:

```json
{
  "mode": "ship" | "flow",
  "started_at": "2026-04-07T10:00:00Z",
  "brainstorm_file": "brainstorm/08-flow-status-line.md",
  "feature_branch": "016-flow-status-line",

  // ship-only fields
  "ask": "smart",
  "stage": "implement",
  "stage_index": 6,
  "total_stages": 9,
  "retries": 0,
  "status": "running"
}
```

In flow mode, the state file tracks mode and metadata. Actual progress comes from artifact detection, not from the state file. The state file's presence signals "a flow is active"; artifacts signal "how far along."

In ship mode, the state file continues to drive stage progression (pipeline discipline requires explicit advancement). Artifact checks serve as validation gates (the `spex-ship-state.sh advance` command already does this).

### Flow Entry and Exit

- **Entry**: Flow mode activates when `/speckit-specify` runs (first artifact created). The specify command (or its overlay) creates the state file with `mode: flow`.
- **Exit**: Flow mode clears when `/spex:stamp` passes successfully. The stamp skill removes the state file after successful verification.
- **No explicit start/stop commands**: The flow starts and ends naturally with the workflow.

### REVIEWERS.md Split

Split the current monolithic `REVIEWERS.md` into three files:

| File | Produced by | Content |
|------|------------|---------|
| `REVIEW-SPEC.md` | `/spex:review-spec` | Spec quality assessment, requirement coverage |
| `REVIEW-PLAN.md` | `/spex:review-plan` | Plan coverage analysis, task quality, coverage matrix |
| `REVIEW-CODE.md` | `/spex:review-code` | Code review guide, deep review report, compliance score |

Benefits:
- Clean binary artifact signals for the status line (file exists = review done)
- Each file maps to exactly one spex command
- Uppercase naming signals "project artifact" (like README.md)
- Files group visually in directory listings
- Enables independent review ordering (review-code before review-plan is valid)

The ship pipeline must be updated to produce these three files instead of accumulating into one REVIEWERS.md.

### Reviews as Unordered Checklist

Unlike ship's linear pipeline, the manual flow treats reviews as an unordered checklist. You can run review-code before review-plan, or skip review-spec entirely. The status line shows which reviews have been completed without enforcing order.

## Status Line Display

### Flow Mode

```
🧬 spex  📝spec ✅  🗺️plan ✅  📋tasks ✅  🔨impl ◻️   reviews: ☑S ☑P ◻C
```

Compact breakdown:
- `🧬 spex`: Mode indicator (no `:ship` suffix = flow mode)
- Linear milestones with check/empty markers
- Review checklist: S=spec, P=plan, C=code

When implementation is done and all reviews pass:
```
🧬 spex  📝✅ 🗺️✅ 📋✅ 🔨✅  reviews: ☑S ☑P ☑C  → stamp
```

The `→ stamp` hint appears when all milestones and reviews are complete.

### Ship Mode (Existing, Unchanged)

```
🧬 spex:ship 🔨 implement ▓▓▓▓▓▓░░░ 7/9 🧠
```

### After Stamp (Celebration)

When stamp passes, display a brief celebration before clearing the state:

**ASCII art banner** (randomized from a small pool):

```
╔══════════════════════════════════════╗
║  ✨ SHIPPED! Feature complete. ✨   ║
╚══════════════════════════════════════╝
```

```
┌──────────────────────────────────────┐
│  🎯 All gates passed. Ready to PR.  │
└──────────────────────────────────────┘
```

```
  _____ _   _ ___ ____  ____  _____ ____  _ 
 / ____| | | |_ _|  _ \|  _ \| ____|  _ \| |
| (___ | |_| || || |_) | |_) |  _| | | | | |
 \___ \|  _  || ||  __/|  __/| |___| |_| |_|
 |____/|_| |_|___|_|   |_|   |_____|____/(_)
```

**Stats summary** (always shown):

```
Feature: 016-flow-status-line
Duration: 2h 34m (specify to stamp)
Reviews: 3/3 passed (spec, plan, code)
Commits: 7 on branch
```

**Randomized sign-off** (one per completion, rotated):

```
"Ship it! 🚢"
"Clean build, clean merge."
"Another one bites the dust. 🎸"
"Spec-driven, review-approved, stamp-verified."
"That's a wrap. 🎬"
```

## Implementation Considerations

### Spec Directory Detection

The status line script needs to find the current feature's spec directory. Options:
- Derive from branch name: `specs/$(git branch --show-current)/`
- Read from state file: `feature_dir` field
- Use the existing `check-prerequisites.sh` script

The state file approach is most reliable since branch naming patterns vary.

### Ship Pipeline Changes

Ship needs updates to produce the split review files:
- Stage 2 (review-spec): Write `REVIEW-SPEC.md` instead of `REVIEWERS.md`
- Stage 5 (review-plan): Write `REVIEW-PLAN.md` instead of building onto `REVIEWERS.md`
- Stage 7 (review-code): Write `REVIEW-CODE.md` instead of appending to `REVIEWERS.md`
- Stage advancement artifact checks must be updated accordingly

### Status Line Script Changes

The `spex-ship-statusline.sh` becomes `spex-statusline.sh` (or stays the same name, just gains flow mode). It reads the state file for mode, then:
- Ship mode: Existing logic (stage from state file, progress bar)
- Flow mode: Detect artifacts in spec directory, build checklist display

### Implementation Detection

Detecting "implement done" is trickier than artifact files. Options:
- Any non-spec commit on the branch = implementation started
- State file marker set by `/speckit-implement` completion
- Diff between spec-only files and other files in the branch

A marker in the state file (set by speckit-implement when it finishes) is probably cleanest.

## Open Questions

- Should `/spex:evolve` (spec refinement) reset any review artifacts? If you evolve the spec after review-spec, `REVIEW-SPEC.md` is now stale.
- Should the flow status line show a "stale review" warning if spec.md is newer than REVIEW-SPEC.md?
- How does the celebration interact with ship's PR creation step? Celebrate before or after PR?

## Out of Scope

- Brainstorm phase tracking (brainstorm is freeform, no status line)
- Multi-feature tracking (status line shows one active feature)
- Integration with external tools (CodeRabbit, Copilot status)
