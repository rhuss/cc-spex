
<!-- SDD-TRAIT:worktrees -->
## Worktree Context

Before starting implementation, check for a handoff file from the specify session:

```bash
if [ -f ".claude/sdd-handoff.md" ]; then cat .claude/sdd-handoff.md; fi
```

If found, read it and use its content (brainstorm summary, key decisions, constraints) as additional context for implementation.
