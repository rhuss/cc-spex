# Feature Specification: Upgrade speckit commands to Agent Skills format

**Feature Branch**: `014-upgrade-speckit-skills`
**Created**: 2026-04-05
**Status**: Draft
**Input**: Upstream spec-kit (github/spec-kit) upgraded from commands to Agent Skills format. Migrate cc-spex to match, enforce version gate, release v3.0.2 then v4.0.0.

## User Scenarios & Testing

### User Story 1 - Fresh project initialization with new spec-kit (Priority: P1)

A plugin user runs `/spex:init` on a project that has never used spec-kit before. They have the new `specify` CLI (>= 0.5.0) installed. The initialization detects the new CLI version, runs `specify init`, and finds the generated skills at `.claude/skills/speckit-*/SKILL.md`. Trait overlays are applied to the skills files. The user can immediately invoke `/speckit-specify` and other speckit skills.

**Why this priority**: This is the primary happy path for all new users after v4.0.0 ships.

**Independent Test**: Run `/spex:init` in a clean directory with specify >= 0.5.0 installed. Verify skills are created, traits are applied, and speckit skills are invocable.

**Acceptance Scenarios**:

1. **Given** a project without `.specify/` or `.claude/skills/`, **When** the user runs `/spex:init`, **Then** `specify init` creates `.claude/skills/speckit-*/SKILL.md` files and spex reports READY
2. **Given** initialization completed, **When** traits are enabled (e.g., superpowers), **Then** trait overlay content is appended to the corresponding `SKILL.md` files
3. **Given** initialization completed, **When** the user checks `.gitignore`, **Then** it contains `.claude/skills/speckit-*` (not the old `.claude/commands/speckit.*` pattern)

---

### User Story 2 - Existing user upgrades from old spec-kit (Priority: P1)

A plugin user has an existing project with old-format speckit commands (`.claude/commands/speckit.*.md`) and runs `/spex:init` after upgrading to cc-spex v4.0.0. The system detects the old `specify` CLI version, stops with a clear error, and provides upgrade instructions. After upgrading the CLI, re-running init migrates from commands to skills.

**Why this priority**: Most existing users will hit this path. A confusing upgrade experience would block adoption.

**Independent Test**: Set up a project with old speckit.*.md files. Run `/spex:init` with old specify CLI and verify error. Upgrade CLI, re-run, and verify migration completes.

**Acceptance Scenarios**:

1. **Given** a project with `.claude/commands/speckit.specify.md` and specify CLI < 0.5.0, **When** the user runs `/spex:init`, **Then** the system outputs an error with the exact upgrade command
2. **Given** the user upgraded specify CLI to >= 0.5.0, **When** they re-run `/spex:init`, **Then** old `.claude/commands/speckit.*.md` files are cleaned up and new skills are generated
3. **Given** migration completed, **When** trait overlays were previously applied to old command files, **Then** overlays are re-applied to the new skills files using the updated overlay structure

---

### User Story 3 - Trait overlay application with prepend support (Priority: P2)

A plugin user enables a trait (e.g., superpowers) on a project using the new skills format. The trait system finds overlay files at `spex/overlays/<trait>/skills/speckit-*/SKILL.append.md` and `SKILL.prepend.md`, and applies them to the corresponding `.claude/skills/speckit-*/SKILL.md` targets. Prepend content is inserted at the top (after any frontmatter), append content at the bottom.

**Why this priority**: Traits are a core differentiator of cc-spex over raw spec-kit. They must work with the new format.

**Independent Test**: Enable a trait, verify SKILL.md files contain both prepended and appended content in the correct order.

**Acceptance Scenarios**:

1. **Given** a project with speckit skills initialized, **When** the user enables the superpowers trait, **Then** `SKILL.append.md` content is appended to the target `SKILL.md` with a sentinel marker
2. **Given** a trait has a `SKILL.prepend.md` overlay, **When** the trait is applied, **Then** the prepend content appears before the original skill content (but after any YAML frontmatter)
3. **Given** a trait is already applied (sentinel present), **When** `apply` runs again, **Then** the overlay is not duplicated (idempotent)
4. **Given** a trait is disabled, **When** overlays are cleaned up, **Then** the sentinel-delimited block is removed from the target `SKILL.md`

---

### User Story 4 - Release and branching workflow (Priority: P2)

The maintainer tags v3.0.2 from current main, creates a `release/3.x` branch for bugfix-only maintenance, then continues on main with the v4.0.0 migration. Users on old spec-kit stay on the 3.x branch. Users who upgrade get v4.0.0.

**Why this priority**: Ensures existing users are not broken and have a supported path for bugfixes while the migration proceeds.

**Independent Test**: Verify v3.0.2 tag exists, `release/3.x` branch exists and contains old-format commands, main contains new-format skills after migration.

**Acceptance Scenarios**:

1. **Given** the current main branch, **When** v3.0.2 is tagged, **Then** the tag contains the last working version with `speckit.*.md` commands
2. **Given** v3.0.2 is tagged, **When** `release/3.x` is created from that tag, **Then** the branch can receive cherry-picked bugfixes independently
3. **Given** main continues with the migration, **When** v4.0.0 is released, **Then** all speckit references use hyphen notation and skills format

