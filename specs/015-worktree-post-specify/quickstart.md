# Quickstart: Post-Specify Worktree Creation

**Branch**: `015-worktree-post-specify` | **Date**: 2026-04-06

## What Changes

This feature updates the worktrees trait so that after `speckit.specify` completes:
1. All modified tracked files are committed to the feature branch
2. The original repo is restored to `main`
3. A worktree is created at `<parent>/<repo-name>:<branch-name>`
4. Switch instructions are printed

## Files to Modify

1. **`spex/skills/worktree/SKILL.md`** - Update path computation (colon naming), commit scope (all tracked files), FR references
2. **`spex/overlays/worktrees/skills/speckit-specify/SKILL.append.md`** - Minor: verify delegation text is clear about ordering

## Key Implementation Details

### Colon Naming (R1)
```bash
REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")
RESOLVED_BASE=$(cd "$REPO_ROOT/$BASE_PATH" && pwd)
WORKTREE_PATH="${RESOLVED_BASE}/${REPO_NAME}:${BRANCH_NAME}"
```

### Broad Commit (R2)
```bash
git add -A
if ! git diff --cached --quiet; then
  git commit -m "feat: Add spec for $BRANCH_NAME

Assisted-By: 🤖 Claude Code"
fi
```

### Worktree Detection (existing, no change)
```bash
GIT_DIR=$(git rev-parse --git-dir)
if [ "$GIT_DIR" != "$REPO_ROOT/.git" ] && [ "$GIT_DIR" != ".git" ]; then
  # Inside a worktree, skip creation
fi
```

## Testing

Run `make release` to validate schema and integration test. Then manually test:
1. Enable worktrees trait: `/spex:traits enable worktrees`
2. Run `/speckit-specify` on a test feature
3. Verify worktree created with colon naming
4. Verify original repo on `main`
5. Start new session in worktree, verify `spex:init` triggers
