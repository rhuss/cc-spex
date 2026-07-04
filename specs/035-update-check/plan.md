# Implementation Plan: Update Check on Init

**Branch**: `feat/001-update-check` | **Date**: 2026-07-04 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/035-update-check/spec.md`

## Summary

Add a VERSION file as the single source of truth for the project version, an update check in spex-init.sh that queries the GitHub releases API on every init run and warns users when they're behind, and an automated `make release` target that syncs VERSION to marketplace.json, tags, pushes, and bumps to the next dev version.

## Technical Context

**Language/Version**: Bash (POSIX-compatible), GNU Make
**Primary Dependencies**: `curl`, `jq` (both already project dependencies)
**Storage**: VERSION file (single-line text), `.claude-plugin/marketplace.json` (JSON)
**Testing**: Manual verification via init script execution, `make validate`
**Target Platform**: macOS, Linux (cross-platform shell)
**Project Type**: CLI plugin (Claude Code plugin)
**Performance Goals**: Update check completes within 3 seconds (API timeout bound)
**Constraints**: Silent failure on network errors, no authentication required, 60 req/hr rate limit
**Scale/Scope**: Single init script modification, single Makefile target rewrite

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-Guided Development | PASS | Feature follows full SDD workflow |
| II. Extension Architecture | PASS | Changes are to core plugin scripts, not extensions |
| III. Extension Composability | PASS | No extension interaction affected |
| VII. State as Scripts | PASS | Version check is inline in spex-init.sh (a script), not in markdown |
| No compiled artifacts | PASS | Only Bash and Make changes |
| Documentation maintenance | PASS | README.md and help.md will be updated |
| Release process | NEEDS UPDATE | Constitution references old release process (bump marketplace.json manually). Will need amendment after this feature lands. |

## Project Structure

### Documentation (this feature)

```text
specs/035-update-check/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 research
├── data-model.md        # Phase 1 data model
└── checklists/
    └── requirements.md  # Spec quality checklist
```

### Source Code (repository root)

```text
VERSION                              # NEW: single-line version file (source of truth)
Makefile                             # MODIFY: rewrite release target
.claude-plugin/marketplace.json      # MODIFY: version derived from VERSION during release
spex/scripts/spex-init.sh           # MODIFY: add check_update() function
```

**Structure Decision**: No new directories or structural changes. Three file modifications plus one new file at the repo root.

## Complexity Tracking

No constitution violations. No complexity justification needed.

## Implementation Approach

### Phase 1: VERSION File and Makefile (User Stories 2 & 3)

1. Create `VERSION` file at repo root with current version `5.9.1-dev` (since 5.9.0 is already released)
2. Rewrite `make release` target to:
   - Read VERSION, validate it's not a `-dev` version
   - Update marketplace.json version field using `jq`
   - Commit the marketplace.json change
   - Create git tag `v$VERSION`
   - Push commit and tag
   - Bump VERSION to `{patch+1}-dev`
   - Commit the VERSION bump
   - Push the post-release commit
3. Update `make validate` to verify VERSION matches marketplace.json (for release versions)

### Phase 2: Update Check in spex-init.sh (User Story 1)

1. Add `check_update()` function to spex-init.sh:
   - Resolve VERSION file path relative to script location (`$script_dir/../../VERSION`)
   - Read local version from VERSION
   - `curl` the GitHub releases API with `--connect-timeout 2 --max-time 3`
   - Extract latest tag name and release body from JSON response using `jq`
   - Strip `v` prefix from tag name for comparison
   - Compare versions using semver logic:
     - Strip `-dev` suffix from local version for comparison base
     - If local (without `-dev`) >= latest: silent (equal or ahead)
     - If local has `-dev` suffix: silent (development build)
     - If local < latest: print warning
   - If release body contains `BREAKING:` lines, extract and display them
   - All failures (missing VERSION, curl error, jq parse error, etc.) are silent
2. Call `check_update` from the appropriate init paths (normal init and `--refresh`)
3. Do NOT call `check_update` from `--clear` or `--update` paths

### Semver Comparison Logic

For POSIX shell, the update check uses a simplified comparison:
- If local version has a `-dev` suffix, skip the check entirely (dev builds never show update warnings per FR-008)
- Otherwise, split on `.` to get major, minor, patch
- Compare major first, then minor, then patch numerically
- If local >= latest: silent. If local < latest: warn

### Error Handling Strategy

Every step in the update check is wrapped in silent failure:
- `curl` with timeout flags and `2>/dev/null`
- `jq` with `// empty` fallbacks
- VERSION read with `cat ... 2>/dev/null`
- The entire check is non-blocking: init continues regardless of outcome
