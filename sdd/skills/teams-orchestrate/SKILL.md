---
name: teams-orchestrate
description: "Unified team orchestration: parallel task implementation with spec guardian review pattern via Claude Code Agent Teams"
---

# Teams Orchestration: Parallel Task Implementation

## Overview

This skill orchestrates parallel task implementation using Claude Code Agent Teams. The lead session analyzes the task dependency graph, spawns teammates in isolated worktrees for independent task groups, reviews all changes against spec.md via the spec guardian pattern, and coordinates merges. The spec guardian review loop is always-on: every teammate's work is reviewed for spec compliance before merging.

## Prerequisites

### CC Teams Feature Flag

Check if Agent Teams is enabled:

```bash
# Check settings.local.json for the feature flag
FLAG=$(jq -r '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS // ""' .claude/settings.local.json 2>/dev/null)
```

**If the flag is not set (`""` or missing):**

1. Set it in `.claude/settings.local.json`:
   ```bash
   jq '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1"' .claude/settings.local.json > /tmp/settings.json && mv /tmp/settings.json .claude/settings.local.json
   ```
2. Inform the user: "Agent Teams feature flag has been enabled. Please restart Claude Code for teams to activate."
3. **Fall back to sequential implementation** for this session (teams will work on next run).

**If the flag is set:** Proceed with team orchestration.

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

## Teammate Spawning

### Spawn Rules

- Spawn **one teammate per independent task group** (not one per task)
- **Maximum 5 teammates** (CC Teams best practice for coordination overhead)
- If more than 5 independent groups, batch them: assign multiple groups to the same teammate sequentially
- **Never spawn more teammates than independent groups**
- **isolation: "worktree"** - each teammate gets its own git worktree for clean file isolation

### Spawn Prompt Template

Each teammate receives this context in its spawn prompt:

```
You are implementing tasks for the [feature-name] feature.
You are working in an isolated git worktree.
Your work will be reviewed against spec.md before merging.

## Your Assigned Tasks

[List the specific tasks assigned to this teammate, including bd issue IDs alongside task IDs]

## Spec Context

[Contents of spec.md for this feature]

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
- Teammate 1: [task group description] - tasks [IDs] (bd issues [bd-IDs])
- Teammate 2: [task group description] - tasks [IDs] (bd issues [bd-IDs])
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
2. **Run spec compliance check** via `{Skill: sdd:review-code}` against spec.md
3. **If PASS**: Merge worktree changes, close beads issues with `bd close <id> -r "Reviewed and merged"`, run `bd backup`
4. **If FAIL**: Send feedback to the teammate with specific spec violations. The teammate fixes the issues and re-submits for review.
5. **If 3+ failures on the same task**: Report to the user and pause. Do not continue retrying.

The lead never implements code directly. The lead's sole job during this phase is review and coordination.

## Beads Integration

### Bootstrap

At the start of orchestration, check the beads state:

- Verify bd issue count matches expected tasks
- If issues are missing, run sync to populate them

### Persistence

- Run `bd backup` after each successful merge to preserve progress
- This ensures task state survives across sessions

### Final Sync

After all teammates have completed and all reviews have passed:

1. Verify all bd issues are closed
2. Reverse sync tasks.md to reflect final state
3. Run final `bd backup`

## Sequential Fallback

When teams cannot be used (feature flag not active, single task, linear dependencies):

Execute tasks sequentially in the current session following the standard implementation flow from tasks.md. This is the normal behavior when the teams trait is not active.

## Key Principles

- **Teams for parallelism, not complexity**: Only use teams when genuine parallel work exists
- **Lead never implements**: The lead's job is review and coordination
- **Spec is the standard**: All review decisions based on spec.md
- **Worktrees prevent conflicts**: Each teammate has clean file isolation
- **Beads preserves state**: Task progress survives across sessions
- **Graceful degradation**: Always fall back to sequential if teams can't help
- **Respect task dependencies**: Never assign dependent tasks to different teammates

## Failure Handling

- **Teammate crashes**: Spawn a replacement teammate for unfinished tasks, or implement directly if near the end of the work
- **Merge conflicts**: Do NOT auto-resolve. Report the conflict to the user and wait for guidance
- **Review deadlock (3+ attempts)**: Message the teammate to stop work, report the situation to the user, and pause orchestration
