# Data Model: Extension-Local Scripts

## Entities

### Canonical Script
A shell or Python script in `spex/scripts/` that is the single source of truth.

| Attribute | Description |
|-----------|-------------|
| path | Relative path under `spex/scripts/` (e.g., `spex-flow-state.sh`, `bash/spex-detach.sh`) |
| consumers | List of extension IDs that need this script |

### Extension Script Copy
A copy of a canonical script placed in an extension's source directory.

| Attribute | Description |
|-----------|-------------|
| source | Path to the canonical script in `spex/scripts/` |
| target | Path in `spex/extensions/<ext-id>/scripts/<script>` |
| extension_id | The extension this copy belongs to |

### Script Inventory
The mapping that defines which scripts belong to which extensions. Defined as Makefile variables.

| Attribute | Description |
|-----------|-------------|
| SCRIPTS_spex | Scripts for the `spex` core extension |
| SCRIPTS_spex_gates | Scripts for the `spex-gates` extension |
| SCRIPTS_spex_collab | Scripts for the `spex-collab` extension |
| SCRIPTS_spex_deep_review | Scripts for the `spex-deep-review` extension |
| SCRIPTS_spex_detach | Scripts for the `spex-detach` extension |

## Inventory Table

| Script | spex | spex-gates | spex-collab | spex-deep-review | spex-detach |
|--------|------|------------|-------------|------------------|-------------|
| spex-flow-state.sh | x | x | x | x | |
| spex-ship-state.sh | x | | | | |
| spex-ship-statusline.sh | x | | | | |
| spex-finish-context.sh | x | | | | |
| spex-worktree-cwd.sh | x | | | | |
| spex-closeout-gate.sh | | x | | | |
| spex-triage-state.sh | | | x | | |
| sanitize-gh-json.py | | | x | | |
| bash/spex-detach.sh | x | | | | x |

## Path Resolution

### At Build Time (Makefile)
```
spex/scripts/<script> -> spex/extensions/<ext-id>/scripts/<script>
```

### At Install Time (specify extension add)
```
spex/extensions/<ext-id>/scripts/<script> -> .specify/extensions/<ext-id>/scripts/<script>
```

### At Runtime (command/skill execution)
```
.specify/extensions/<ext-id>/scripts/<script>
```
Where `<ext-id>` is the extension that owns the command referencing the script.
