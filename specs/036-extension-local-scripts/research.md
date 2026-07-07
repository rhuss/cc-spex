# Research: Extension-Local Scripts

## Decision: Script Distribution Mechanism

**Chosen**: Build-time sync via Makefile target (`make sync-scripts`)
**Rationale**: Single source of truth in `spex/scripts/`, copies distributed to extensions at build time. `specify extension add` already copies entire extension directories including `scripts/`. No upstream spec-kit changes needed.
**Alternatives considered**:
- Core extension owns all scripts: fragile install-order dependency, silent cascade failures
- Shared scripts directory: needs upstream spec-kit support that doesn't exist

## Decision: CI Enforcement

**Chosen**: Makefile `sync-scripts-check` target as prerequisite of `release`
**Rationale**: CI runs `make sync-scripts-check` which uses `diff` to compare canonical scripts against extension copies. Fails with clear remediation message. No pre-commit hook (adds friction without improving safety over CI).
**Alternatives considered**:
- Git pre-commit hook: not all contributors would have hooks installed

## Decision: Context Hook Plugin Root Tag

**Chosen**: Remove `<plugin-root>` tag from the injected `<spex-context>` block. Keep internal `plugin_root` variable for command file lookups.
**Rationale**: Commands no longer need `$PLUGIN_ROOT` at runtime. The context hook still needs it internally to find command files for `{Skill:` delegation checking, but this is resolved at hook execution time by Python's `Path(__file__).parent.parent.parent`.
**Alternatives considered**:
- Remove plugin_root entirely: breaks command file lookup in context-hook.sh

## Decision: spex-init.sh Changes

**Chosen**: Minimal changes. The existing `install_extensions` function already calls `specify extension add` which copies scripts. The `configure_statusline` function uses `$script_dir` (relative to init script location) for the statusline script, which still works since the canonical copy exists during init.
**Rationale**: `spex-init.sh` is already well-structured. No script-copy logic to remove. The extension add pathway handles script installation automatically.
**Alternatives considered**:
- Rewrite init to reference extension-local statusline: unnecessary complexity since init runs from the plugin root

## Finding: Skill Files Mirror Command Files

Skills in `.claude/skills/` are generated from command files in `spex/extensions/*/commands/` by `specify extension add`. Both contain the same `$PLUGIN_ROOT` references. Updating command files causes skills to be regenerated on the next `specify init`/`specify extension add`. However, for the current installed state, skill files must be updated independently since they're generated artifacts that persist between inits.

## Finding: context-hook.sh Internal Usage Is Safe

The shared `context-hook.sh` script accepts `$PLUGIN_ROOT` as its 4th argument and uses it to search for command files (checking for `{Skill:` delegation markers). This is an internal hook operation that runs at hook execution time, not at command runtime. The Python wrapper (`context-hook.py`) resolves the plugin root from its own file path (`Path(__file__).parent.parent.parent`). This internal usage does not depend on the `<plugin-root>` tag and should remain unchanged.

## Finding: Statusline Script Path

The `spex-ship-statusline.sh` script is referenced by `configure_statusline()` in `spex-init.sh` via `$script_dir/spex-ship-statusline.sh`. This resolves to `spex/scripts/spex-ship-statusline.sh` at init time. The script is then configured with an absolute path in `.claude/settings.local.json`. This works independently of the extension-local script mechanism since the statusline is configured during init, not at command runtime. The statusline script should be included in the `spex` extension's scripts for completeness.
