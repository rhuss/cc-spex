# Research: Extension-Owned Scripts

## R1: Which scripts to remove from spex/scripts/

**Decision**: Remove only `spex-detach.py` and `spex-detach.sh` from `spex/scripts/`. All other extension-specific scripts remain canonical for now (deferred to follow-up).

**Rationale**: The spec scopes this feature to the detach scripts only. Other single-extension scripts (spex-ship-state.sh, etc.) continue to use the canonical pattern until a follow-up feature migrates them.

## R2: SCRIPTS variable changes

**Decision**: Remove `spex-detach.sh` from `SCRIPTS_spex`. Remove `spex-detach.sh` from `SCRIPTS_spex_detach` (since it will no longer be synced from canonical). Leave all other SCRIPTS variables unchanged.

**Rationale**: `SCRIPTS_spex_detach` currently lists `spex-detach.sh` which gets synced from `spex/scripts/`. After this change, `spex-detach.sh` lives only in `spex/extensions/spex-detach/scripts/` and is not synced.

## R3: Harness marker fix approach

**Decision**: Split the bash block in `speckit.spex-deep-review.run.md` around the `{harness:codex-review-tool}` marker. Close the bash block before the marker, place marker outside, open a new bash block after.

**Rationale**: This matches the pattern already used at line 258 of the same file where the second harness marker instance is correctly placed outside fenced blocks.
