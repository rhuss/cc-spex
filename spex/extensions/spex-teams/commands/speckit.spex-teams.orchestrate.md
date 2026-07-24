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

1. **Wait for all teammates to finish** their assigned tasks
2. **Do not implement tasks yourself** while teammates are working (coordinate only)
3. **Monitor for stuck teammates**: if a teammate stops responding or errors, note the issue
4. **Handle teammate failures**: if a teammate crashes mid-task, either:
   - Spawn a replacement teammate for the remaining tasks
   - Fall back to implementing the remaining tasks directly

## Spec Guardian Review Loop

When a teammate reports completion, the lead reviews their changes:

1. **Review changes**: Examine the teammate's commits and modified files
2. **Run spec compliance check** via `speckit.spex-gates.review-code` against spec.md
3. **If PASS**: Merge worktree changes, update tasks.md checkboxes to `[X]` for completed tasks
4. **If FAIL**: Send feedback to the teammate with specific spec violations. The teammate fixes the issues and re-submits for review.
5. **If 3+ failures on the same task**: Report to the user and pause. Do not continue retrying.

The lead never implements code directly. The lead's sole job during this phase is review and coordination.

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

- **Teammate crashes**: Spawn a replacement teammate for unfinished tasks, or implement directly if near the end of the work
- **Merge conflicts**: Do NOT auto-resolve. Report the conflict to the user and wait for guidance
- **Review deadlock (3+ attempts)**: Message the teammate to stop work, report the situation to the user, and pause orchestration
