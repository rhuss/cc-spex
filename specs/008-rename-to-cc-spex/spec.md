# Feature Specification: Rename Plugin to cc-spex

**Feature Branch**: `008-rename-to-cc-spex`
**Created**: 2026-03-27
**Status**: Draft
**Input**: Rename cc-sdd plugin to cc-spex with full command prefix, directory, and script renames plus backwards-compatible migration.

## User Scenarios & Testing

### User Story 1 - Plugin Developer Renames All Internal References (Priority: P1)

A plugin developer runs the rename across all plugin files so that every command, skill, overlay, hook, and script uses the new `spex:` prefix and `spex` naming instead of `sdd:` and `sdd`. After the rename, the plugin loads in Claude Code, all commands are discoverable under `/spex:*`, and hooks fire correctly.

**Why this priority**: This is the core rename. Nothing else works until internal references are consistent.

**Independent Test**: Install the renamed plugin in Claude Code. Run `/spex:help`, `/spex:init`, `/spex:traits`. Verify all commands load, hooks inject `<spex-context>` tags, and skills cross-reference each other correctly.

**Acceptance Scenarios**:

1. **Given** the rename is complete, **When** a user types `/spex:` in Claude Code, **Then** all 10 commands appear in autocomplete with correct descriptions.
2. **Given** the rename is complete, **When** `/spex:init` is run in a new project, **Then** the init script runs, applies trait overlays, and produces no errors referencing `sdd`.
3. **Given** the rename is complete, **When** `/spex:traits` is run, **Then** trait listing, enabling, and disabling all work with the new `spex-traits.json` config file.
4. **Given** the rename is complete, **When** any skill invokes `{Skill: spex:other-skill}`, **Then** the delegation resolves correctly.
5. **Given** the rename is complete, **When** the context hook fires, **Then** it emits `<spex-context>`, `<spex-configured>`, `<spex-initialized>`, `<spex-init-command>`, and `<spex-traits-command>` XML tags (not `sdd-*` tags).

---

### User Story 2 - Backwards-Compatible Migration for Existing Projects (Priority: P2)

A user with an existing project configured for the old `sdd` plugin runs `/spex:init`. The init script detects the old `sdd-traits.json` config file and migrates it to `spex-traits.json`, preserving all trait settings. The user does not lose their configuration.

**Why this priority**: Existing users must not be broken by the rename. Migration ensures a smooth transition.

**Independent Test**: Create a project with `.specify/sdd-traits.json` containing trait configuration. Run `/spex:init`. Verify `spex-traits.json` is created with identical content and the old file is preserved (or backed up) during the transition period.

**Acceptance Scenarios**:

1. **Given** a project has `.specify/sdd-traits.json` but no `spex-traits.json`, **When** `/spex:init` runs, **Then** the old config is copied to `spex-traits.json` and a message informs the user about the migration.
2. **Given** a project has both `sdd-traits.json` and `spex-traits.json`, **When** `/spex:init` runs, **Then** `spex-traits.json` takes precedence and the old file is ignored.
3. **Given** a project has only `spex-traits.json` (fresh setup), **When** `/spex:init` runs, **Then** no migration logic fires and init proceeds normally.
4. **Given** old overlay sentinel markers (`<!-- SDD-TRAIT:name -->`) exist in project files, **When** `/spex:init` applies overlays, **Then** new sentinels use the same format (sentinel format is part of the overlay content, not the plugin naming).

---

### User Story 3 - Repo-Root Documentation and Tooling Files Updated (Priority: P3)

All documentation files at the repository root (README.md, CLAUDE.md, TESTING.md, Makefile, .gitignore, etc.) reflect the new `spex` naming. The constitution is updated to reference `spex:` prefixes. Memory files are updated.

**Why this priority**: Documentation consistency matters for contributors and users, but does not block functional use of the plugin.

**Independent Test**: Search the entire repo (excluding `specs/`, `brainstorm/`, and `CHANGELOG.md`) for remaining `sdd:` or `sdd-` references. Only methodology prose ("SDD methodology", "Spec-Driven Development") should remain.

**Acceptance Scenarios**:

