# Brainstorm 07: Upgrade speckit commands to skills format

**Date:** 2026-04-05
**Status:** Draft
**Trigger:** Upstream spec-kit (github/spec-kit) upgraded from commands to Agent Skills format

## Context

The upstream `specify` CLI (spec-kit) has changed how it generates speckit commands:

| Aspect | Old (specify 0.4.x) | New (specify 0.5.x) |
|--------|---------------------|---------------------|
| Format | Claude Code commands | Agent Skills (open standard) |
| Location | `.claude/commands/speckit.specify.md` | `.claude/skills/speckit-specify/SKILL.md` |
| Naming | Dot notation (`speckit.specify`) | Hyphen notation (`speckit-specify`) |
| Invocation | `/speckit.specify` | `/speckit-specify` |

cc-spex wraps these speckit commands with trait overlays (superpowers, teams, worktrees, deep-review) and provides its own `spex:*` extension commands. The upstream format change requires updating:

- **spex-init.sh**: Readiness checks, gitignore patterns, version detection
- **spex-traits.sh**: Overlay application logic (target path mapping)
- **17 trait overlay files**: Renamed from `speckit.X.append.md` to `speckit-X.append.md`
- **5 ship-guard overlay files**: Same rename
- **All documentation**: README, CHANGELOG, help docs, brainstorm files, specs

## Decisions

### D1: Version gate mechanism
**Decision:** Parse `specify version` output for semver comparison.
**Rationale:** Most reliable, does not depend on behavioral probing. Require `specify` >= 0.5.0. If older, print error with upgrade instructions and exit.

### D2: Overlay directory structure (mirror skills)
**Decision:** Mirror the skills directory structure: `spex/overlays/<trait>/skills/speckit-specify/SKILL.append.md`
**Rationale:** Consistent with the upstream skills layout. Also enables `SKILL.prepend.md` for content that should be injected before the upstream skill content (e.g., overriding defaults, adding preamble instructions).

The overlay mapping in `spex-traits.sh` changes:

```
Old: commands/speckit.specify.append.md        →  .claude/commands/speckit.specify.md  (append)
New: skills/speckit-specify/SKILL.append.md    →  .claude/skills/speckit-specify/SKILL.md  (append)
New: skills/speckit-specify/SKILL.prepend.md   →  .claude/skills/speckit-specify/SKILL.md  (prepend)
```

The `templates/` subdirectory convention remains unchanged for template overlays.

### D3: Keep spex commands as commands
**Decision:** Do NOT migrate spex's own commands to skills format.
**Rationale:** Skills installed via plugins don't get tab-completion in Claude Code. The `spex/commands/` directory stays as-is. Only speckit-related references are updated.

A previous attempt to migrate spex commands to skills (commit `8d89217`) was reverted (`cad8ff4`) for this reason.

### D4: No dual-version support
**Decision:** cc-spex v4.0.0 requires spec-kit >= 0.5.0. No compatibility shim for old command format.
**Rationale:** Maintaining both formats doubles the overlay system complexity. Users on older spec-kit should stay on cc-spex 3.x.

## Release Strategy

```
main (current, v3.0.1)
  │
  ├── Tag v3.0.2 (last release with old command format)
  ├── Create release/3.x branch from v3.0.2
  │     └── Bugfix-only maintenance for speckit.* command format
  │
  └── main continues
        ├── Migrate all speckit references (dot → hyphen, commands → skills)
        ├── Update spex-init.sh with version gate
        ├── Update spex-traits.sh overlay mapping
        ├── Rename all 22 overlay files
        ├── Update documentation
        └── Release v4.0.0
```

## Scope of Changes

### 1. spex-init.sh

- **`check_ready()`**: Check for `.claude/skills/speckit-specify/SKILL.md` instead of `.claude/commands/speckit.specify.md`
- **Version gate**: Parse `specify version` output, require >= 0.5.0, error with upgrade command if older
- **Migration cleanup**: If old `.claude/commands/speckit.*.md` files exist, remove them after `specify init` generates the new skills
- **`.gitignore`**: Change pattern from `.claude/commands/speckit.*` to `.claude/skills/speckit-*`
- **Command detection**: Update `ls .claude/commands/speckit.*` to `ls .claude/skills/speckit-*/SKILL.md`

### 2. spex-traits.sh

- **`apply_internal_overlays()`** and **`do_apply()`**: Update the overlay-to-target mapping:
  - `skills/<name>/SKILL.append.md` → append to `.claude/skills/<name>/SKILL.md`
  - `skills/<name>/SKILL.prepend.md` → prepend to `.claude/skills/<name>/SKILL.md`
  - `templates/` subdirectory → target `.specify/templates/*.md` (unchanged)
