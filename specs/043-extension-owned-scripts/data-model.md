# Data Model: Extension-Owned Scripts

## Makefile Variables (before -> after)

```makefile
# BEFORE
SCRIPTS_spex := spex-flow-state.sh spex-ship-state.sh spex-ship-statusline.sh spex-finish-context.sh spex-worktree-cwd.sh spex-detach.sh
SCRIPTS_spex_detach := spex-detach.sh

# AFTER
SCRIPTS_spex := spex-flow-state.sh spex-ship-state.sh spex-ship-statusline.sh spex-finish-context.sh spex-worktree-cwd.sh
SCRIPTS_spex_detach :=
```

## File Modification Map

| File | Change Type | FR Coverage |
|------|-------------|-------------|
| `Makefile` | Modify (SCRIPTS variables) | FR-002, FR-006, FR-007 |
| `spex/scripts/spex-detach.py` | Delete | FR-001 |
| `spex/scripts/spex-detach.sh` | Delete | FR-001 |
| `spex/extensions/spex/scripts/spex-detach.py` | Delete | FR-005 |
| `spex/extensions/spex/scripts/spex-detach.sh` | Delete | FR-005 |
| `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md` | Modify (harness marker) | FR-008 |

## Files NOT changed

| File | Reason |
|------|--------|
| `spex/extensions/spex-detach/scripts/spex-detach.py` | Already the authoritative copy, no changes needed |
| `spex/extensions/spex-detach/scripts/spex-detach.sh` | Already the authoritative copy, no changes needed |
| `spex/scripts/spex-flow-state.sh` | Stays canonical (shared) |
| `spex/scripts/spex-adapt-commands.sh` | Build utility, not extension script |
| `spex/scripts/spex-init.sh` | Init utility, not extension script |
