
<!-- SDD-TRAIT:worktrees -->
## Worktree Isolation

After completing the specification and all quality gates:

1. Invoke {Skill: sdd:worktree} with action "create" to:
   - Create a git worktree for the feature branch in a sibling directory
   - Restore `main` in the original repo
   - Print instructions for switching to the worktree
