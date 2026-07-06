# Brainstorm: Extension-Local Scripts (Replace $PLUGIN_ROOT)

**Date:** 2026-07-06
**Status:** active
**Related:** [#28 Harness-Agnostic Spex](28-harness-agnostic-spex.md), [#29 Replace find with plugin root](29-replace-find-with-plugin-root.md)
**Upstream:** [spec-kit#3308](https://github.com/github/spec-kit/issues/3308), [spec-kit#3359](https://github.com/github/spec-kit/issues/3359)

## Problem Framing

Extension commands reference helper scripts at runtime (flow-state, ship-state, triage, detach, etc.). The current mechanism uses `$PLUGIN_ROOT`, extracted from a `<plugin-root>` tag that Claude Code injects into the system prompt. This points to the Claude Code plugin cache (e.g., `~/.claude/plugins/cache/spex-plugin-development/spex/5.8.0/scripts/`).

This is entirely Claude Code-specific. Moving to harness-agnostic operation requires eliminating this dependency. The scripts need to be reachable from any agent harness without relying on Claude Code's plugin infrastructure.

Today, scripts live in `spex/scripts/` (top-level, outside extensions). When `specify extension add` installs an extension, it copies `commands/` and `extension.yml` to `.specify/extensions/<id>/` but no scripts. The commands then rely on `$PLUGIN_ROOT` to find the scripts at runtime.

## Approaches Considered

### A: Extension-Local Scripts with Build-Time Sync (chosen)

Move scripts into each extension's source directory. `specify extension add` installs them alongside commands. Commands reference their own extension's scripts via relative paths from the project root.

A Makefile target syncs scripts from the canonical source (`spex/scripts/`) into each extension's `scripts/` dir at build/release time.

- Pros: Each extension is self-contained. Works with any harness. No `$PLUGIN_ROOT`, no Claude Code dependency. `specify extension add` just works without needing `spex-init.sh`. Init scripts shrink to just extension-add calls. Scripts are duplicated but ephemeral (regenerated on every init/refresh, never user-edited).
- Cons: Duplicated scripts in git. Requires a sync step in the build process. Needs CI check to catch forgotten syncs.

### B: Core Extension Owns All Scripts

Put all shared scripts in the `spex` core extension. Other extensions reference scripts cross-extension via `.specify/extensions/spex/scripts/foo.sh`.

- Pros: Single copy per script. Clear ownership.
- Cons: Install order dependency (spex must install first). Extension removal cascades silently. `specify extension add` doesn't validate cross-extension references. Fragile in practice.

### C: Shared Scripts Directory

Keep scripts in a separate `spex/scripts/shared/` dir installed to `.specify/scripts/` alongside extensions.

- Pros: Clean separation. No duplication.
- Cons: Needs spec-kit support for installing shared scripts (doesn't exist). Adds a concept outside the extension model.

## Decision

**Approach A: Extension-local scripts with build-time sync.**

Scripts are ephemeral artifacts regenerated on every `specify init`. Users never edit them. The duplication cost is minimal (small shell scripts), and the benefit is significant: each extension is fully self-contained and harness-agnostic. The Makefile makes the single-source-of-truth relationship explicit and enforceable.

## Script Inventory

Current scripts in `spex/scripts/` and which extensions need them:

| Script | spex | spex-gates | spex-collab | spex-deep-review | spex-detach |
|--------|------|------------|-------------|------------------|-------------|
| spex-flow-state.sh | x | x | x | x | |
| spex-ship-state.sh | x | | | | |
| spex-finish-context.sh | x | | | | |
| spex-worktree-cwd.sh | x | | | | |
| spex-closeout-gate.sh | | x | | | |
| spex-triage-state.sh | | | x | | |
| sanitize-gh-json.py | | | x | | |
| bash/spex-detach.sh | x | | | | x |

## Implementation Plan

### Step 1: Build-time script distribution

- Add a `scripts/` directory to each extension's source dir under `spex/extensions/<id>/scripts/`
- Create a `make sync-scripts` target that copies from `spex/scripts/` into each extension's `scripts/` dir based on the inventory above
- Add `sync-scripts` as a dependency of the release target
- Add a CI check that verifies extension scripts match their source in `spex/scripts/`

### Step 2: Update command templates

Replace all `$PLUGIN_ROOT/scripts/<script>` references with `.specify/extensions/<own-extension-id>/scripts/<script>`. For example:

**Before:**
```bash
FLOW_STATE="$PLUGIN_ROOT/scripts/spex-flow-state.sh"
```

**After:**
```bash
FLOW_STATE=".specify/extensions/spex-gates/scripts/spex-flow-state.sh"
```

Remove the "Step 0: Resolve Plugin Root" preamble from all commands.

### Step 3: Remove $PLUGIN_ROOT infrastructure

- Remove the `<plugin-root>` tag injection from the context hook (`spex/scripts/hooks/context-hook.py`)
- Remove the "extract plugin root from system reminder" instructions from commands
- Keep `spex/scripts/` as the canonical source (used by build-time sync and by `spex-init.sh` for non-extension scripts like hooks)

### Step 4: Simplify spex-init.sh

With self-contained extensions, `spex-init.sh` can shrink. The extension installation section becomes a simple loop of `specify extension add` calls. Per-harness init logic moves to harness-specific adapter setup, not script copying.

## Relative Path Risk Assessment

Relative paths (`.specify/extensions/<id>/scripts/foo.sh`) work when the agent's CWD is the project root. This is the common case for all major harnesses. Known edge cases:

- **Monorepo member projects**: CWD might be the git root, not the spec-kit project root. Mitigated by upstream proposals ([spec-kit#3308](https://github.com/github/spec-kit/issues/3308)) for runtime project root resolution.
- **Worktrees**: Our worktree management already rsyncs `.specify/` to the worktree, so relative paths work from the worktree root.
- **Subagents**: Most harnesses inherit CWD from the parent agent.

For the foreseeable future, relative paths work. If edge cases surface, the upstream `$(specify project root)` proposal or `post_process_command_content()` hook ([spec-kit PR#3311](https://github.com/github/spec-kit/pull/3311)) provide a path forward.

## Open Questions

- Should `spex-init.sh` (hooks, adapters, non-extension scripts) also be refactored into the extension model, or does it stay as a separate init layer?
- Should the build-time sync be a Makefile target only, or also a git pre-commit hook to prevent commits with stale copies?