---

### Edge Cases

- What happens when a user has specify >= 0.5.0 but still has old `.claude/commands/speckit.*.md` files? Init cleans them up during migration.
- What happens when a user has a mix of old and new format files? Init removes all old-format files, runs `specify init` fresh, then applies traits.
- What happens when a trait overlay references a speckit skill that doesn't exist? A warning is logged, the overlay is skipped, other overlays continue.
- What happens when `specify version` output format changes? Version parsing should handle the decorated CLI output and extract semver reliably.
- What happens when both `SKILL.prepend.md` and `SKILL.append.md` exist for the same trait/skill? Both are applied: prepend first, then append.

## Requirements

### Functional Requirements

**Version Gate**

- **FR-001**: The init system MUST parse the `specify` CLI version and require >= 0.5.0
- **FR-002**: When the CLI version is below 0.5.0, the system MUST display an error with the exact upgrade command (`uv tool install specify-cli --force --from git+https://github.com/github/spec-kit.git`)
- **FR-003**: The version check MUST handle the decorated ASCII art output of `specify version` and extract the semver string reliably

**Skills Format Support**

- **FR-004**: The readiness check MUST look for `.claude/skills/speckit-specify/SKILL.md` (and other core skills) instead of `.claude/commands/speckit.specify.md`
- **FR-005**: The `.gitignore` configuration MUST use the pattern `.claude/skills/speckit-*` instead of `.claude/commands/speckit.*`
- **FR-006**: All references to speckit commands in active spex skills, commands, scripts, and user-facing documentation (README, CHANGELOG, help docs) MUST use hyphen notation (`/speckit-specify`) instead of dot notation (`/speckit.specify`). Historical artifacts (brainstorm files, old spec directories) are excluded.

**Migration**

- **FR-007**: When old `.claude/commands/speckit.*.md` files exist during init, the system MUST remove them after generating new skills
- **FR-008**: The system MUST NOT support both old and new speckit formats simultaneously

**Trait Overlay System**

- **FR-009**: The overlay system MUST support the directory structure `spex/overlays/<trait>/skills/<skill-name>/SKILL.append.md`
- **FR-010**: The overlay system MUST support `SKILL.prepend.md` files that inject content before the original skill content (after any YAML frontmatter)
- **FR-011**: Overlay application MUST remain idempotent via sentinel markers
- **FR-012**: The overlay system MUST map `skills/<name>/SKILL.append.md` to `.claude/skills/<name>/SKILL.md` as the target
- **FR-013**: The template overlay path (`templates/`) MUST remain unchanged

**Release Management**

- **FR-014**: A v3.0.2 release MUST be tagged from the current main before migration begins
- **FR-015**: A `release/3.x` branch MUST be created from the v3.0.2 tag for bugfix maintenance
- **FR-016**: The migration MUST result in a v4.0.0 release on main

**Spex Commands**

- **FR-017**: Spex's own commands (in `spex/commands/`) MUST remain as commands and NOT be migrated to skills format
- **FR-018**: The project constitution (`.specify/memory/constitution.md`) MUST be updated to reflect the new naming convention (`/speckit-*` prefix) and overlay directory structure (`skills/<name>/` instead of `{commands,templates}/`)

### Key Entities

- **Speckit Skill**: An upstream skill generated by `specify init` at `.claude/skills/speckit-<name>/SKILL.md`. Nine total: specify, plan, tasks, implement, clarify, analyze, checklist, constitution, taskstoissues
- **Trait Overlay**: A file that extends a speckit skill with additional content. Lives in `spex/overlays/<trait>/skills/<skill-name>/SKILL.{append,prepend}.md`
- **Ship Guard Overlay**: An unconditional (non-trait) overlay applied to speckit skills for pipeline control. Lives in `spex/overlays/_ship-guard/skills/<skill-name>/SKILL.append.md`

## Success Criteria

### Measurable Outcomes

- **SC-001**: All 9 speckit skills are detected and validated by the init system in under 5 seconds
- **SC-002**: Users with specify < 0.5.0 receive a clear upgrade error within 2 seconds of running init
- **SC-003**: All 22 trait overlay files are migrated to the new directory structure with zero content loss
- **SC-004**: Trait application completes successfully for all enabled traits (superpowers, teams, worktrees, deep-review) with the new overlay paths
- **SC-005**: Zero references to `speckit.` dot notation remain in any spex skill, command, or script after migration
- **SC-006**: The integration test suite passes with the new skills format
- **SC-007**: Prepend and append overlays can coexist on the same skill without conflicts

## Assumptions

- The `specify` CLI version >= 0.5.0 generates skills at `.claude/skills/speckit-*/SKILL.md` (confirmed by testing with 0.5.1.dev0)
- The `specify version` output contains a parseable semver string in the format `CLI Version    X.Y.Z`
- The `release/3.x` branch will receive only critical bugfixes, not feature backports
- Historical brainstorm and spec documents will NOT be updated to use new naming (they are historical artifacts)
- The `init-options.json` file's `speckit_version` field is managed by `specify init` and does not need manual updates
- SKILL.md files generated by specify may contain YAML frontmatter (the prepend logic must handle this)
