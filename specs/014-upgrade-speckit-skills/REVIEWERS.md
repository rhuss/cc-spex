# Review Guide: Upgrade speckit commands to Agent Skills format

**Feature Branch**: `014-upgrade-speckit-skills`
**Spec**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md) | **Tasks**: [tasks.md](tasks.md)

## What This Feature Does

Migrates cc-spex from the old speckit command format (`.claude/commands/speckit.*.md`) to the new upstream Agent Skills format (`.claude/skills/speckit-*/SKILL.md`). This is a breaking change (v4.0.0) with a version gate requiring spec-kit >= 0.5.0.

## Key Review Areas

### 1. Version Gate (spex-init.sh)
- Does `check_version()` reliably parse the decorated `specify version` output?
- Does the error message provide the exact upgrade command?
- Does the semver comparison handle edge cases (pre-release versions, dev suffixes)?

### 2. Overlay System (spex-traits.sh)
- Does the new overlay mapping correctly resolve `skills/<name>/SKILL.append.md` → `.claude/skills/<name>/SKILL.md`?
- Does prepend correctly handle YAML frontmatter (insert after `---` block)?
- Is idempotency preserved (sentinel markers for both append and prepend)?
- Does cleanup correctly remove stale trait blocks?

### 3. Migration Path
- Are old `.claude/commands/speckit.*.md` files cleaned up during migration?
- Is the `.gitignore` pattern updated in both init.sh (for user projects) and the repo's own `.gitignore`?

### 4. Reference Completeness
- Are there zero `speckit.` dot-notation references remaining in active files?
- Are historical artifacts (brainstorm/, old specs/) correctly excluded?

### 5. Release Strategy
- Is v3.0.2 tagged before any migration changes?
- Does `release/3.x` branch exist for bugfix maintenance?

## Files to Review (by priority)

| Priority | File | What to Check |
|----------|------|---------------|
| High | `spex/scripts/spex-init.sh` | Version gate, readiness check, migration |
| High | `spex/scripts/spex-traits.sh` | Overlay mapping, prepend support, sentinel handling |
| Medium | `spex/overlays/*/skills/*/SKILL.append.md` | All 17 files migrated, content preserved |
| Medium | `spex/scripts/hooks/pretool-gate.py` | Command name mapping updated |
| Medium | `spex/scripts/hooks/context-hook.py` | Command URL mapping updated |
| Low | `spex/skills/*/SKILL.md` | Reference updates (mechanical, verify with grep) |
| Low | Documentation files | Reference updates |
| Low | `.specify/memory/constitution.md` | Naming section updated |

## Validation Commands

```bash
# Verify zero dot-notation references in active files
rg 'speckit\.' spex/skills/ spex/commands/ spex/scripts/ spex/docs/ README.md docs/

# Verify all 17 overlay files exist in new structure
fd SKILL.append.md spex/overlays/

# Verify old overlay directories removed
fd -t d commands spex/overlays/

# Verify integration test passes
make release
```
