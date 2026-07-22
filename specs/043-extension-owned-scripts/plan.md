# Implementation Plan: Extension-Owned Scripts

**Branch**: `043-extension-owned-scripts` | **Date**: 2026-07-15 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/043-extension-owned-scripts/spec.md`

## Summary

Remove `spex-detach.py` and `spex-detach.sh` from the canonical `spex/scripts/` directory and from the stale copies in `spex/extensions/spex/scripts/`. Update Makefile SCRIPTS variables so `make sync-scripts` only handles shared scripts. Fix the deep-review harness marker placement. Validate with `make release`.

## Technical Context

**Language/Version**: Bash (POSIX-compatible), Python 3, Markdown, Makefile
**Primary Dependencies**: `make`, `specify` CLI
**Storage**: N/A
**Testing**: `make release` (schema validation + integration test + sync-scripts-check)
**Target Platform**: macOS, Linux
**Project Type**: CLI plugin (spec-kit extension bundle)
**Performance Goals**: N/A
**Constraints**: No compiled artifacts
**Scale/Scope**: 4 files deleted, 2 files modified, ~10 lines changed in Makefile

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-Guided Development | PASS | Following full SDD workflow |
| II. Extension Architecture | PASS | Strengthens extension ownership of scripts |
| III. Extension Composability | PASS | Extensions become more independent |
| IV. Quality Gates | PASS | Ship pipeline runs full gate chain |
| V. Naming Discipline | PASS | No naming changes |
| VI. Skill Autonomy | PASS | No skill changes |
| VII. State as Scripts | PASS | Scripts remain in scripts, just relocated |

No violations.

## Project Structure

### Source Code Changes

```text
Makefile                                           # MODIFY: update SCRIPTS variables
spex/scripts/spex-detach.py                        # DELETE: no longer canonical
spex/scripts/spex-detach.sh                        # DELETE: no longer canonical
spex/extensions/spex/scripts/spex-detach.py        # DELETE: stale copy
spex/extensions/spex/scripts/spex-detach.sh        # DELETE: stale copy
spex/extensions/spex-deep-review/commands/
  speckit.spex-deep-review.run.md                  # MODIFY: fix harness marker placement
```

**Structure Decision**: Pure deletion and variable cleanup. No new files.

## Implementation Approach

### Phase 1: Remove stale and canonical detach scripts

**Task 1**: Delete stale detach scripts from spex extension (FR-005)
- Remove `spex/extensions/spex/scripts/spex-detach.py`
- Remove `spex/extensions/spex/scripts/spex-detach.sh`

**Task 2**: Delete canonical detach scripts from spex/scripts/ (FR-001)
- Remove `spex/scripts/spex-detach.py`
- Remove `spex/scripts/spex-detach.sh`

**Task 3**: Update Makefile SCRIPTS variables and EXTENSIONS list (FR-002, FR-003, FR-004, FR-006, FR-007)
- Remove `spex-detach.sh` from `SCRIPTS_spex`
- Remove `spex-detach` from the `EXTENSIONS` list (it has no canonical scripts left)
- Remove the `SCRIPTS_spex_detach` variable (no longer needed)
- Remove the `_print-scripts-spex-detach` helper target (no longer needed)

Note: Simply clearing `SCRIPTS_spex_detach` to empty would break `make sync-scripts` and `make sync-scripts-check`, which both guard against empty script lists with `exit 1`. Removing `spex-detach` from `EXTENSIONS` entirely is the correct approach, as extension-owned scripts should not be managed by the sync mechanism at all.

### Phase 2: Fix harness marker

**Task 4**: Fix harness marker in deep-review.run.md (FR-008)
- Split the bash block around the first `{harness:codex-review-tool}` marker
- Close the bash block before the marker, open a new one after

### Phase 3: Validate

**Task 5**: Validate build (FR-010)
- Run `make sync-scripts` to verify no errors
- Run `make sync-scripts-check` to verify clean
