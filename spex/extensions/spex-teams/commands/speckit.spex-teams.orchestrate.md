---
description: "Unified team orchestration: parallel task implementation with spec guardian review pattern via parallel agent teams"
---

# Teams Orchestration: Parallel Task Implementation

## Overview

This command orchestrates parallel task implementation using parallel agent teams. The lead session analyzes the task dependency graph, spawns teammates in isolated worktrees for independent task groups, reviews all changes against spec.md via the spec guardian pattern, and coordinates merges. The spec guardian review loop is always-on: every teammate's work is reviewed for spec compliance before merging.

## Prerequisites

### Parallel Agent Teams Prerequisite

{harness:agent-teams}
Verify that the parallel agent teams feature is available on the current harness.
If not available, fall back to sequential implementation for this session.
{/harness:agent-teams}

**If teams are available:** Proceed with team orchestration.

## Task Graph Analysis

Read the tasks.md file and analyze the dependency structure:

1. **Parse all tasks** with their IDs, descriptions, and phase membership
2. **Identify dependency relationships** from the Dependencies section and phase ordering
3. **Group tasks by independence**: tasks that can execute simultaneously (no shared dependencies, different files)
4. **Identify blocked tasks**: tasks that must wait for others to complete first

### Parallelism Assessment

Evaluate whether teams add value:

- **If 0-1 independent task groups exist** (everything is sequential): Skip team creation, execute tasks sequentially in the current session. Report: "Tasks are sequential, no parallelism benefit. Executing directly."
- **If 2+ independent task groups exist**: Proceed with team spawning.

## Bounded SubagentAssignment Generation

Before creating any teammate, generate one JSON `SubagentAssignment` record for
each independent work group. The record is the complete dispatch boundary: do
not supplement it with the whole conversation, the full specification, or
unrelated repository context.

Populate every record as follows:

- `schema_version`: exactly `"1.0.0"`.
- `assignment_id`: a unique, stable ID for this dispatch.
- `kind`: `"read"` for research or `"write"` for implementation.
- `workdir`: an explicit absolute path. Resolve and verify it before dispatch;
  never rely on the lead's current working directory.
- `objective`: one concrete outcome, bounded to the assigned work group.
- `spec_context`: only the minimum relevant spec sections and artifact paths
  needed to decide correctness. Never include unrelated context.
- `task_ids`: the exact task IDs assigned to this work group.
- `security_profile`: inherit the same effective parent security profile
  (`safe`, `autonomous`, or `yolo`). An assignment must not escalate to a
  broader or weaker security boundary.
- `dependencies`: assignment/task IDs whose accepted results are prerequisites;
  use an empty array only when the group is immediately runnable.
- `allowed_files`: the complete file scope, including any schema, contract, or
  shared-interface paths the assignment may change. Files not listed are
  read-only.
- `required_evidence`: concrete evidence the lead can review, including a
  changed-file inventory, relevant test/check results, and contract or spec
  compliance evidence.
- `isolated_worktree`: `true` for every concurrent writer/write assignment.
  Read assignments may use `false` and share a read-only view.

Use this shape (replace every placeholder with resolved values):

```json
{
  "schema_version": "1.0.0",
  "assignment_id": "assignment-T057-writer-1",
  "kind": "write",
  "workdir": "/absolute/repository/worktrees/feature-writer-1",
  "objective": "Implement the assigned bounded work group",
  "spec_context": ["specs/feature/spec.md#relevant-requirement"],
  "task_ids": ["T057"],
  "security_profile": "autonomous",
  "dependencies": [],
  "allowed_files": [
    "path/to/assigned-file.md",
    "specs/feature/contracts/relevant.schema.json"
  ],
  "required_evidence": [
    "Changed-file inventory is within allowed_files",
    "Relevant tests and contract checks pass"
  ],
  "isolated_worktree": true
}
```

### Validation Before Dispatch

Validate each generated object against
`specs/047-codex-plugin-support/contracts/subagent-assignment.schema.json`
before calling the harness dispatch mechanism. Then perform these semantic
checks, which are stricter than shape validation:

1. The absolute `workdir` exists and is the intended registered worktree/read
   view; every concurrent write assignment has a distinct workdir and
   `isolated_worktree=true`.
2. `security_profile` exactly equals the lead's persisted effective security
   profile. Refuse any missing, unknown, or escalated profile.
3. `spec_context`, `task_ids`, `allowed_files`, and `required_evidence` are
   nonempty and contain only context necessary for the objective.
4. Every dependency exists, is acyclic, and has been accepted before the
   assignment is released.
5. The assigned file and contract scope matches the independence analysis and
   does not overlap another concurrent writer.

