---
name: teams-spec-guardian
description: "DEPRECATED: Merged into sdd:teams-orchestrate. Use the consolidated 'teams' trait instead of 'teams-spec'."
deprecated: true
replacement: sdd:teams-orchestrate
---

# Spec Guardian: Lead Reviews, Teammates Implement

## Overview

This skill implements the spec guardian pattern for the `teams-spec` trait. The lead session does not implement any tasks. Instead, it:

1. Bootstraps beads issues from tasks.md (if not already synced)
2. Spawns teammates in isolated git worktrees
3. Reviews each teammate's completed work against spec.md
4. Merges compliant changes, rejects non-compliant work with feedback
5. Syncs final state back to beads

**This skill supersedes `sdd:teams-orchestrate`** when both `teams-vanilla` and `teams-spec` traits are active. Check `.specify/sdd-traits.json` for `teams-spec: true` to confirm this skill should run.

## 1. Beads Bootstrap

Before spawning any teammates, ensure beads issues exist for all tasks:

```bash
SPEC_DIR="specs/[feature-name]"
ISSUE_COUNT=$(bd list --json 2>/dev/null | jq 'if type == "object" and .error then 0 else length end')
TASK_COUNT=$(grep -c '^\- \[ \]' "$SPEC_DIR/tasks.md" 2>/dev/null || echo 0)
```

- If `bd` is not installed: **STOP.** Report error. The beads trait is required.
- If issue count is 0 but tasks exist: Run `"<sdd-beads-sync-command>" "$SPEC_DIR/tasks.md"` to create issues.
- If issues already exist: Proceed. Report: "Beads issues already synced ([N] issues)."

## 2. Task Graph Analysis

Same as `sdd:teams-orchestrate`: read tasks.md, identify independent task groups, determine parallel opportunities.

- If no parallelism possible: execute sequentially (but the lead still acts as guardian, running review-code after each task completion).
- If 2+ independent groups: proceed with worktree spawning.

## 3. Worktree Teammate Spawning

Each teammate gets its own git worktree for file isolation.

### Spawn Rules

- **Maximum 5 teammates** (same as vanilla)
- Each teammate works in an **isolated git worktree** (use `isolation: "worktree"` or instruct the teammate to use the `EnterWorktree` tool)
- The lead MUST NOT implement any tasks itself

### Spawn Prompt Template

Each teammate receives:

```
You are implementing tasks for the [feature-name] feature.
You are working in an isolated git worktree.

## Your Assigned Tasks

[List the specific tasks assigned to this teammate with bd issue IDs]

## Spec Context

[Contents of spec.md for this feature]

## Working Rules

1. Implement each task completely before moving to the next
2. Commit after each task with a descriptive message
3. When all your tasks are done, message the lead: "Tasks complete, ready for review"
4. If you encounter a blocker, message the lead with details
5. Do not modify files outside your assigned task scope
6. Your work will be reviewed against spec.md before merging
```

## 4. Spec Guardian Review Loop

The lead monitors teammates and reviews their work as they complete tasks.

### When a Teammate Reports Completion

1. **Review the changes**: Examine the teammate's worktree diff against the working branch
2. **Run spec compliance check**: Invoke `{Skill: sdd:review-code}` against the teammate's changes, checking compliance with spec.md
3. **Decision**:

   **If review PASSES:**
   - Merge the worktree changes into the working branch
   - Mark the corresponding beads issue(s) as closed: `bd close <id> -r "Reviewed and merged"`
   - Run `bd backup` to persist state
   - Message the teammate: "Work approved and merged. Move to your next task."

   **If review FAILS:**
   - Send feedback to the teammate listing specific spec violations
   - Include the exact spec requirements that were not met
   - Message: "Review failed. Please fix these issues: [list violations]"
   - Do NOT merge non-compliant work
   - The teammate fixes and re-submits

### Lead Behavior During Reviews

- The lead coordinates and reviews. It does NOT implement.
- The lead may research questions from teammates, clarify spec requirements, and make review decisions.
- If the lead notices a spec ambiguity during review, note it but do not block the merge if the implementation is reasonable.

## 5. Failure Handling

### Teammate Crashes Mid-Task

1. Detect the idle/stopped teammate
2. Log the failure and the task it was working on
3. Either:
   - Spawn a replacement teammate in a new worktree for the remaining tasks
   - If near the end, implement the remaining task(s) directly (exception to no-implement rule)

### Merge Conflicts

1. If merging a worktree produces conflicts, **do not auto-resolve**
2. Report the conflict to the user with details:
   - Which files conflict
   - Which teammates' changes are involved
3. Pause and wait for user guidance

### Review Deadlock

If a teammate repeatedly fails review (3+ attempts on the same task):
1. Message the teammate to stop
2. Report to the user: "Teammate unable to pass spec review after 3 attempts. Manual intervention needed."
3. Pause implementation

## 6. Final Sync

When all tasks are complete and merged:

1. **Verify all beads issues are closed:**
   ```bash
   bd list --status open --json 2>/dev/null | jq 'if type == "object" and .error then error(.error) else length end'
   ```
   Should return 0.

2. **Run reverse sync** to update tasks.md checkboxes:
   ```bash
   "<sdd-beads-sync-command>" "$SPEC_DIR/tasks.md" --reverse
   ```

3. **Final beads backup:**
   ```bash
   bd backup
   ```

4. **Clean up the team:**
   Ask Claude to clean up the agent team resources.

5. **Report completion:**
   - Total tasks executed
   - Tasks that required re-review
   - Any discovered work items
   - Final beads status

## Key Principles

- **Lead never implements**: The lead's job is review and coordination, not coding
- **Spec is the standard**: All review decisions are based on spec.md compliance
- **Worktrees prevent conflicts**: Each teammate has clean file isolation
- **Beads preserves state**: Task progress survives across sessions
- **Graceful degradation**: If teams fail, fall back to sequential with review
