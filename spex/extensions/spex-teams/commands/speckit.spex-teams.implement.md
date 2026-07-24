---
description: "Parallel implementation via agent teams for independent tasks"
---

# Teams Implement

Use Teams only for proven parallelism. A `[P]` marker is a hint, never proof
that two assignments can safely write concurrently.

## Prerequisites

- `{harness:teams-enabled}` and the harness subagent capability are available.
- `tasks.md`, `spec.md`, and the validated active feature worktree exist.
- The spex-gates extension is enabled for returned-work review.
- The effective security profile and writable repository boundary are known.

If any prerequisite or durable worktree identity cannot be validated, use the
sequential fallback. Do not approximate isolation in the current checkout.

## T058: Independence and Conflict Analysis

Build work groups before dispatch:

1. Parse every incomplete task into its ID, phase, explicit dependencies,
   described files, shared contracts, and produced or consumed interfaces.
2. Add dependency edges from the Dependencies section, task wording, phase
   ordering, and producer-before-consumer relationships. A dependency blocks
   parallel dispatch even when both tasks carry `[P]`.
3. Derive an `allowed_files` scope for each proposed group. A file overlap is a
   conflict. Directory scopes overlap when either contains the other; generated
   files and their generators also conflict.
4. Build a contract graph. Changes to a contract, schema, migration, generated
   API, shared interface, or its consumer conflict unless the producer is
   accepted first and the consumer is rebased onto that accepted result.
5. Treat shared mutable fixtures, lockfiles, registries, build manifests, and
   task bookkeeping as file conflicts unless exactly one group owns them.
6. Compute connected components across dependency, file, and contract edges.
   Tasks connected by any edge belong in the same sequential work group.

Record the analysis as a table before spawning:

| Group | Task IDs | Dependencies | `allowed_files` | Contracts | Blocked by |
|-------|----------|--------------|-----------------|-----------|------------|

Parallel dispatch requires **2+ independent** work groups with no edge between
them. Fewer than 2 independent groups MUST fall back to sequential execution.
Do not manufacture a second group merely to enable Teams.

## T059: Isolated Writer Worktrees

For every concurrent write group, create a distinct isolated writer worktree
from the same validated feature HEAD. Resolve its physical absolute path and
put that exact path in the assignment `workdir`; set `kind: write` and
`isolated_worktree: true`. Never ask a writer to rely on inherited CWD.

Use collision-free branch and directory names derived from the workflow and
assignment IDs. Before dispatch, verify with `git worktree list --porcelain`
that:

- every writer path is registered, exists, and resolves inside the granted
  repository/worktree boundary;
- no two assignments have the same worktree, branch, or `allowed_files` scope;
- each writer starts at the recorded feature HEAD; and
- the main/feature checkout is not itself used as a concurrent writer.

The assignment contains only its task IDs, relevant spec context, explicit
absolute workdir, allowed files, inherited effective security profile, and
required review evidence. Writers must commit their result in their own branch
and return the commit OID, changed files, tests/checks, and residual risks.

## Dispatch and Lifecycle Handoff

Pass the analyzed groups and validated writer paths to
`speckit.spex-teams.orchestrate`. That command owns waiting, review, and merge
coordination, but this dispatch establishes these mandatory gates:

1. A prerequisite remains blocked until its producer result passes spec and
   scope review and completes **accepted reconciliation** into the feature
   branch.
2. **Dependent release** occurs only after all dependency OIDs are accepted;
   create the dependent worktree from the reconciled feature HEAD, never from
   the pre-review base.
3. On writer failure, **preserve partial work**, the branch, worktree, commit
   OIDs, diff, and diagnostics before choosing recovery. Never merge an
   unreviewed partial result.
4. A **replacement assignment** receives a new ID, branch, and isolated
   worktree from the last accepted feature HEAD. The failed worktree remains
   intact until its evidence is recorded and the replacement is reviewed.
5. **Cleanup worktree** registrations only after accepted reconciliation or
   after failed-work evidence has a durable branch/commit reference. Prune
   registrations and verify that no successful or replaced writer path remains.

Merge or cherry-pick only reviewed commit OIDs. If the feature branch moved,
conflicts appeared, an agent wrote outside `allowed_files`, or contract
assumptions changed, stop reconciliation and rerun the analysis. Never
auto-resolve a semantic conflict.

## Safe Sequential Fallback

Execute tasks sequentially in the validated active feature worktree when:

- fewer than 2 independent groups remain;
- dependencies, file ownership, or contract relationships are ambiguous;
- isolated worktrees or explicit writable paths cannot be created;
- the harness lacks safe concurrent subagents; or
- the effective security profile cannot be inherited without escalation.

Sequential fallback performs the same tasks, reviews, and evidence collection;
it changes scheduling only. In ship mode it continues without asking whether
to proceed.

## Ship Pipeline Integration

Ship routes here only after Teams is explicitly enabled. Re-resolve durable
WorkflowState after every subagent return and before review, reconciliation,
dependent release, or cleanup. A host CWD reset never selects a worktree.
