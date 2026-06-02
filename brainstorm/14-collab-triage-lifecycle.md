# Brainstorm: Collab Triage Lifecycle

**Date:** 2026-06-02
**Status:** active

## Problem Framing

Real-world usage of the spex collab workflow on a large PR (42 files, 300 review comments, 41 commits) revealed several pain points:

1. **PRs grow too large.** Spec + implementation on the same PR produces massive review surfaces. GitHub's UI degrades above ~100 review comments, making review ineffective.
2. **No structured triage phase.** After a PR is created, bot reviews (CodeRabbit, Copilot) arrive but there's no workflow step guiding the user to triage them. The `/speckit-spex-collab-triage` command exists but isn't surfaced at the right moment.
3. **No split decision point.** The workflow never asks "should we continue on this PR or split?" There's no gate between spec review and implementation that considers review volume.
4. **Deep review timing.** The deep review runs pre-push but the triage command only handles post-PR comments. These are separate concerns but the workflow doesn't make the handoff clear.

Source: [PR #85 feedback](https://github.com/opendatahub-io/agent-eval-harness/pull/85#issuecomment-4599086037)

## Approaches Considered

### A: Triage states integrated into flow state (Chosen)

Add `triage-spec` and `triage-impl` as recognized phases in the flow state (only when spex-collab is enabled). The collab extension hooks into the existing lifecycle with a gate check after spec triage to decide whether to continue on the same PR or split.

- Pros: Reuses existing flow state and phase-manager infrastructure. Status line shows current triage phase. Gate check is a natural extension of phase-manager.
- Cons: Ties triage lifecycle to flow state, adding complexity to the state machine.

### B: Triage as standalone checkpoints

Keep triage completely decoupled from flow state. Suggestion messages are printed by the commands that create PRs. Gate check is a new standalone command the user must remember to run.

- Pros: No flow state changes. Triage stays fully optional and self-contained.
- Cons: Gate check requires user initiative. No status line visibility. Suggestion messages scattered across multiple commands.

### C: Hybrid with collab-specific state

Add a separate `collab.triage_phase` to the collab namespace in `.spex-state`. Flow state stays unchanged but the collab namespace grows.

- Pros: Clean separation from flow state. Collab state is already established.
- Cons: Two state tracking mechanisms in the same file. Status line would need to read both.

## Decision

**Approach A: Triage states integrated into flow state.** The flow state already tracks workflow progression, and triage-spec/triage-impl are genuine workflow phases. The status line and phase-manager already read flow state, so integration is natural.

## Key Requirements

### New flow states

- `triage-spec`: entered after spec PR is created (only when spex-collab is enabled)
- `triage-impl`: entered after implementation is pushed to PR (only when spex-collab is enabled)
- Both states are skipped entirely when spex-collab is not enabled

### Status line badge

- New `T` badge for triage (same badge for both spec and impl triage)
- Spinner while triage is active, checkmark when complete
- Consistent with existing badge pattern (S, C, P, I, R, V)

### Suggest-with-delay pattern

After PR creation (spec or impl), the workflow does NOT auto-start triage. Instead it:
1. Tells the user that bot reviewers need 1-2 minutes to post comments
2. Suggests the ready-to-paste command: `/loop {interval} /speckit-spex-collab-triage`
3. The loop interval comes from `collab-config.yml` (`triage.loop_interval`, default "5m")

### Gate check after triage-spec

After triage-spec completes, phase-manager reads the triage state file (`.specify/.pr-triage-state.json`) and counts total review comments. Compares against `triage.split_threshold` from `collab-config.yml` (default 100).

- **Below threshold**: continue on the same PR. Update PR title to "[Spec + Impl]" and update labels accordingly.
- **Above threshold**: recommend merging the spec PR as-is, then creating separate implementation PR(s). Present this as a recommendation with user choice (not forced).

### Config additions to collab-config.yml

```yaml
triage:
  split_threshold: 100    # comment count above which PR split is recommended
  loop_interval: "5m"     # default interval for /loop triage suggestion
```

### Workflow lifecycle (collab enabled)

1. Specify → spec PR created → flow enters `triage-spec` → suggest with delay
2. User runs `/loop {interval} /speckit-spex-collab-triage` until done
3. Gate check in phase-manager: same PR (update title/labels) or merge spec PR + new impl PR(s)
4. Plan → implement → deep review suggested with delay (if deep-review extension enabled) → push to PR → flow enters `triage-impl` → suggest with delay
5. User runs triage loop until done

### Implementation phase-split unchanged

The existing `before_implement` phase-split hook stays as-is, based on task structure and implementation phases. This is orthogonal to the post-triage PR split decision.

### Triage command unchanged

The `/speckit-spex-collab-triage` command itself doesn't change. It already handles bot/human comments, state tracking, and loop mode. The new work is about when and how it's invoked in the workflow.

## Open Questions

- Should the gate check count only bot comments, or all comments (bot + human)?
- When splitting after triage-spec, should the spec PR be merged automatically or should the user confirm?
- Should triage-impl also have a gate check (e.g., recommend splitting a large impl into multiple PRs), or is that overkill since phase-split already handles impl phases?
- How should the deep review suggestion (pre-push) interact with the triage-impl suggestion (post-push)? Sequential suggestions or a combined message?
