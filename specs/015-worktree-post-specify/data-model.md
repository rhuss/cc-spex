# Data Model: Post-Specify Worktree Creation

**Branch**: `015-worktree-post-specify` | **Date**: 2026-04-06

## Entities

### Trait Configuration (`.specify/spex-traits.json`)

```json
{
  "version": 1,
  "traits": {
    "superpowers": true,
    "worktrees": true
  },
  "worktrees_config": {
    "base_path": ".."
  },
  "applied_at": "2026-04-06T10:00:00Z"
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `traits.worktrees` | boolean | `false` | Enables/disables worktree creation after specify |
| `worktrees_config.base_path` | string | `".."` | Parent directory for worktree creation, relative to repo root |

**Identity**: Singleton per project. Located at `.specify/spex-traits.json`.
**Lifecycle**: Created by `spex-traits.sh init`, modified by `enable`/`disable`.

### Worktree Directory

| Attribute | Derivation | Example |
|-----------|-----------|---------|
| `REPO_NAME` | `basename $(git rev-parse --show-toplevel)` | `cc-spex` |
| `BRANCH_NAME` | `git rev-parse --abbrev-ref HEAD` | `015-worktree-post-specify` |
| `BASE_PATH` | From `worktrees_config.base_path` | `..` |
| `WORKTREE_PATH` | `<resolved-base>/<repo-name>:<branch-name>` | `/path/to/cc-spex:015-worktree-post-specify` |

**Identity**: Unique by `WORKTREE_PATH`. Git enforces one worktree per branch.
**Lifecycle**: Created by `git worktree add`, removed by `git worktree remove`.

### Overlay File

| Attribute | Value |
|-----------|-------|
| Location | `spex/overlays/worktrees/skills/speckit-specify/SKILL.append.md` |
| Sentinel | `<!-- SPEX-TRAIT:worktrees -->` |
| Target | `.claude/skills/speckit-specify/SKILL.md` |
| Max lines | 30 (constitution II) |

**Identity**: One overlay file per trait-skill combination.
**Lifecycle**: Static file in repo. Applied/removed by `spex-traits.sh apply`.

## State Transitions

### Worktree Creation Sequence

```
specify completes (on feature branch)
    ↓
[superpowers overlay] review-spec validates
    ↓
[worktrees overlay] invokes spex:worktree create
    ↓
Step 1: Read config (base_path)
    ↓
Step 2: Get branch name, verify NNN-* pattern
    ↓
Step 3: Detect if already in worktree → SKIP if yes
    ↓
Step 4: Compute target path, check not exists → ERROR if exists
    ↓
Step 5: git add -A && git commit (all modified tracked files)
    ↓
Step 6: git checkout main → ERROR if fails (uncommitted changes)
    ↓
Step 7: git worktree add <path> <branch> → ERROR if fails
    ↓
Step 8: Print switch instructions
```

Each error state is a terminal state for worktree creation only; the specify flow itself is not affected (spec files are already on the feature branch).

## Relationships

```
spex-traits.json ──enables──> worktrees overlay
worktrees overlay ──appends to──> speckit-specify skill
speckit-specify skill ──invokes──> spex:worktree skill (create action)
spex:worktree skill ──reads──> spex-traits.json (base_path)
spex:worktree skill ──creates──> worktree directory
spex:worktree skill ──modifies──> git state (commit, checkout, worktree add)
```
