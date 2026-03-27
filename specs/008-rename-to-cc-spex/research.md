# Research: Rename Plugin to cc-spex

**Date**: 2026-03-27
**Feature**: 008-rename-to-cc-spex

## Rename Pattern Inventory

### Pattern Categories

28 distinct pattern types requiring updates across 60+ file locations.

| Category | Pattern | Count | Example |
|----------|---------|-------|---------|
| Slash commands | `/sdd:*` | 10+ locations | `/sdd:init`, `/sdd:verify` |
| Skill references | `{Skill: sdd:*}` | 9 distinct skills | `{Skill: sdd:teams-orchestrate}` |
| Marker files | `.claude-sdd-*` | 2 patterns | `.claude-sdd-skill-pending-*` |
| Config files | `sdd-traits.json` | 1 file, many refs | `.specify/sdd-traits.json` |
| Shell scripts | `sdd-*.sh` | 2 files | `sdd-init.sh`, `sdd-traits.sh` |
| XML tags | `<sdd-*>` | 6 tag names | `<sdd-context>`, `<sdd-error>` |
| Sentinel markers | `<!-- SDD-TRAIT:* -->` | Multiple overlays | `<!-- SDD-TRAIT:teams -->` |
| Plugin names | `"sdd"` in JSON | 3 files | plugin.json, marketplace.json, Makefile |
| Phase marker | `.sdd-phase` | 1 file | `.specify/.sdd-phase` |
| Directory paths | `sdd/` | structural | Top-level plugin dir |
| Permission patterns | `SDD_PATTERN_*` | 2 variables | `Bash(*/scripts/sdd-init.sh*)` |

### Hook Script Analysis

**context-hook.py** (most complex, 6+ pattern types):
- Marker file: `.claude-sdd-skill-pending-{session_id}`
- Command detection: `prompt.startswith('/sdd:')`
- Known commands list with "sdd:" prefix
- XML tags: `<sdd-context>`, `<sdd-error>`, `<sdd-configured>`, `<sdd-initialized>`, `<sdd-init-command>`, `<sdd-traits-command>`
- File paths: `sdd-init.sh`, `sdd-traits.sh`, `.specify/sdd-traits.json`

**skill-gate-hook.py**: Marker file `.claude-sdd-skill-pending-{session_id}`

**verification-gate-hook.py**: Marker `.claude-sdd-verified-{session_id}`, message `/sdd:verify`

**teams-enforce-hook.py**: Skill reference `{Skill: sdd:teams-orchestrate}`

### Shell Script Analysis

**sdd-init.sh** (~30 occurrences):
- Config path: `.specify/sdd-traits.json`
- Script call: `sdd-traits.sh`
- All function names are generic (no "sdd" in function names)

**sdd-traits.sh** (400+ occurrences, densest file):
- Constant: `TRAITS_CONFIG=".specify/sdd-traits.json"`
- Sentinel template: `<!-- SDD-TRAIT:${sentinel_trait} -->`
- Permission patterns: `SDD_PATTERN_INIT`, `SDD_PATTERN_TRAITS`
- Script self-references

### Sentinel Marker Decision

- Decision: Keep `<!-- SDD-TRAIT:name -->` format unchanged
- Rationale: "SDD" is the methodology name, sentinels identify trait-system provenance. Changing would break existing consumer projects with applied overlays.
- Alternative considered: Emit `<!-- SPEX-TRAIT:name -->` for new applications, recognize both patterns. Rejected because the spec explicitly says to keep sentinel format.
- Consequence: `spex-traits.sh` will emit `SDD-TRAIT` sentinels. This is intentionally inconsistent to maintain backwards compatibility.

### Migration Strategy

- Decision: Copy-on-init migration for `sdd-traits.json` to `spex-traits.json`
- Rationale: Non-destructive, preserves old config during transition
- Alternatives considered: Symlink (fragile), auto-delete (risky), rename-in-place (breaks old plugin if still installed)

### Files Excluded from Rename

Per spec FR-018, these are left unchanged:
- `specs/` directory (all historical specs)
- `brainstorm/` directory (all brainstorm docs)
- `CHANGELOG.md` (historical record)