- **Prepend logic**: For `SKILL.prepend.md`, insert content at the top of the target SKILL.md (after any frontmatter if present)
- **Sentinel cleanup**: Update sentinel scanning to look in skills files

### 3. Overlay files (22 total)

Migrate all overlay files from `commands/` to `skills/` directory structure:

```
# Ship-guard (5 files)
_ship-guard/commands/speckit.clarify.append.md   → _ship-guard/skills/speckit-clarify/SKILL.append.md
_ship-guard/commands/speckit.implement.append.md → _ship-guard/skills/speckit-implement/SKILL.append.md
_ship-guard/commands/speckit.plan.append.md      → _ship-guard/skills/speckit-plan/SKILL.append.md
_ship-guard/commands/speckit.specify.append.md   → _ship-guard/skills/speckit-specify/SKILL.append.md
_ship-guard/commands/speckit.tasks.append.md     → _ship-guard/skills/speckit-tasks/SKILL.append.md

# deep-review (1 file)
deep-review/commands/speckit.implement.append.md → deep-review/skills/speckit-implement/SKILL.append.md

# superpowers (3 files)
superpowers/commands/speckit.implement.append.md → superpowers/skills/speckit-implement/SKILL.append.md
superpowers/commands/speckit.plan.append.md      → superpowers/skills/speckit-plan/SKILL.append.md
superpowers/commands/speckit.specify.append.md   → superpowers/skills/speckit-specify/SKILL.append.md

# teams-spec (1 file)
teams-spec/commands/speckit.implement.append.md  → teams-spec/skills/speckit-implement/SKILL.append.md

# teams-vanilla (2 files)
teams-vanilla/commands/speckit.implement.append.md → teams-vanilla/skills/speckit-implement/SKILL.append.md
teams-vanilla/commands/speckit.plan.append.md      → teams-vanilla/skills/speckit-plan/SKILL.append.md

# teams (2 files)
teams/commands/speckit.implement.append.md → teams/skills/speckit-implement/SKILL.append.md
teams/commands/speckit.plan.append.md      → teams/skills/speckit-plan/SKILL.append.md

# worktrees (3 files)
worktrees/commands/speckit.implement.append.md → worktrees/skills/speckit-implement/SKILL.append.md
worktrees/commands/speckit.plan.append.md      → worktrees/skills/speckit-plan/SKILL.append.md
worktrees/commands/speckit.specify.append.md   → worktrees/skills/speckit-specify/SKILL.append.md
```

After migration, remove empty `commands/` subdirectories from each overlay.

Note: `SKILL.prepend.md` files can be added to any of these directories as needed. No existing overlays use prepend yet, but the infrastructure supports it from day one.

### 4. Overlay file content

Inside each overlay file, update any references to the old command names:
- `/speckit.specify` → `/speckit-specify`
- `/speckit.plan` → `/speckit-plan`
- `/speckit.implement` → `/speckit-implement`
- etc.

### 5. spex skills and commands

Update all `spex/skills/*/SKILL.md` and `spex/commands/*.md` files that reference speckit commands.

### 6. Documentation

- **README.md**: Update workflow examples, command references
- **CHANGELOG.md**: Add v4.0.0 section with breaking change and migration instructions
- **CLAUDE.md**: Update project structure (will auto-regenerate)
- **docs/**: Help documentation, tutorials
- **brainstorm/**: Historical references (optional, low priority)
- **specs/**: Historical specs (optional, low priority)

### 7. Integration test

Update `tests/` to check for skills format instead of commands format.

### 8. Makefile

Update any validation that checks for speckit command files.

## Migration UX (spex-init.sh)

When a user with old spec-kit runs `spex:init` on cc-spex v4.0.0:

```
ERROR: spec-kit version 0.4.3 is too old for this version of spex.

spex v4.0.0+ requires spec-kit >= 0.5.0, which uses the Agent Skills format.

Upgrade with:
  uv tool install specify-cli --force --from git+https://github.com/github/spec-kit.git

Then re-run /spex:init to complete the migration.
```

When a user with new spec-kit but old speckit.*.md files runs init:

```
Migrating from speckit commands to skills format...
  Removed .claude/commands/speckit.specify.md (replaced by .claude/skills/speckit-specify/)
  Removed .claude/commands/speckit.plan.md (replaced by .claude/skills/speckit-plan/)
  ...
Migration complete. Restarting spec-kit initialization.
```

## Open Questions

- **Q1**: Should `release/3.x` get any updates to warn users about the upcoming v4.0.0 migration? (e.g., a deprecation notice in spex-init.sh output)
- **Q2**: The `init-options.json` records `speckit_version: 0.4.3`. Should we update this file or let `specify init` handle it?
- **Q3**: Should we update historical brainstorm and spec files to use the new naming, or leave them as historical artifacts?
