# Feature Specification: Extension-Owned Scripts

**Feature Branch**: `043-extension-owned-scripts`
**Created**: 2026-07-15
**Status**: Draft
**Input**: Brainstorm #39 (extension-owned-scripts), Brainstorm #33 (extension-local-scripts)

## User Scenarios & Testing

### User Story 1 - Extension-specific scripts live only in their extension (Priority: P1)

A developer modifying an extension-specific script (e.g., `spex-detach.py`) edits only the file in the extension's `scripts/` directory. There is no canonical copy in `spex/scripts/` to keep in sync. `make sync-scripts` does not touch extension-specific scripts.

**Why this priority**: This eliminates the drift problem that caused stale copies to diverge from the canonical source, as seen with `spex-detach.py` in PR #38.

**Independent Test**: Modify `spex/extensions/spex-detach/scripts/spex-detach.py`, run `make sync-scripts`, verify the file is untouched (not overwritten by a canonical copy). Run `make sync-scripts-check`, verify it passes without requiring a canonical copy.

**Acceptance Scenarios**:

1. **Given** extension-specific scripts have been moved from `spex/scripts/` to their owning extension, **When** `make sync-scripts` runs, **Then** only shared scripts (`spex-flow-state.sh`) are copied to extensions. Extension-specific scripts are not touched.
2. **Given** an extension-specific script is modified in its extension directory, **When** `make sync-scripts-check` runs during `make release`, **Then** the check passes without requiring a matching canonical copy.
3. **Given** `spex/scripts/` no longer contains extension-specific scripts, **When** a developer lists scripts in `spex/scripts/`, **Then** only shared scripts and build/init utilities remain.

---

### User Story 2 - Stale detach scripts removed from spex extension (Priority: P1)

