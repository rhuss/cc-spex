
<!-- SDD-TRAIT:worktrees -->
## Worktree Context

Before starting implementation, check for a handoff file from the specify session:

```bash
if [ -f ".claude/sdd-handoff.md" ]; then cat .claude/sdd-handoff.md; fi
```

If found, read it and use its content (brainstorm summary, key decisions, constraints) as additional context for implementation.

## Post-Implementation Cleanup

After all implementation tasks are complete and before merging to main, remove the handoff file. It is temporary context from the specify session and must not be merged:

```bash
rm -f .claude/sdd-handoff.md
```

If it was tracked by git, also commit the removal:

```bash
git rm --cached .claude/sdd-handoff.md 2>/dev/null && git commit -m "Remove temporary handoff file"
```
