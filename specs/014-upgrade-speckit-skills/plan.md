# Implementation Plan: Upgrade speckit commands to Agent Skills format

**Branch**: `014-upgrade-speckit-skills` | **Date**: 2026-04-05 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/014-upgrade-speckit-skills/spec.md`

## Summary

Migrate cc-spex from the old speckit command format (`.claude/commands/speckit.*.md`) to the new Agent Skills format (`.claude/skills/speckit-*/SKILL.md`) to match upstream spec-kit >= 0.5.0. This includes updating the init/traits scripts, restructuring 17 overlay files, adding prepend support, updating 150+ references across skills/commands/docs, and enforcing a version gate. Release v3.0.2 first as the last old-format release, create `release/3.x` for maintenance, then ship v4.0.0 with the migration.

## Technical Context

**Language/Version**: Bash (POSIX-compatible), Python 3 (hooks), Markdown
**Primary Dependencies**: `jq` (JSON parsing), `specify` CLI >= 0.5.0 (spec-kit)
**Storage**: File-based (JSON config, Markdown documents)
**Testing**: Integration test via `make release` (installs plugin, validates structure, cleans up)
**Target Platform**: Claude Code plugin (macOS/Linux)
**Project Type**: CLI plugin
**Performance Goals**: Init completes in < 5 seconds, version check in < 2 seconds
**Constraints**: POSIX-compatible Bash, no compiled artifacts, no package dependencies beyond `jq` and `specify`
**Scale/Scope**: 17 overlay files, 11 skill files, 4 script files, 6 documentation files

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-Guided Development | Pass | Following full SDD workflow (specify, clarify, plan, tasks) |
| II. Overlay Delegation | Pass | Overlays remain < 30 lines, delegate to skills via `{Skill:}` |
| III. Trait Composability | Pass | Traits remain independent, overlay structure preserved |
| IV. Quality Gates | Pass | Review-spec completed, review-plan will run after tasks |
| V. Naming Discipline | Action needed | Constitution itself needs updating (FR-018) |
| VI. Skill Autonomy | Pass | No skills are being merged or having roles mixed |

**Section V note**: The constitution currently references `/speckit.*` prefix and `{commands,templates}/` overlay paths. FR-018 requires updating these. This is not a violation; it is part of the planned work.

## Project Structure

### Documentation (this feature)

```text
specs/014-upgrade-speckit-skills/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```text
spex/
├── commands/            # Spex commands (UNCHANGED, stays as commands)
├── skills/              # Spex skills (update speckit references inside)
├── overlays/            # Trait overlays (RESTRUCTURE: commands/ → skills/)
│   ├── _ship-guard/skills/speckit-*/SKILL.append.md
│   ├── deep-review/skills/speckit-*/SKILL.append.md
│   ├── superpowers/skills/speckit-*/SKILL.append.md
│   ├── teams/skills/speckit-*/SKILL.append.md
│   ├── teams-spec/skills/speckit-*/SKILL.append.md
│   ├── teams-vanilla/skills/speckit-*/SKILL.append.md
│   └── worktrees/skills/speckit-*/SKILL.append.md
├── scripts/
│   ├── spex-init.sh     # MAJOR: version gate, skills detection, migration
│   ├── spex-traits.sh   # MAJOR: skills overlay mapping, prepend support
│   └── hooks/
│       ├── pretool-gate.py   # UPDATE: command name mapping
│       └── context-hook.py   # UPDATE: command URL mapping
└── docs/                # UPDATE: speckit references
```

**Structure Decision**: Existing plugin structure is preserved. The only structural change is within `spex/overlays/` where `commands/` subdirectories become `skills/<name>/` subdirectories.

## Implementation Phases

### Phase 1: Release v3.0.2 and create maintenance branch (FR-014, FR-015)

Tag the current main as v3.0.2, create `release/3.x` branch. This is a prerequisite before any migration work begins on main.

**Steps**:
1. Bump version in marketplace.json and plugin.json to 3.0.2
2. Update CHANGELOG.md with v3.0.2 entry
3. Run `make release` to validate
4. Tag and create release
5. Create `release/3.x` branch from tag

### Phase 2: Core script updates (FR-001 through FR-005, FR-007, FR-009 through FR-013)

Update the two core scripts that power initialization and trait overlay application.

**spex-init.sh changes**:
- Add `check_version()` function: parse `specify version` output, compare semver, require >= 0.5.0
- Update `check_ready()`: look for `.claude/skills/speckit-specify/SKILL.md` instead of `.claude/commands/speckit.specify.md`
- Add `migrate_old_commands()`: detect and remove old `.claude/commands/speckit.*.md` files
- Update `configure_gitignore()`: use `.claude/skills/speckit-*` pattern
- Update `do_init()`: call version check before `specify init`, handle migration
- Update command detection: `ls .claude/skills/speckit-*/SKILL.md` instead of `ls .claude/commands/speckit.*`