The stale `spex-detach.py` and `spex-detach.sh` files in `spex/extensions/spex/scripts/` are removed. The `spex` extension no longer bundles detach scripts since no command in the `spex` extension references them (the brainstorm skill was fixed to reference `spex-detach/scripts/` in PR #38).

**Why this priority**: These stale files are actively misleading. A developer might modify the wrong copy and wonder why their changes don't take effect.

**Independent Test**: Verify `spex/extensions/spex/scripts/` does not contain `spex-detach.py` or `spex-detach.sh`. Verify `SCRIPTS_spex` in the Makefile does not include `spex-detach.sh`.

**Acceptance Scenarios**:

1. **Given** the stale files are removed, **When** `ls spex/extensions/spex/scripts/`, **Then** `spex-detach.py` and `spex-detach.sh` are not present.
2. **Given** `SCRIPTS_spex` is updated, **When** `make sync-scripts` runs, **Then** `spex-detach.sh` is not copied to the spex extension.

---

### User Story 3 - Shared scripts remain canonical and synced (Priority: P1)

`spex-flow-state.sh` (used by 4 extensions: spex, spex-gates, spex-collab, spex-deep-review) continues to live in `spex/scripts/` as the canonical source. `make sync-scripts` copies it to all 4 extensions. `make sync-scripts-check` verifies all copies match.

**Why this priority**: Shared scripts must remain in sync. The canonical pattern works well for genuinely shared scripts.

**Independent Test**: Modify `spex/scripts/spex-flow-state.sh`, run `make sync-scripts`, verify all 4 extension copies are updated. Run `make sync-scripts-check`, verify it detects any drift.

**Acceptance Scenarios**:

1. **Given** `spex-flow-state.sh` is modified in `spex/scripts/`, **When** `make sync-scripts` runs, **Then** the copies in spex, spex-gates, spex-collab, and spex-deep-review are all updated to match.

---

### User Story 4 - Deep-review harness marker fix (Priority: P2)

The `{harness:codex-review-tool}` marker in `deep-review.run.md` is moved outside the bash fenced block to prevent adapter substitution from producing invalid bash syntax.

**Why this priority**: A correctness bug. When adapters substitute descriptive text for the marker, the bash block becomes syntactically invalid, causing agent execution errors.

**Independent Test**: Read `speckit.spex-deep-review.run.md` and verify the `{harness:codex-review-tool}` and `{/harness:codex-review-tool}` markers are outside any bash fenced code block.

**Acceptance Scenarios**:

1. **Given** the harness markers are moved outside the bash block, **When** the adapter substitutes descriptive text for the marker, **Then** the surrounding bash blocks remain syntactically valid.

---

### Edge Cases

- What if a script is used by exactly 2 extensions in the future? It should be promoted to canonical in `spex/scripts/` and added to both SCRIPTS variables. The threshold for canonical is 2+ extensions.
- What if `make sync-scripts-check` runs and finds a script in `spex/scripts/` that is not in any SCRIPTS variable? It should warn about orphaned canonical scripts.
- What if a developer accidentally creates a script in both the extension and `spex/scripts/`? `make sync-scripts` would overwrite the extension copy with the canonical one, which is the correct behavior for shared scripts.

## Requirements

### Functional Requirements

- **FR-001**: Extension-specific scripts that are only used by one extension SHOULD eventually live only in that extension's `scripts/` directory. This feature migrates `spex-detach.*` as the first instance of this pattern.
- **FR-002**: The `SCRIPTS_<ext>` Makefile variables MUST be updated to only list scripts that come from the canonical `spex/scripts/` directory (i.e., shared scripts).
- **FR-003**: `make sync-scripts` MUST only copy shared scripts (currently `spex-flow-state.sh`) from `spex/scripts/` to extension directories. It MUST NOT touch extension-specific scripts.
- **FR-004**: `make sync-scripts-check` MUST only validate shared scripts against their canonical source. It MUST NOT require canonical copies for extension-owned scripts.
- **FR-005**: Stale `spex-detach.py` and `spex-detach.sh` MUST be removed from `spex/extensions/spex/scripts/`.
- **FR-006**: `spex-detach.sh` MUST be removed from `SCRIPTS_spex`.
- **FR-007**: `spex-detach.py` MUST NOT be added to any SCRIPTS variable (it is extension-owned, not synced).
- **FR-008**: The first `{harness:codex-review-tool}` marker block in `speckit.spex-deep-review.run.md` (tool detection, around line 111) MUST be moved outside its enclosing fenced bash block. The second instance (Codex invocation, around line 258) is already correctly placed outside fenced blocks.
- **FR-009**: Build/init utilities (`spex-adapt-commands.sh`, `spex-init.sh`, `check-upstream-changes.sh`) MUST remain in `spex/scripts/` (they are not extension scripts).
- **FR-010**: `make release` MUST continue to pass after all changes (schema validation + integration test + sync-scripts-check).

### Key Entities

- **spex/scripts/**: Canonical location for shared scripts and build utilities. After this change, contains only `spex-flow-state.sh` (shared) plus build/init utilities.
- **SCRIPTS_<ext>**: Makefile variables listing which canonical scripts to sync to each extension. After this change, only list shared scripts.
- **make sync-scripts**: Copies canonical scripts to extension directories. After this change, only handles the shared set.
- **make sync-scripts-check**: Validates extension scripts match canonical sources. After this change, only checks the shared set.

## Success Criteria

### Measurable Outcomes

- **SC-001**: `spex-detach.py` and `spex-detach.sh` have been removed from `spex/scripts/`. The remaining extension-specific scripts (spex-ship-state.sh, spex-ship-statusline.sh, etc.) continue to live in `spex/scripts/` as canonical copies for now (migration deferred to a follow-up feature).
- **SC-002**: `make sync-scripts && make sync-scripts-check` passes cleanly after the refactoring.
- **SC-003**: `make release` passes (schema validation + integration test + sync-scripts-check).
- **SC-004**: No extension directory contains a script that also exists in another extension directory (except `spex-flow-state.sh` which is shared).
- **SC-005**: The `{harness:codex-review-tool}` marker in deep-review.run.md is outside all bash fenced blocks.

## Smoke Test

1. Run `make sync-scripts` and verify only `spex-flow-state.sh` is synced to extensions. Verify no extension-specific scripts are overwritten or created.
2. Modify `spex/scripts/spex-flow-state.sh` (add a comment), run `make sync-scripts`, verify all 4 extension copies updated. Run `make sync-scripts-check`, verify pass.
3. Run `make release` (or the validation subset) to confirm nothing is broken.

## Clarifications

### Session 2026-07-15

No critical ambiguities. All decisions made during brainstorming:
- Extension-specific scripts owned by their extension, not synced
- Only `spex-flow-state.sh` stays canonical (4 extensions)
- Build/init utilities stay in `spex/scripts/` (not extension scripts)
- Harness marker fix is a one-off, no broader pattern needed

## Out of Scope

- **Migrating other single-extension scripts**: Scripts like `spex-ship-state.sh`, `spex-ship-statusline.sh`, `spex-finish-context.sh`, `spex-worktree-cwd.sh`, `spex-closeout-gate.sh`, `spex-triage-state.sh`, and `sanitize-gh-json.py` are each used by only one extension and could follow the same extension-owned pattern. They remain canonical in `spex/scripts/` for now. A follow-up feature can migrate them incrementally.
- **Changes to `spex-ship-state.py`**: The spec acknowledges this file is extension-owned (used only by spex), but its migration from `spex/scripts/` is deferred to avoid expanding scope.
- **Makefile structural refactoring**: The `sync-scripts` / `sync-scripts-check` targets keep their current structure. Only the SCRIPTS_ variable contents change.

## Assumptions

- The `specify extension add --dev` command installs the extension's `scripts/` directory alongside `commands/`. This was verified in spec 036 (extension-local-scripts).
- No other extension or command references `spex-detach.sh` from the `spex` extension's scripts directory (confirmed by the brainstorm path fix in PR #38).
- The `spex-ship-state.py` file in `spex/extensions/spex/scripts/` is an extension-owned script (used only by the `spex` extension), not a shared script.
