# Data Model: Detach Stealth Mode

## Entities

### Exclude Entry

A line in `.git/info/exclude` that prevents git from tracking a path.

| Field | Type | Description |
|-------|------|-------------|
| pattern | string | Git exclude pattern (e.g., `.specify/`, `specs/`, `brainstorm/`) |

Default patterns: `.specify/`, `specs/`, `brainstorm/`

Configurable via `exclude.paths` in `spex-detach-config.yml`.

### Archive

A copy of spec artifacts in the sibling specs repo.

| Field | Type | Description |
|-------|------|-------------|
| project_name | string | Derived from git remote URL (e.g., `NVIDIA/OpenShell`) |
| feature_name | string | Current git branch name (e.g., `045-detach-stealth-mode`) |
| archive_path | string | Configured sibling repo path |
| auto_commit | boolean | Whether to auto-commit after copying (default: true) |

Directory structure in sibling repo:
```
<archive_path>/
  <project_name>/
    <feature_name>/
      .specify/          # copied from code repo
      specs/             # copied from code repo
      brainstorm/        # copied from code repo (if include_brainstorm is set)
```

### Config (spex-detach-config.yml)

New simplified schema:

```yaml
archive:
  path: ""              # Path to sibling specs repo (empty = skip archiving)
  auto_commit: true     # Auto-commit archived specs

exclude:
  paths:                # Paths to add to .git/info/exclude
    - ".specify/"
    - "specs/"
    - "brainstorm/"
```

Removed fields (from old config):
- `upstream.default_branch` (was for merge-base in detach subcommand)
- `detach.strip_paths` (replaced by `exclude.paths`)

## State Transitions

### Extension Lifecycle

```
disabled -> enabled (specify extension enable spex-detach)
  -> exclude entries written (.git/info/exclude)
  -> spec files become invisible to git
  -> development proceeds normally
  -> finish triggers archive (if configured)
  -> exclude entries persist across branches/rebases
```

### Subcommand Map (old -> new)

| Old | New | Status |
|-----|-----|--------|
| `detach` | (removed) | PR branch stripping no longer needed |
| `verify` | (removed) | No PR branch to verify |
| `clean-branch-name` | (removed) | No PR branch naming needed |
| `archive` | `archive` | Simplified: copy + commit only |
| `is-enabled` | `is-enabled` | Unchanged |
| (none) | `enable` | New: write .git/info/exclude entries |
