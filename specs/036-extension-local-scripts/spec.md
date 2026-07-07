# Feature Specification: Extension-Local Scripts

**Feature Branch**: `036-extension-local-scripts`  
**Created**: 2026-07-06  
**Status**: Draft  
**Input**: Replace $PLUGIN_ROOT with extension-local scripts installed by `specify extension add`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Extension Commands Find Their Scripts Without Harness-Specific Infrastructure (Priority: P1)

A developer (or AI agent) runs a spex command (e.g., `/speckit-spex-ship`) on any agent harness. The command references helper scripts (flow-state, ship-state, etc.) and finds them at a deterministic path relative to the project root, without relying on `$PLUGIN_ROOT` or any Claude Code-specific system prompt injection.

**Why this priority**: This is the core value proposition. Without this, every command depends on Claude Code's `<plugin-root>` tag, blocking harness-agnostic operation entirely.

**Independent Test**: Run any spex command that references a helper script after a fresh `specify init`. Verify the script is found and executes successfully without `$PLUGIN_ROOT` being set.

**Acceptance Scenarios**:

1. **Given** a project with spex extensions installed via `specify extension add`, **When** a command references `.specify/extensions/<ext-id>/scripts/<script>`, **Then** the script exists at that path and is executable.
2. **Given** a command previously using `$PLUGIN_ROOT/scripts/spex-flow-state.sh`, **When** updated to use `.specify/extensions/spex/scripts/spex-flow-state.sh`, **Then** the command executes identically to before.
3. **Given** a fresh `specify init` run, **When** extensions are installed, **Then** each extension's `scripts/` directory contains exactly the scripts it needs (per the inventory table).

---

### User Story 2 - Build-Time Script Sync Keeps Extension Scripts Current (Priority: P2)

A cc-spex maintainer modifies a script in the canonical source (`spex/scripts/`). Running `make sync-scripts` copies the updated script to every extension that needs it. The release process catches forgotten syncs.

**Why this priority**: Without build-time sync, canonical scripts and extension copies drift. This is the mechanism that makes the "single source of truth" promise real.

**Independent Test**: Modify a script in `spex/scripts/`, run `make sync-scripts`, and verify all consuming extensions have the updated copy.

**Acceptance Scenarios**:

1. **Given** a modified `spex-flow-state.sh` in `spex/scripts/`, **When** `make sync-scripts` runs, **Then** `spex/extensions/spex/scripts/spex-flow-state.sh`, `spex/extensions/spex-gates/scripts/spex-flow-state.sh`, `spex/extensions/spex-collab/scripts/spex-flow-state.sh`, and `spex/extensions/spex-deep-review/scripts/spex-flow-state.sh` all match the canonical copy.
2. **Given** a new script added to `spex/scripts/` and the inventory mapping, **When** `make sync-scripts` runs, **Then** the new script appears in the correct extensions' `scripts/` directories.
3. **Given** `sync-scripts` was not run after a script change, **When** the release target runs, **Then** it fails with a clear message identifying which scripts are out of sync.

---

### User Story 3 - CI Validates Script Sync Freshness (Priority: P2)

A contributor opens a PR that modifies a script in `spex/scripts/` but forgets to run `make sync-scripts`. CI detects the stale copies and fails the check with a clear remediation message.

**Why this priority**: Same priority as the sync itself because without CI enforcement, the sync discipline erodes over time.

**Independent Test**: Modify a canonical script without syncing, push, and verify CI fails with an actionable error.

**Acceptance Scenarios**:

1. **Given** a PR where `spex/scripts/spex-ship-state.sh` was modified, **When** CI runs the sync check, **Then** it compares canonical scripts against extension copies and reports any mismatches.
2. **Given** all extension scripts match their canonical sources, **When** CI runs the sync check, **Then** the check passes silently.
3. **Given** a mismatch is detected, **When** CI reports the failure, **Then** the message includes: which scripts are stale, which extensions are affected, and the command to fix it (`make sync-scripts`).

---

### User Story 4 - All $PLUGIN_ROOT References Are Eliminated (Priority: P1)

After migration, no command template, skill, or hook references `$PLUGIN_ROOT` or the `<plugin-root>` system prompt tag. The context hook no longer injects the `<plugin-root>` tag.

**Why this priority**: Residual `$PLUGIN_ROOT` references would be broken paths at runtime. This must be complete for the feature to work.

**Independent Test**: Search the entire codebase for `$PLUGIN_ROOT`, `PLUGIN_ROOT`, and `<plugin-root>`. Zero results.

**Acceptance Scenarios**:

1. **Given** the migration is complete, **When** searching all command templates for `PLUGIN_ROOT`, **Then** zero matches are found.
2. **Given** the context hook (`context-hook.py`), **When** inspecting its output, **Then** no `<plugin-root>` tag is injected into the system prompt.
3. **Given** a command that previously had a "Step 0: Resolve Plugin Root" section, **When** reading the migrated command, **Then** that section is removed and scripts are referenced via `.specify/extensions/<ext-id>/scripts/`.

---

### User Story 5 - Simplified spex-init.sh (Priority: P3)

With self-contained extensions, `spex-init.sh` no longer needs to copy scripts manually. The extension installation section becomes a loop of `specify extension add` calls.

**Why this priority**: Quality-of-life improvement. The init script works without this simplification, just with more complexity.

**Independent Test**: Run `spex-init.sh` on a clean project and verify all extensions are installed with their scripts present.

**Acceptance Scenarios**:

