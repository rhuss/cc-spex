# Contract: spex-detach.sh

Shell script providing the core git operations for the spex-detach extension.

Location: `spex/scripts/bash/spex-detach.sh`

## Interface

```bash
spex-detach.sh <subcommand> [options]
```

### Subcommand: `detach`

Create a clean PR branch by squashing code-only changes onto the merge-base.

```bash
spex-detach.sh detach [--branch <name>] [--base <branch>] [--strip <path>...]
```

| Option | Default | Description |
|--------|---------|-------------|
| `--branch` | Current branch | Feature branch to detach from |
| `--base` | Auto-detect from origin | Upstream default branch for merge-base |
| `--strip` | `.specify specs brainstorm` | Paths to exclude from the clean branch |

**Output**: JSON to stdout
```json
{
  "pr_branch": "pr/029-upstream-contrib-mode",
  "merge_base": "abc1234",
  "commit": "def5678",
  "files_changed": 12,
  "empty": false
}
```

**Exit codes**:
- `0`: Clean PR branch created successfully
- `1`: Error (git operation failed, branch not found)
- `2`: Empty diff (all changes were spec-only, no code changes)

### Subcommand: `archive`

Copy spec artifacts to the project-specs repo archive path.

```bash
spex-detach.sh archive --target <path> [--project <name>] [--feature <name>] [--auto-commit]
```

| Option | Default | Description |
|--------|---------|-------------|
| `--target` | (required) | Path to project-specs repo |
| `--project` | Derived from git remote | Project identifier (`owner/repo`) |
| `--feature` | Current branch name | Feature identifier |
| `--auto-commit` | `false` | Commit archived specs to target repo |

**Output**: JSON to stdout
```json
{
  "archive_path": "/path/to/project-specs/owner/repo/feature",
  "files_copied": 15,
  "committed": true
}
```

**Exit codes**:
- `0`: Archive successful
- `1`: Error (target path unreachable, git operation failed)

### Subcommand: `is-enabled`

Check if spex-detach extension is installed and active.

```bash
spex-detach.sh is-enabled
```

**Exit codes**:
- `0`: Extension is enabled
- `1`: Extension is not installed or disabled

### Subcommand: `clean-branch-name`

Output the clean PR branch name for a given feature branch.

```bash
spex-detach.sh clean-branch-name [--branch <name>]
```

**Output**: Branch name to stdout (e.g., `pr/029-upstream-contrib-mode`)

## Extension Manifest

```yaml
schema_version: "1.0"

extension:
  id: spex-detach
  name: "Spex Detach"
  version: "1.0.0"
  description: "Detach spec artifacts at PR time for contributing to projects that don't use spec-driven development"
  author: cc-spex
  license: MIT

requires:
  speckit_version: ">=0.5.2"
  tools:
    - name: git
      required: true

provides:
  commands:
    - name: speckit.spex-detach.detach
      file: commands/speckit.spex-detach.detach.md
      description: "Create clean PR branch with spec artifacts stripped"

  config:
    - name: "spex-detach-config.yml"
      template: "config-template.yml"
      description: "Detach extension configuration (archive path, upstream branch)"
      required: false

hooks:
  before_finish:
    command: speckit.spex-detach.detach
    args: "archive"
    optional: true
    prompt: "Archive specs to project-specs repo before finishing?"
    description: "Copy spec artifacts to configured archive path"

tags:
  - "spex"
  - "upstream"
  - "contribution"
  - "detach"
```
