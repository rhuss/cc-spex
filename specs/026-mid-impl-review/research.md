# Research: Mid-Implementation Review Checkpoints

## R1: Where do checkpoint instructions go?

**Decision**: Add checkpoint logic to the implement subagent prompt in `speckit.spex.ship.md` (Stage 6). The ship pipeline already calculates task count from tasks.md. Pre-compute checkpoint positions and pass them as explicit task numbers in the prompt.

**Rationale**: Same pattern as per-task test checkpoints (feature 024). The ship pipeline orchestrates; the subagent executes.

## R2: How does the subagent spawn a fresh-context review?

**Decision**: The implementing subagent uses the Agent tool to spawn a review subagent. The review subagent gets: the spec path, the list of completed tasks, and instructions to review correctness only. It returns findings as text.

**Rationale**: Agent tool provides true context isolation. The review subagent has no memory of the implementation decisions, giving it fresh eyes.

## R3: Where do deep review statistics come from?

**Decision**: The deep review command (`speckit.spex-deep-review.run.md`) already dispatches 5 agents and collects their findings. The statistics feature adds a summary table at the end that formats the already-collected data. No new data collection is needed; it's a reporting change.

**Rationale**: The findings are already in memory when the deep review finishes (it merges them for the fix loop). Formatting them as a table is trivial.

## R4: How to compute "unique findings" across layers?

**Decision**: Compare finding locations (file path + line range) across layers. A finding is "unique" to a layer if no other layer reported a finding in the same file at overlapping lines. This is an approximation but sufficient for the statistics purpose.

**Rationale**: Exact semantic dedup would require NLP comparison of finding descriptions. Location-based matching is deterministic, fast, and good enough to answer "did the checkpoint catch something new?"

## R5: Checkpoint state storage

**Decision**: Store checkpoint results as simple counts in the existing `.specify/.spex-state` file: `checkpoint_1_findings`, `checkpoint_1_fixed`, `checkpoint_2_findings`, `checkpoint_2_fixed`. The ship pipeline reads these after the final deep review to compute the layer comparison.

**Rationale**: Counts are sufficient for the layer comparison table. Individual finding details are in the console output and don't need persistence.
