
<!-- SDD-TRAIT:worktrees -->
## Worktree Context

Before starting implementation, check for a handoff file from the specify session. Read its content, then delete it immediately so it cannot be accidentally committed or merged:

```bash
if [ -f ".claude/sdd-handoff.md" ]; then cat .claude/sdd-handoff.md && rm -f .claude/sdd-handoff.md; fi
```

If content was found, use it (brainstorm summary, key decisions, constraints) as additional context for implementation. The file has been consumed and removed.