Do not dispatch an invalid assignment. Report the validation reasons and use
the sequential fallback without weakening the assignment or security contract.

## Teammate Spawning

### Spawn Rules

- Spawn **one teammate per independent task group** (not one per task)
- **Maximum 5 teammates** (best practice for coordination overhead)
- If more than 5 independent groups, batch them: assign multiple groups to the same teammate sequentially
- **Never spawn more teammates than independent groups**
- Each writer gets its own git worktree for clean file isolation
- Pass exactly one validated `SubagentAssignment` JSON object to each teammate

### Spawn Prompt Template

Each teammate receives its validated assignment fields in this prompt; include
only the paths/sections listed in `spec_context` and no ambient conversation:

```
You are implementing tasks for the [feature-name] feature.
Assignment ID: [assignment_id]
Kind: [kind]
Absolute workdir: [workdir]
Effective security profile: [security_profile]
Dependencies: [dependencies]
Allowed files and contracts: [allowed_files]
Required evidence: [required_evidence]

You are working in the workdir declared by the assignment.
Your work will be reviewed against spec.md before merging.

## Your Assigned Tasks

[List the specific tasks assigned to this teammate with task IDs]

## Spec Context

[Only the bounded sections and paths listed in spec_context]

## Working Rules

1. Implement each task completely before moving to the next
2. Commit after each logical group with descriptive messages
3. When all your tasks are done, message the lead: "Tasks complete, ready for review"
4. If you encounter a blocker, message the lead with details
5. Do not modify files outside your assigned task scope
6. Use "Assisted-By: Claude Code" as the git commit tagline
```

### Spawning Process

Tell Claude to create an agent team:

```
Create an agent team for parallel implementation of [feature-name].

Spawn [N] teammates:
- Teammate 1: [task group description] - tasks [IDs]
- Teammate 2: [task group description] - tasks [IDs]
...

Each teammate should implement their assigned tasks independently in their worktree.
Wait for all teammates to complete before proceeding to review.
```

## Completion Waiting

After spawning teammates:

1. Record every dispatched `assignment_id`, workdir, branch, base commit, and
   dependency edge in the lead's coordination state.
2. **Wait for all assigned work** in the current runnable wave to return a
   result or an explicit failed/unavailable outcome. Do not treat the first
   successful writer as completion, and do not release a dependent while any
   prerequisite assignment is running, unreviewed, rejected, or unresolved.
3. **Do not implement tasks yourself** while teammates are working (coordinate
   only). Monitor stuck teammates and request a final result/evidence report
   before classifying an assignment as failed.
4. Require each result to identify its `assignment_id`, status, commit OID(s),
   changed-file inventory, evidence for every `required_evidence` item, checks,
   summary, and residual risks. Missing evidence is a rejected result, not an
   implicit success.

## Spec Guardian Review Loop

Review every returned result independently before changing the feature branch:

1. **Schema and identity review**: Revalidate the original assignment against
   `subagent-assignment.schema.json`. Match the result to its `assignment_id`,
   recorded workdir/branch/base, and commit OIDs. Reject ambiguous or missing
   identity.
2. **Scope review**: Diff the recorded base through every returned commit.
   Require the changed-file inventory to match the diff exactly and require all
   changed paths to be within `allowed_files`, including contract/schema paths.
   Reject unrelated changes, uncommitted mutations, and dependency changes not
   authorized by the assignment.
3. **Evidence review**: Evaluate every `required_evidence` entry against the
   returned checks and artifacts. Record an explicit accepted/rejected decision
   with reasons; a process exit code or teammate claim is not evidence by
   itself.
4. **Spec guardian review**: Run `speckit.spex-gates.review-code` against the
   bounded `spec_context`, objective, task IDs, and relevant full specification.
   Record the gate evidence and reject any material deviation.
5. **Acceptance**: Mark a result `accepted` only when schema/identity, scope,
   evidence, tests, and spec guardian review all pass. Otherwise mark it
   `rejected`, send the concrete findings to the same teammate for an in-scope
   correction, and repeat the entire review. After three failed reviews of the
   same task, preserve the evidence and report the decision boundary instead of
   continuing retries.

Acceptance is a review decision only. It does not satisfy dependencies until
accepted reconciliation has completed on the feature branch.

## Accepted Reconciliation and Dependent Release

After every prerequisite result in a runnable wave is accepted:

1. Re-read the feature branch HEAD and verify it is the expected reconciliation
   base. Fetch each accepted commit by exact OID from its isolated branch.
2. Reconcile accepted commits one at a time in deterministic assignment order
   using a non-interactive cherry-pick (or an equivalently auditable operation).
   Before each commit, verify that its patch remains within `allowed_files`.
