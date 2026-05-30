# Brainstorm: PR Review Comment Triage

**Date:** 2026-05-30
**Status:** active

## Problem Framing

After a PR is created (via `/speckit-spex-finish` or collab skills), automated review bots (CodeRabbit, GitHub Copilot) and human reviewers leave comments. Currently there is no structured way to:

1. Assess the validity of bot suggestions against the spec and actual code
2. Apply valid fixes and reject invalid ones with reasoning
3. Reply to each comment with a justification
4. Handle human reviewer comments with appropriate care (not auto-posting replies)
5. Repeat the process as new comments arrive

This creates manual overhead and risks ignoring valid bot feedback or blindly applying incorrect suggestions.

## Approaches Considered

### A: Single-pass with tier separation (Chosen)

One invocation does a full pass:
1. Fetch all PR comments via `gh api`
2. Partition into bot vs. human by GitHub author type
3. Process all bot comments autonomously (assess, fix, batch commit, reply)
4. Enter interactive mode for human comments (one by one, user approval)
5. Update state file
6. Report summary (N handled, M remaining)

When called via `/loop`, the next invocation picks up new/re-opened comments. Loop exits when 0 open bot comments remain.

- Pros: Simple mental model, one pass per invocation, natural `/loop` fit
- Cons: Human tier needs user interaction (but this is intentional)

### B: Separate bot and human modes

Two distinct modes via argument: `--bots` for autonomous looping, `--review` for interactive human pass.

- Pros: Clean separation, `/loop` only runs autonomous part
- Cons: Two invocations needed, user might forget the human pass

### C: Priority queue with interruptible processing

Single invocation processes comments in priority order (human first, then bots), with state-tracked position for resume.

- Pros: Human comments get attention first, single entry point
- Cons: More complex state management, human comments blocking bot processing feels backwards

## Decision

**Approach A: Single-pass with tier separation.** Simplest model, `/loop` naturally handles recurring bot comments, human comments are handled interactively when the user runs the skill directly.

## Key Requirements

### Skill identity
- Name: `speckit-spex-collab-triage`
- Location: spex-collab extension (alongside revise, reviewers, phase-manager)
- On-demand invocation, loopable via `/loop`

### PR detection
- Auto-detect open PR for current branch via `gh pr view`
- Override with `--pr <number>` argument

### Comment partitioning
- Detect bot vs. human by GitHub author type (bot flag via API)
- Bot tier: fully autonomous
- Human tier: interactive, user approves each reply before posting

### Bot tier (autonomous)
- Assess each open bot comment against spec (when available) and code
- For valid suggestions: apply the fix
- For invalid suggestions: prepare a rejection
- Batch all fixes into a single commit + push at the end
- Reply to each comment:
  - Accepted: brief note of what was fixed
  - Rejected: 1-2 sentence justification with spec reference when applicable
- Auto-resolve threads for single-pass bots (e.g., Copilot)
- Leave resolution to self-resolving bots (e.g., CodeRabbit)

### Human tier (interactive)
- Present each open human comment to the user
- Show: the comment, the skill's assessment, and a proposed reply
- User can approve, edit, or skip each reply
- Only post approved/edited replies
- Iterate through all open human comments one by one

### Open detection
- Primary: reply-based (check if we already replied to a comment)
- Cache: state file at `.specify/.pr-triage-state.json` mapping comment IDs to status
- Re-evaluate: if new replies appear after our last response
- Respect GitHub thread resolution status (resolved = handled)

### Bot profiles
- Hardcoded profiles for known bots:
  - CodeRabbit: self-resolves, don't auto-resolve
  - Copilot: single-pass, auto-resolve after handling
- Unknown bots: default to not auto-resolving
- Override via `collab-config.yml` for custom bot behavior

### Loop mode
- `/loop` re-runs the skill periodically
- Bot tier runs autonomously each pass
- Human comments reported in summary without blocking
- Exit condition: 0 open bot comments remaining

### Spec awareness
- Use spec as reference when `specs/<branch>/spec.md` exists
- Fall back to code-only analysis when no spec is found
- Still fully functional for non-spex PRs

## Out of Scope
- Auto-creating labels or updating PR status based on triage results
- Integration with deep-review extension (different lifecycle: pre-PR vs. post-PR)
- Handling PR description-level comments (only review comments/threads)

## Open Questions
- Should the reply format include a signature/tag (e.g., "Triaged by spex") so replies are easily identifiable for the open-detection logic?
- Should the skill offer to re-request review from bots after pushing fixes (some bots support this)?
- What happens when a bot comment references code that was already changed by another fix in the same batch?
