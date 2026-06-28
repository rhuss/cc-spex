# Research: spex-detach Extension

## R1: Git mechanism for squash-onto-base clean branch creation

**Decision**: Use `git diff` with pathspec exclusions + `git apply` on a new branch rooted at merge-base.

**Rationale**: This produces a clean single-commit branch that shows only code changes. The merge-base anchoring ensures the PR diff against upstream's default branch is minimal and correct. Using `git diff` pathspec exclusions (`:!.specify`, `:!specs`, `:!brainstorm`) is the simplest reliable way to filter spec artifacts.

**Implementation sequence**:
```bash
MERGE_BASE=$(git merge-base "$UPSTREAM_DEFAULT" "$FEATURE_BRANCH")
PR_BRANCH="pr/$FEATURE_BRANCH"

# Delete existing PR branch if present (idempotent regeneration)
git branch -D "$PR_BRANCH" 2>/dev/null || true

# Create PR branch from merge-base
git checkout -b "$PR_BRANCH" "$MERGE_BASE"

# Apply filtered diff
git diff "$MERGE_BASE".."$FEATURE_BRANCH" -- \
  ':!.specify' ':!.specify/**' \
  ':!specs' ':!specs/**' \
  ':!brainstorm' ':!brainstorm/**' \
  | git apply --index

# Commit
git commit -m "$(git log --format='%s' "$MERGE_BASE".."$FEATURE_BRANCH" | head -1)"

# Return to feature branch
git checkout "$FEATURE_BRANCH"
```

**Alternatives considered**:
- `git filter-branch` / `git filter-repo`: Too heavy, rewrites history. Overkill for creating a single derived branch.
- Cherry-pick with exclusions: Git doesn't support per-file cherry-pick. Would require manual conflict resolution.
- Orphan branch + checkout files: Creates a branch with no parent, which makes PR diffs confusing on GitHub.

**Edge case: binary files**: `git diff | git apply` handles binary files via `--binary` flag. Include `--binary` in the diff command.

**Edge case: empty diff**: If all changes are spec-only, the diff will be empty. The script should detect this and warn instead of creating an empty commit.

## R2: Extension manifest and hook registration

**Decision**: Use `before_finish` hook point for archiving, and modify the finish command to detect spex-detach for clean branch creation.

**Rationale**: The `before_finish` hook runs before verification (Phase 1). Archiving at this point is safe because the specs already exist on the feature branch. Clean branch creation must happen after Phase 2 (commit outstanding changes), so it cannot be a hook; it must be inline in the finish command.

**Hook registration pattern** (from existing extensions):
```yaml
hooks:
  before_finish:
    command: speckit.spex-detach.detach
    args: "archive"
    optional: true
    prompt: "Archive specs to project-specs repo?"
    description: "Copy spec artifacts to configured archive path"
```

**Finish command modification**: Add a detection block after Phase 2 that checks for `spex-detach` extension and calls the detach script. This follows the same pattern as the existing brainstorm file exclusion in Phase 5 (Option B2) of the finish command.

## R3: Extension configuration file format

**Decision**: YAML config file following the `spex-collab` pattern.

**Rationale**: Existing extensions with configuration (spex-collab, spex-deep-review, spex-teams) use YAML config files with a `config-template.yml` that gets installed to `.specify/extensions/<id>/`. This is the established pattern.

**Config template**:
```yaml
# spex-detach configuration
archive:
  # Path to project-specs repository for spec archiving
  # Leave empty to skip archiving
  path: ""
  # Auto-commit archived specs to the project-specs repo
  auto_commit: true

upstream:
  # Override upstream's default branch (auto-detected from origin if empty)
  default_branch: ""

detach:
  # Paths to strip from the clean PR branch
  strip_paths:
    - ".specify"
    - "specs"
    - "brainstorm"
```

## R4: Project name derivation from git remote

**Decision**: Parse `origin` remote URL to extract `owner/repo`, use as project name in archive path.

**Rationale**: The `origin` remote in a fork points to the contributor's fork. For upstream project identification, the `upstream` remote (if set) is more accurate. Fallback chain: `upstream` remote > `origin` remote > directory name.

**Implementation**:
```bash
get_project_name() {
  local remote_url
  remote_url=$(git remote get-url upstream 2>/dev/null || git remote get-url origin 2>/dev/null || echo "")
  if [ -n "$remote_url" ]; then
    # Handle both HTTPS and SSH URLs
    echo "$remote_url" | sed 's|.*github\.com[:/]||; s|\.git$||'
  else
    basename "$(git rev-parse --show-toplevel)"
  fi
}
```

**Alternatives considered**:
- Using only `origin`: Misidentifies the project when `origin` is the fork, not the upstream.
- Using directory name always: Loses the owner/repo context that distinguishes forks.

## R5: Interaction with existing finish flow

**Decision**: Detect spex-detach between Phase 2 and Phase 4 of the finish command. Add a new "Push clean PR branch" option when detach is active.

**Rationale**: The finish command already has conditional behavior (worktree detection, autonomous mode, existing PR detection). Adding spex-detach detection fits naturally.

**Modified Phase 4 options when spex-detach is active**:
1. "Push clean PR branch to upstream" (Recommended) - pushes `pr/<branch>` 
2. "Merge to default branch" - normal merge behavior
3. "Keep branch as-is" - no action

**Detection logic**:
```bash
DETACH_ENABLED=false
DETACH_SCRIPT=""
if [ -d ".specify/extensions/spex-detach" ]; then
  DETACH_SCRIPT=$(find ~/.claude -name 'spex-detach.sh' 2>/dev/null | head -1)
  if [ -x "$DETACH_SCRIPT" ]; then
    DETACH_ENABLED=true
  fi
fi
```
