# Brainstorm: Extension-Owned Scripts (Eliminate Redundant Canonical Copies)

**Date:** 2026-07-15
**Status:** active
**Related:** Brainstorm #33 (extension-local-scripts), Spec 036, Brainstorm #37 (spex-detach-hardening)

## Problem Framing

The `make sync-scripts` pipeline copies canonical scripts from `spex/scripts/` to
extension `scripts/` directories. This made sense when scripts were shared across
extensions. In practice, most scripts are extension-specific (used by exactly one
extension), and the canonical copy creates drift risk without benefit.

Evidence from PR #38 (detach hardening): `spex-detach.py` was modified in the
`spex-detach` extension but the canonical copy in `spex/scripts/` and a stale
copy in `spex/extensions/spex/scripts/` diverged, missing the new verify command,
archive move semantics, and hardened failure cleanup.

Current state of sharing:
- `spex-flow-state.sh`: genuinely shared (4 extensions)
- All other scripts: used by exactly 0 or 1 extension

Additionally, `deep-review.run.md` has a `{harness:codex-review-tool}` marker
placed inside an active bash fenced block. When adapters substitute descriptive
text for the marker, it produces invalid bash syntax.

## Approaches Considered

### A: Keep all scripts canonical (status quo)

Fix the immediate issue by adding `spex-detach.py` to `SCRIPTS_spex_detach`
and removing stale copies.

- Pros: Minimal change, preserves existing pattern
- Cons: Keeps the sync overhead for scripts that don't benefit from it.
  Every extension-specific script change requires updating two locations.

### B: Extension-owned scripts (Chosen)

Only genuinely shared scripts remain canonical in `spex/scripts/`. Extension-specific
scripts live only in their owning extension's `scripts/` directory. The extension
IS the source of truth. `make sync-scripts` only handles the shared set.

- Pros: Eliminates drift risk for extension-specific scripts. Simpler mental
  model: if a script belongs to an extension, it lives there. Fewer files in
  `spex/scripts/`.
- Cons: Larger refactoring (moving ~10 scripts). Need to update Makefile
  SCRIPTS variables and sync-scripts-check.

### C: Eliminate sync entirely

Remove `spex/scripts/` as a concept. All scripts live in their owning extension.
For shared scripts, pick one extension as the owner and have others reference it
via symlinks or copy at install time.

- Pros: Simplest model, no sync at all
- Cons: Shared scripts like `spex-flow-state.sh` genuinely need to be in
  multiple extensions. Symlinks don't survive `specify extension add`.

## Decision

**Approach B: Extension-owned scripts.** Move extension-specific scripts out of
`spex/scripts/` to their owning extension. Keep only genuinely shared scripts
(`spex-flow-state.sh`) canonical. Fix the deep-review harness marker as a
one-off.

## Key Requirements

1. **Move extension-specific scripts** from `spex/scripts/` to their owning
   extension's `scripts/` directory. Delete the canonical copies.

2. **Update Makefile**: Remove moved scripts from `SCRIPTS_<ext>` variables.
   For extension-owned scripts, sync is not needed (the extension dir IS the
   source). Update `sync-scripts-check` to only validate the shared set.

3. **Keep shared scripts canonical**: `spex-flow-state.sh` stays in
   `spex/scripts/` and gets synced to all 4 extensions that use it.

4. **Remove stale copies**: Delete `spex-detach.py` and `spex-detach.sh` from
   `spex/extensions/spex/scripts/` (leftover from before detach was its own
   extension).

5. **Fix harness marker**: Split the bash block in `deep-review.run.md` around
   the `{harness:codex-review-tool}` marker so adapter substitution produces
   valid syntax.

6. **Scripts ownership map**:
   - `spex-flow-state.sh` -> stays canonical (shared by spex, spex-gates, spex-collab, spex-deep-review)
   - `spex-ship-state.sh`, `spex-ship-state.py`, `spex-ship-statusline.sh`, `spex-finish-context.sh`, `spex-worktree-cwd.sh` -> owned by `spex`
   - `spex-detach.py`, `spex-detach.sh` -> owned by `spex-detach`
   - `spex-triage-state.sh`, `sanitize-gh-json.py` -> owned by `spex-collab`
   - `spex-closeout-gate.sh` -> owned by `spex-gates`
   - `spex-adapt-commands.sh`, `spex-init.sh`, `check-upstream-changes.sh` -> remain in `spex/scripts/` (build/init utilities, not extension scripts)

## Open Questions

- Should `make sync-scripts-check` in the release target also verify that
  extension-owned scripts have no stale copies in `spex/scripts/`? Or is
  the absence of the script from SCRIPTS variables sufficient?
- Should the constitution's "Extension-local scripts" constraint be updated
  to explicitly distinguish shared vs extension-owned scripts?
