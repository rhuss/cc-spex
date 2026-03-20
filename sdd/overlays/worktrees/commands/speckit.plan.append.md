
<!-- SDD-TRAIT:worktrees -->
## Worktree Context

Before starting the planning workflow, check for a handoff file from the specify session:

```bash
if [ -f ".claude/sdd-handoff.md" ]; then cat .claude/sdd-handoff.md; fi
```

If found, read it and use its content (brainstorm summary, key decisions, constraints) as additional context for planning. This file bridges the gap between the specify session (in the main repo) and this planning session (in the worktree).