3. After each reconciliation, rerun the assignment's focused checks plus all
   affected shared contract and downstream tests. If reconciliation conflicts
   or validation fails, abort only that in-progress integration, restore the
   feature branch to its pre-integration state with a recoverable operation,
   retain the accepted writer branch/commit/evidence, and classify it for
   correction. Never auto-resolve an ambiguous conflict.
4. Record the reconciled feature-branch OID and evidence. Only now may the lead
   mark the assignment reconciled and update its completed task IDs.
5. Evaluate the dependency graph again. **Dependent release** is permitted only
   when every declared prerequisite is both accepted and reconciled into the
   dependent's base. Create the dependent worktree from that reconciled OID and
   validate its assignment again before dispatch. Acceptance without
   reconciliation never releases a dependent.

The lead never implements code directly. The lead's sole job during this phase is review and coordination.

## Partial Failure, Replacement, and Sequential Degradation

On a crash, timeout, rejected result, or partially completed assignment:

1. **Preserve partial work** before replacement: record the failure status and
   diagnostics, branch name, workdir, base and HEAD OIDs, changed-file
   inventory, commits, uncommitted patch (if any), checks, and returned evidence.
   Commit or otherwise store a recoverable evidence snapshot on the failed
   assignment branch; never reconcile rejected partial changes into the feature
   branch.
2. Keep dependents blocked. Do not delete the failed branch or worktree while
   evidence collection or salvage is incomplete.
3. Generate a new bounded **replacement assignment** for only the remaining
   objective. Give it a new `assignment_id`, the same effective security
   profile, an explicit workdir, a reference to the failed assignment/evidence,
   and revalidated dependencies, allowed files, and required evidence. A
   replacement may inspect preserved evidence but must not silently inherit
   rejected mutations.
4. If a safe replacement cannot be dispatched, degrade to sequential execution
   as a successful orchestration mode. Apply the same assignment scope,
   security, evidence, spec review, acceptance, reconciliation, and dependency
   gates; sequential mode is not permission to bypass them.

## Safe Worktree Cleanup

Run cleanup only after all accepted results are reconciled, all failure evidence
is recoverable by branch/commit, and no dependent or review still needs the
worktree:

1. Verify the worktree is the exact recorded path and registered branch. Refuse
   cleanup for an unresolved path, dirty writer, unrecorded commit, or the main
   repository/feature checkout.
2. For successful writers, confirm every accepted commit is reachable from the
   feature branch. For failed/rejected writers, confirm partial evidence is
   reachable from the preserved assignment branch.
3. Use the repository's worktree command to **cleanup worktree** registrations
   one explicit path at a time, then prune stale registrations. Never use a
   recursive delete or a broad path/glob.
4. Delete a temporary assignment branch only when its commits are reconciled or
   preserved elsewhere and no audit evidence depends on it. Retaining a failed
   evidence branch is valid cleanup.
5. Report removed worktrees, retained evidence branches, reconciliation OIDs,
   and any cleanup refusal. Cleanup failure does not invalidate accepted work.

## Sequential Fallback

When teams cannot be used (feature flag not active, single task, linear dependencies):

Execute tasks sequentially in the current session following the standard implementation flow from tasks.md. This is the normal behavior when the teams trait is not active.

**Mixed independence**: When some tasks are independent and others are sequential (e.g., 1 of 3 tasks is independent, 2 are sequential), group the sequential tasks together as one teammate's workload and assign the independent task to a separate teammate. If only one independent group results, fall back to sequential execution.

## Multi-Agent Dispatch

The parallel dispatch mechanism varies by harness:

{harness:agent-teams-dispatch}
Use the agent's team mechanism to spawn teammates in isolated worktrees.
If the current harness does not support parallel dispatch, execute tasks sequentially.
{/harness:agent-teams-dispatch}

## Key Principles

- **Teams for parallelism, not complexity**: Only use teams when genuine parallel work exists
- **Lead never implements**: The lead's job is review and coordination
- **Spec is the standard**: All review decisions based on spec.md
- **Worktrees prevent conflicts**: Each teammate has clean file isolation
- **Graceful degradation**: Always fall back to sequential if teams can't help
- **Respect task dependencies**: Never assign dependent tasks to different teammates

## Failure Handling

- **Teammate crashes**: Preserve its partial work/evidence, then dispatch a
  validated replacement or use the same gated protocol sequentially.
- **Reconciliation conflicts**: Do NOT auto-resolve. Keep the source branch and
  evidence, restore the pre-integration feature state, and report the conflict.
- **Review deadlock (3+ attempts)**: Preserve the rejected results, message the
  teammate to stop work, report the situation, and pause orchestration.
