# Brainstorm: Mid-Implementation Review Checkpoints

**Date:** 2026-06-11
**Status:** active

## Problem Framing

The backpressure article found review subagents were the single most effective mechanism for keeping autonomous coding agents on track. Spex currently runs review at two points: never during implementation, and a full 5-agent deep review after all tasks are complete. This leaves a gap: if task 5 introduces a correctness issue, tasks 6-20 may build on it, and the deep review at the end faces a larger, more tangled problem to diagnose.

The initial idea was a per-task review agent, but analysis revealed three problems:
1. **Same-context blindness**: A review running inside the implementing subagent's session shares the implementer's blind spots. The deep review works because it uses isolated subagents with fresh context.
2. **Cost**: A feature with 50 tasks would need 50 review passes, easily adding 250k+ tokens.
3. **Runtime**: Roughly doubles implementation time.

The question became: is there a way to get the benefit (catch issues mid-implementation) without the cost (review every task)?

## Approaches Considered

### A: Per-Task Review Agent (Rejected)

A single review agent after every task completion.

- Pros: Catches issues at the earliest possible point.
- Cons: Same-context problem (diminished value). Prohibitive cost on large features (50+ tasks). Doubles runtime. Over-engineering for what the test checkpoint already partially covers.

### B: Mid-Implementation Review Checkpoints at 1/3 and 2/3 (Chosen)

Run two correctness-focused review checkpoints during implementation: one after approximately 1/3 of tasks complete, and another after approximately 2/3. Each checkpoint spawns a fresh-context subagent (true isolation, not in the implementing agent's session). Track statistics for comparison with the final deep review.

- Pros: Two reviews instead of 50. Fresh context (true isolation). Catches drift before it compounds across the remaining tasks. Cost is bounded (2 reviews regardless of task count). The 1/3 and 2/3 split gives two correction opportunities before the final deep review.
- Cons: Adds some implementation time (two pauses for review). The checkpoint positions are approximate (rounding to nearest task boundary). May duplicate some findings that the final deep review would also catch (statistics will reveal this).

### C: Single Mid-Point Review at 50% (Rejected in favor of B)

One review checkpoint at the halfway point.

- Pros: Simpler than B. One review, minimal cost.
- Cons: Only one correction opportunity. If the first third has issues, they're not caught until halfway through, meaning a third of tasks may build on problems.

## Decision

**Approach B: Two mid-implementation review checkpoints at 1/3 and 2/3 of tasks.**

Key design decisions:
- **Fresh-context subagent**: Each checkpoint spawns an isolated Agent (not inline in the implementing session), so the reviewer has no implementation blind spots.
- **Correctness only**: The checkpoint reviews correctness (does the code match the spec requirements for the completed tasks?). Architecture, security, production readiness, and test quality wait for the full deep review.
- **Gated on deep-review extension**: Only runs when the `spex-deep-review` extension is enabled. If deep review is disabled, no mid-implementation checkpoints either.
- **On by default, opt-out via config**: `implement.review_checkpoints: true` in `spex-config.yml`. Set to `false` to disable.
- **Statistics tracking**: Each checkpoint records findings (count, severity, fixed/unfixed). The final deep review also records its findings. At pipeline completion, a comparison report shows what each layer caught, enabling data-driven decisions about whether the checkpoints are worth the cost.

## Key Requirements

- Two review checkpoints during implementation: after ~33% and ~66% of tasks
- Each checkpoint runs as a fresh-context subagent via Agent tool (not inline)
- Correctness-focused review only: does code match spec requirements for completed tasks?
- Only active when `spex-deep-review` extension is enabled
- On by default, opt-out via `implement.review_checkpoints: false` in `.specify/extensions/spex/spex-config.yml`
- Statistics recorded for each checkpoint: findings count by severity, fixes applied, fix success rate
- Statistics also recorded for the final deep review (may already exist, needs verification)
- End-of-pipeline statistics report comparing all review layers: checkpoint 1, checkpoint 2, final deep review
- Report should answer: "How many findings did the mid-point reviews catch that the deep review would have also caught? How many were unique to the mid-point reviews?"
- Changes go in `speckit.spex.ship.md` (implement subagent prompt), no new extension or command
- Checkpoint positions are approximate: round to the nearest task boundary (e.g., for 10 tasks: checkpoint at task 3 and task 7)

## Open Questions

- Should the statistics report be written to a file (e.g., `REVIEW-STATS.md`) or only output to console?
- How should checkpoint findings interact with the test checkpoint? Should the correctness review run before or after the test suite?
- If a checkpoint finds issues and fixes them, should the task count restart (since new code was added) or continue from where it was?
- Should the checkpoint review only the diff since the last checkpoint, or the entire implementation so far?
- After collecting statistics across multiple ship runs, how should the data be aggregated? Per-project trends would be valuable but require persistent storage beyond the session.