1. **Given** the documentation rename is complete, **When** searching for `sdd:` as a command prefix across non-excluded files, **Then** zero matches are found.
2. **Given** the constitution is updated, **When** reading `.specify/memory/constitution.md`, **Then** all command/skill/overlay references use `spex:` while methodology prose still says "SDD".
3. **Given** CLAUDE.md is updated, **When** reading the project structure section, **Then** it shows `spex/` as the plugin root directory with `spex/commands/`, `spex/skills/`, etc.

---

### User Story 4 - GitHub Repo and Parent Directory Renamed (Priority: P4)

The GitHub repository is renamed from `rhuss/cc-sdd` to `rhuss/cc-spex`. The local parent directory is renamed from `cc-superpowers-sdd` to `cc-superpowers-spex`. All hardcoded URLs in the plugin are updated.

**Why this priority**: This is the final external-facing step. It depends on all internal renames being complete and tested first.

**Independent Test**: After GitHub rename, verify the old URL redirects. After directory rename, verify `make reinstall` works from the new path.

**Acceptance Scenarios**:

1. **Given** the GitHub repo is renamed, **When** visiting `github.com/rhuss/cc-sdd`, **Then** GitHub redirects to `github.com/rhuss/cc-spex`.
2. **Given** `plugin.json` and `marketplace.json` are updated, **When** reading these files, **Then** all URLs point to `rhuss/cc-spex`.
3. **Given** the parent directory is renamed, **When** running `make reinstall` from `cc-superpowers-spex/`, **Then** the plugin installs correctly.

---

### User Story 5 - Consumer Projects Updated (Priority: P5)

Consumer projects (such as cc-deck) that reference the plugin update their command references from `/sdd:*` to `/spex:*`, their settings paths from `sdd-init.sh` to `spex-init.sh`, and their trait config from `sdd-traits.json` to `spex-traits.json`.

**Why this priority**: Consumer projects are separate repositories. They can be updated after the plugin itself is renamed and published.

**Independent Test**: In a consumer project, verify that `/speckit.specify`, `/speckit.plan`, and `/speckit.implement` all correctly invoke `spex:*` skills, and that hook permissions reference the new script paths.

**Acceptance Scenarios**:

1. **Given** a consumer project's `.claude/commands/speckit.*.md` files are updated, **When** running `/speckit.specify`, **Then** it invokes `{Skill: spex:*}` skills correctly.
2. **Given** a consumer project's `.claude/settings.local.json` is updated, **When** hook scripts fire, **Then** permissions match the new `spex-init.sh` and `spex-traits.sh` paths.

---

### Edge Cases

- What happens if a user has the old `sdd` plugin and new `spex` plugin installed simultaneously? Not expected in practice since this is a rename (same repo, new name), not a fork. No detection needed for MVP.
- What happens if overlay sentinel markers in consumer projects still use `<!-- SDD-TRAIT:name -->`? These should continue to work since sentinel format is content, not plugin naming. The `apply` function should recognize both old and new sentinels during the transition period.
- What happens if a user's `.claude/settings.local.json` has path permissions referencing `sdd-init.sh`? The migration guidance should tell users to update these paths manually (settings files are not auto-modified).
- What happens to in-progress feature branches that were created under the old naming? They continue to work, since the `specify` CLI manages branches independently of the plugin naming.

## Requirements

### Functional Requirements

