# Research: Detach Stealth Mode

## .git/info/exclude Behavior

**Decision**: Use .git/info/exclude as the mechanism for hiding spec files from git.

**Rationale**: Experimentally verified that .git/info/exclude provides identical behavior to .gitignore but is local-only (never committed, never pushed). This is the standard git mechanism for per-developer exclusions.

**Alternatives considered**:
- `.gitignore` (committed): Rejected because it modifies the upstream project's committed files.
- Global gitignore (`~/.gitignore`): Works but is user-wide, not project-specific. Could be added as belt-and-suspenders but not the primary mechanism.
- `pr/` branch stripping (current approach): Rejected because it allows spec files to be committed to feature branches, where rebase/merge can carry them to unrelated PRs.

**Key properties verified**:
- `git add .` and `git add -A` skip excluded paths
- `git status` hides excluded paths
- Files remain on disk, accessible to spec-kit via cwd resolution
- Only `git add -f` overrides the exclusion
- Since files are never committed, rebase/merge cannot propagate them

## Extension Hook for specify init

**Decision**: Use an `after_init` lifecycle hook in extension.yml to auto-run enable during `specify init`.

**Rationale**: spec-kit supports `after_init` hooks in extension manifests. This ensures the exclude entries are written automatically when the detach extension is active during project initialization.

**Alternatives considered**:
- `before_specify` hook: Too late; spec files should be excluded before any spec-kit operation writes them.
- Manual-only: Requires the developer to remember to run enable separately. Error-prone.

## Archive Directory Structure

**Decision**: Archive to `<archive-path>/<project-name>/<feature-branch-name>/` preserving internal directory structure.

**Rationale**: Consistent with the existing archive subcommand behavior. Project name derived from git remote URL (upstream or origin). Feature name from current branch.

**Alternatives considered**:
- Flat structure (all specs in one directory): Loses project/feature organization.
- Numbered structure (matching spec directory names): Branch names are more meaningful than spec numbers for cross-project archiving.

## Config Template Simplification

**Decision**: Remove `upstream.default_branch` and `detach.strip_paths` from config-template.yml. Keep `archive.path` and `archive.auto_commit`. Add `exclude.paths` as the new configurable list.

**Rationale**: `upstream.default_branch` was used by the old detach subcommand for merge-base calculation. `detach.strip_paths` configured the old pr/ branch stripping paths. Neither is needed. The `exclude.paths` key replaces strip_paths for the enable command.

## Submit Skill Changes

**Decision**: Remove the "Phase 2b: Detach Detection" section from the submit skill. With stealth mode, there is no clean PR branch to push; the main branch is already clean.

**Rationale**: The submit skill currently checks if spex-detach is enabled and offers to push the `pr/` branch to upstream. Since `pr/` branches no longer exist, this logic must be removed. The developer pushes their feature branch directly (it never contains spec files).