**spex-traits.sh changes**:
- Update `apply_internal_overlays()`: scan for `skills/*/SKILL.append.md` instead of `commands/*.append.md`
- Update `do_apply()`: new overlay-to-target mapping for skills directory structure
- Add prepend support: detect `SKILL.prepend.md` files, insert after YAML frontmatter
- Update sentinel scanning: look in `.claude/skills/` instead of `.claude/commands/`
- Update cleanup logic: remove stale trait blocks from skills files

### Phase 3: Overlay file migration (FR-009, SC-003)

Restructure all 17 overlay files from `commands/` to `skills/` directory layout. Update the 2 files that contain internal speckit.X references.

**Steps**:
1. Create new directory structure under each overlay trait
2. Move and rename each file (e.g., `commands/speckit.specify.append.md` → `skills/speckit-specify/SKILL.append.md`)
3. Update internal references in `superpowers/skills/speckit-plan/SKILL.append.md` (`/speckit.tasks` → `/speckit-tasks`, `/speckit.clarify` → `/speckit-clarify`)
4. Remove empty `commands/` directories
5. Verify all 17 files migrated with content preserved

### Phase 4: Hook script updates

Update the two Python hook scripts that reference speckit command names.

**pretool-gate.py**: Update the stage-to-command mapping dictionary:
- `"speckit.specify"` → `"speckit-specify"`
- `"speckit.clarify"` → `"speckit-clarify"`
- `"speckit.plan"` → `"speckit-plan"`
- `"speckit.tasks"` → `"speckit-tasks"`
- `"speckit.implement"` → `"speckit-implement"`

**context-hook.py**: Update command URL mappings:
- `'/speckit.specify'` → `'/speckit-specify'`
- etc.

### Phase 5: Skill and command reference updates (FR-006, SC-005)

Update all speckit dot-notation references across 11 skill files and 1 command file. This is the bulk of the text changes (123+ references in skills, 1 in commands).

**Approach**: For each file, replace all instances of:
- `/speckit.specify` → `/speckit-specify`
- `/speckit.plan` → `/speckit-plan`
- `/speckit.tasks` → `/speckit-tasks`
- `/speckit.implement` → `/speckit-implement`
- `/speckit.clarify` → `/speckit-clarify`
- `/speckit.analyze` → `/speckit-analyze`
- `/speckit.checklist` → `/speckit-checklist`
- `/speckit.constitution` → `/speckit-constitution`
- `/speckit.taskstoissues` → `/speckit-taskstoissues`
- `speckit.specify` (without slash) → `speckit-specify`
- `.claude/commands/speckit.` → `.claude/skills/speckit-`

### Phase 6: Documentation and constitution updates (FR-006, FR-018)

Update user-facing documentation and the constitution.

**Files**:
- `README.md`: Workflow examples, command tables, diagram references
- `CHANGELOG.md`: Add v4.0.0 section with breaking change and migration guide
- `docs/smoke-test.md`: Test instructions
- `docs/plugin-schema.md`: Architecture description
- `spex/docs/help.md`: Help text
- `spex/docs/tutorial-full.md`: Tutorial commands
- `spex/docs/tutorial-team.md`: Team tutorial commands
- `.specify/memory/constitution.md`: Section V naming, Plugin Architecture overlay paths
- `.gitignore`: Pattern update (also handled in init.sh for user projects)

### Phase 7: Version bump and integration test (FR-016, SC-006)

Bump version to 4.0.0, update integration test, validate everything works.

**Steps**:
1. Bump version in `.claude-plugin/marketplace.json` and `spex/.claude-plugin/plugin.json` to 4.0.0
2. Update integration test to check for skills format instead of commands format
3. Run `make release` to validate
4. Verify SC-005: `rg 'speckit\.' spex/skills/ spex/commands/ spex/scripts/ spex/docs/ README.md` returns zero matches (excluding historical specs/)

## Complexity Tracking

No constitution violations requiring justification.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `specify version` output format changes | Low | Medium | Robust regex extraction, fallback error message |
| Users skip version upgrade | Medium | Low | Clear error message with exact upgrade command |
| Overlay content lost during migration | Low | High | Git tracks all changes; verify file count and content after migration |
| Prepend breaks YAML frontmatter | Low | Medium | Detect frontmatter boundary (`---`) before inserting |
