# Data Model: spex-detach Extension

## Entities

### 1. Extension Configuration (`spex-detach-config.yml`)

Installed to `.specify/extensions/spex-detach/spex-detach-config.yml` from the config template during `specify init`.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `archive.path` | string | `""` | Local filesystem path to project-specs repo |
| `archive.auto_commit` | boolean | `true` | Auto-commit archived specs |
| `upstream.default_branch` | string | `""` | Override upstream default branch (auto-detect if empty) |
| `detach.strip_paths` | string[] | `[".specify", "specs", "brainstorm"]` | Paths to strip from clean PR branch |

### 2. Extension Manifest (`extension.yml`)

Standard spec-kit extension manifest. See `contracts/spex-detach-sh.md` for the full manifest.

| Field | Value |
|-------|-------|
| `extension.id` | `spex-detach` |
| `extension.name` | `Spex Detach` |
| `extension.version` | `1.0.0` |
| `extension.description` | Detach spec artifacts at PR time for contributing to projects that don't use SDD |
| `requires.speckit_version` | `>=0.5.2` |
| `requires.tools` | `git` (required) |

### 3. Clean PR Branch (`pr/<feature-branch-name>`)

A git branch, not a file. Created by `spex-detach.sh detach`.

| Property | Value |
|----------|-------|
| Name | `pr/<feature-branch-name>` |
| Parent commit | Merge-base of feature branch and upstream default branch |
| Contents | Single squashed commit with all code changes, no spec artifacts |
| Lifecycle | Created at finish time, regenerated on re-run (idempotent) |

### 4. Archive Directory Structure

Created in the project-specs repo at `<archive-path>/<project-name>/<feature-name>/`.

```text
<archive-path>/
└── <project-name>/           # e.g., opendatahub-io/odh-dashboard
    └── <feature-name>/       # e.g., 029-upstream-contrib-mode
        ├── .specify/         # Spec-kit configuration snapshot
        └── specs/
            └── <feature>/    # spec.md, plan.md, tasks.md
```

## Relationships

```text
Extension Config ──reads──> spex-detach.sh ──creates──> Clean PR Branch
                                          ──copies───> Archive Directory
Feature Branch ────input──> spex-detach.sh
Upstream Default ──input──> spex-detach.sh (merge-base calculation)
```

## State Transitions

The extension does not maintain its own state. It operates as a stateless transformation during the finish flow:

```text
Feature Branch (with specs) ──detach──> Clean PR Branch (code only)
                            ──archive──> Project-specs repo (specs preserved)
```

The existing `.specify/.spex-state` flow state is managed by the core `spex` extension and is unaffected by `spex-detach`.