1. **Given** a clean project without `.specify/`, **When** `spex-init.sh` runs, **Then** all extensions are installed via `specify extension add` and each has its `scripts/` directory populated.
2. **Given** the current `spex-init.sh` with manual script-copy logic, **When** migrated, **Then** the script-copy section is replaced by extension add calls and the script is shorter.

---

### Edge Cases

- What happens when a script is needed by only one extension? It should still go through the sync pipeline for consistency rather than being treated specially.
- What happens when `specify extension add` is run for an extension that has no scripts? The extension installs normally; the absence of a `scripts/` directory is not an error.
- What happens in a git worktree? The worktree management already rsyncs `.specify/` to the worktree, so scripts at `.specify/extensions/<ext-id>/scripts/` are available.
- What happens if a user manually edits a script in `.specify/extensions/`? Their edits are overwritten on the next `specify init` or `specify extension add`. This is by design since scripts are ephemeral artifacts.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Each extension's source directory (`spex/extensions/<id>/`) MUST contain a `scripts/` subdirectory with the scripts it needs at runtime.
- **FR-002**: The build system MUST provide a `make sync-scripts` target that copies scripts from `spex/scripts/` to consuming extensions based on a defined inventory mapping.
- **FR-003**: The `sync-scripts` target MUST be a dependency of the release target so stale copies cannot be shipped.
- **FR-004**: CI MUST include a check that compares extension scripts against their canonical sources and fails on any mismatch.
- **FR-005**: All command templates and skill files (`.claude/skills/*/SKILL.md`) MUST reference scripts via `.specify/extensions/<own-extension-id>/scripts/<script>` instead of `$PLUGIN_ROOT/scripts/<script>`.
- **FR-006**: The context hook (`context-hook.py`) MUST stop injecting the `<plugin-root>` tag into the system prompt.
- **FR-007**: All "Step 0: Resolve Plugin Root" preambles MUST be removed from command templates and skill files.
- **FR-008**: `spex-init.sh` MUST install extensions via `specify extension add` calls, which automatically installs scripts alongside commands.
- **FR-009**: The script inventory mapping MUST be defined in a single location (Makefile or config) to serve as the authoritative record of which scripts belong to which extensions.
- **FR-010**: The constitution (`.specify/memory/constitution.md`) MUST be updated to remove the "Plugin root detection" constraint that mandates `$PLUGIN_ROOT` extraction and "Step 0: Resolve Plugin Root" sections, replacing it with the extension-local script path convention.

### Key Entities

- **Canonical Script**: A shell or Python script in `spex/scripts/` that is the single source of truth for its content.
- **Extension Script Copy**: A copy of a canonical script placed in `spex/extensions/<id>/scripts/` by the sync process, installed to `.specify/extensions/<id>/scripts/` by `specify extension add`.
- **Script Inventory**: The mapping that defines which canonical scripts are needed by which extensions. Current inventory:

| Extension | Scripts |
|-----------|---------|
| spex | `spex-flow-state.sh`, `spex-ship-state.sh`, `spex-finish-context.sh`, `spex-worktree-cwd.sh`, `spex-detach.sh` |
| spex-gates | `spex-flow-state.sh`, `spex-closeout-gate.sh` |
| spex-collab | `spex-flow-state.sh`, `spex-triage-state.sh`, `sanitize-gh-json.py` |
| spex-deep-review | `spex-flow-state.sh` |
| spex-detach | `spex-detach.sh` |

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Zero occurrences of `PLUGIN_ROOT` or `<plugin-root>` in any command template, skill, or hook file after migration.
- **SC-002**: All existing spex commands that reference helper scripts continue to function identically after migrating to extension-local paths.
- **SC-003**: `make sync-scripts` completes in under 5 seconds and correctly distributes all scripts per the inventory.
- **SC-004**: CI script-sync check catches 100% of stale extension script copies (no false negatives).
- **SC-005**: A fresh `specify init` on a clean project results in all extensions having their required scripts installed and executable.

## Clarifications

### Session 2026-07-06

- Q: Should spex-init.sh be refactored into the extension model or stay as a separate init layer? → A: Stay as separate init layer. FR-008 defines its role: it calls `specify extension add` for each extension. Init handles harness-specific setup (hooks, adapters) that doesn't fit the extension model.
- Q: Should sync enforcement use a Makefile target only, or also a git pre-commit hook? → A: Makefile target + CI check only (FR-002, FR-004). A pre-commit hook adds developer friction without improving safety over CI, and not all contributors would have hooks installed.

## Out of Scope

- Removing `spex/scripts/` as a directory. It remains as the canonical source that feeds the sync pipeline.
- Migrating scripts in `spex/scripts/hooks/` (e.g., `context-hook.py`). Hooks run at the harness level and are not extension-local. The context hook is *modified* (FR-006) but not *relocated*.
- Migrating scripts in `spex/scripts/adapters/`. Adapter scripts are harness-specific infrastructure, not extension runtime dependencies.
- Changing how `spex-init.sh` itself is located or invoked. Only its internal script-copy logic changes (FR-008).
- Extensions that do not reference any scripts (`spex-worktrees`, `spex-teams`) get no `scripts/` directory.

## Assumptions

- `spex/scripts/` remains the canonical source for all shared scripts. It is not removed; it feeds the sync process.
- Scripts are small shell/Python files (under 500 lines each). Duplication adds negligible repository size.
- `specify extension add` already copies all files from an extension's source directory (including `scripts/`) to `.specify/extensions/<id>/`. No upstream spec-kit changes are needed.
- Commands always run with CWD set to the project root, making `.specify/extensions/<id>/scripts/` a reliable relative path.
- The `spex-detach.sh` script in `bash/` subdirectory follows the same pattern: it gets copied to extensions that need it under `scripts/bash/`.