- **FR-001**: All 10 plugin commands MUST use the `spex:` prefix instead of `sdd:` in their frontmatter name field.
- **FR-002**: All skill files MUST reference `{Skill: spex:*}` instead of `{Skill: sdd:*}` for cross-skill delegation.
- **FR-003**: All overlay files MUST use `{Skill: spex:*}` references in their content.
- **FR-004**: The plugin root directory MUST be renamed from `sdd/` to `spex/`.
- **FR-005**: Shell scripts MUST be renamed: `sdd-init.sh` to `spex-init.sh`, `sdd-traits.sh` to `spex-traits.sh`.
- **FR-006**: The trait config file MUST be renamed from `sdd-traits.json` to `spex-traits.json` in the plugin's default references.
- **FR-007**: Hook scripts MUST match `/spex:` prefixed commands instead of `/sdd:` for context injection and skill gating.
- **FR-008**: Hook XML output tags MUST change from `<sdd-*>` to `<spex-*>` (context, configured, initialized, init-command, traits-command).
- **FR-009**: `plugin.json` MUST update the plugin name from `"sdd"` to `"spex"` and update repository/homepage URLs to `rhuss/cc-spex`.
- **FR-010**: `marketplace.json` MUST update plugin name and URLs to reflect `cc-spex`.
- **FR-011**: The init script (`spex-init.sh`) MUST detect an existing `.specify/sdd-traits.json` and migrate it to `.specify/spex-traits.json`, preserving all trait settings.
- **FR-012**: The init script MUST prefer `spex-traits.json` when both old and new config files exist.
- **FR-013**: The constitution (`.specify/memory/constitution.md`) MUST update all command/skill/overlay references from `sdd:` to `spex:` while preserving "SDD" as the methodology name in prose.
- **FR-014**: CLAUDE.md MUST update the project structure to reference `spex/` directories and `spex:` commands.
- **FR-015**: README.md, TESTING.md, Makefile, .gitignore, and docs/ files MUST update `sdd` references to `spex` where they refer to tooling (not methodology).
- **FR-016**: The `.claude/commands/speckit.*.md` files MUST update `{Skill: sdd:*}` invocations to `{Skill: spex:*}`.
- **FR-017**: Memory files (MEMORY.md and individual memory files) MUST update tooling references from `sdd` to `spex`.
- **FR-018**: Historical files (specs/, brainstorm/, CHANGELOG.md) MUST be left unchanged.
- **FR-019**: Prose references to "SDD methodology" or "Spec-Driven Development" MUST be preserved unchanged throughout all files.
- **FR-020**: The GitHub repository MUST be renamed from `rhuss/cc-sdd` to `rhuss/cc-spex`.
- **FR-021**: The parent directory MUST be renamed from `cc-superpowers-sdd` to `cc-superpowers-spex`.

### Key Entities

- **Plugin Metadata**: `plugin.json` and `marketplace.json` defining the plugin's identity, name, URLs, and description.
- **Command Files**: 10 Markdown files in `commands/` that define slash commands with frontmatter including the `name:` field.
- **Skill Files**: 15+ `SKILL.md` files in `skills/` containing cross-references to other skills via `{Skill: name}` syntax.
- **Overlay Files**: Markdown append files in `overlays/<trait>/` containing sentinel markers and skill references.
- **Hook Scripts**: Python scripts in `scripts/hooks/` that match command prefixes and emit XML context tags.
- **Shell Scripts**: `spex-init.sh` and `spex-traits.sh` that handle initialization and trait management.
- **Trait Config**: `.specify/spex-traits.json` storing per-project trait enablement state.
- **Constitution**: `.specify/memory/constitution.md` defining project governance principles and naming conventions.

## Success Criteria

### Measurable Outcomes

- **SC-001**: After rename, searching for `sdd:` in the `spex/` directory returns zero matches (all command/skill prefixes migrated).
- **SC-002**: After rename, searching for `<sdd-` in `spex/scripts/` returns zero matches (all XML tags migrated).
- **SC-003**: Plugin loads in Claude Code with all 10 commands discoverable under `/spex:*`.
- **SC-004**: Running `/spex:init` in a project with old `sdd-traits.json` successfully migrates config to `spex-traits.json` with no data loss.
- **SC-005**: Running `/spex:traits list` shows all available traits with correct enable/disable state.
- **SC-006**: Searching the full repo (excluding specs/, brainstorm/, CHANGELOG.md) for `sdd:` as a command prefix returns zero matches. Only "SDD" as methodology name in prose remains.
- **SC-007**: All cross-skill delegation (`{Skill: spex:*}`) resolves correctly during a full SDD workflow (specify, plan, tasks, implement, verify).

## Assumptions

- GitHub's automatic redirect for renamed repositories will handle existing bookmarks and links during the transition.
- Consumer projects (cc-deck) will be updated in a separate effort after the plugin rename is complete and tested.
- The `specify` CLI tool itself does not reference `sdd` internally and needs no changes.
- Overlay sentinel markers (`<!-- SDD-TRAIT:name -->`) keep their current format since "SDD" is the methodology name. The sentinel is about the trait system, not the plugin prefix.
- The transition period for backwards compatibility (old `sdd-traits.json` detection) has no defined end date. It stays until a future cleanup removes it.
