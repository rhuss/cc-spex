# Rename cc-sdd to cc-spex

## Context

The GitHub project `gotalab/cc-sdd` (2,980 stars, TypeScript, multi-editor) has taken the "cc-sdd" name for spec-driven development tooling.
Our project (`rhuss/cc-sdd`, Bash/Markdown, Claude Code plugin) collides with that name.

**Decision:** Rename to **cc-spex** with full command prefix rename (Option A).

- No GitHub repos named "cc-spex" exist
- No naming conflicts in the developer tooling space
- "spex" is short, memorable, and clearly spec-related

## Scope: Full Rename (Option A)

Both the repo name AND the command prefix change: `sdd:` becomes `spex:`.

### 1. Plugin Repo (~45 files)

| Category | Files | Change |
|----------|-------|--------|
| Plugin metadata | `.claude-plugin/plugin.json` | `name: "sdd"` to `"spex"`, repo/homepage URLs to `rhuss/cc-spex` |
| Commands | 10 files in `commands/` | `name: sdd:*` to `spex:*` in frontmatter |
| Skills | 15 `SKILL.md` files in `skills/` | All cross-references `sdd:*` to `spex:*` |
| Hook scripts | 5 Python files in `scripts/hooks/` | `/sdd:` prefix matching to `/spex:` |
| Shell scripts | `sdd-init.sh`, `sdd-traits.sh` | Rename files to `spex-init.sh`, `spex-traits.sh` + internal refs |
| Trait config | `.specify/sdd-traits.json` | Rename to `spex-traits.json` |
| Documentation | 4 docs in `docs/` | All `sdd:` command references |
| Dev commands | `update-superpowers.md` | cc-sdd verification checks |
| Sync state | `.superpowers-sync` | Metadata references |

### 2. GitHub Repo Rename

- Rename `rhuss/cc-sdd` to `rhuss/cc-spex`
- GitHub auto-redirects old URL, but update all hardcoded links

### 3. Consumer Projects (cc-deck, ~15 references)

| Location | Change |
|----------|--------|
| `CONTRIBUTING.md` | `/sdd:*` command references to `/spex:*` |
| `.claude/commands/speckit.*.md` | `{Skill: sdd:*}` invocations to `spex:*` |
| `.claude/settings.local.json` | Script path permissions (sdd-init.sh, etc.) |
| `.specify/sdd-traits.json` | Rename to `spex-traits.json` |
| Build manifests and docs | `- name: sdd` to `- name: spex` |
| `cc-deck-build.yaml` | Plugin name reference |
| Antora docs (4 .adoc files) | Plugin name in examples |

### 4. Plugin Root Directory Rename

`sdd/` to `spex/` inside the repo. This affects:
- `plugin.json` paths and plugin root references
- All hook script paths in consumer `settings.local.json` files
- Init script references (`sdd-init.sh` path becomes `spex/scripts/spex-init.sh`)
- Trait script references (`sdd-traits.sh` path becomes `spex/scripts/spex-traits.sh`)
- CLAUDE.md project structure documentation

### 5. Parent Directory Rename

`cc-superpowers-sdd/` to `cc-superpowers-spex/`

### 6. Project Documentation

- `CLAUDE.md`: Update all `sdd` references to `spex`
- `MEMORY.md` and memory files: Update references
- Historical `specs/` files: **Leave as-is** (frozen history)

### 7. Repo-Root Files (not yet listed)

These files outside `sdd/` also reference "sdd" and need updating:

| File | Type of reference |
|------|-------------------|
| `.claude/commands/speckit.implement.md` | `{Skill: sdd:*}` invocation |
| `.claude/commands/speckit.specify.md` | `{Skill: sdd:*}` invocation |
| `.claude/commands/speckit.plan.md` | `{Skill: sdd:*}` invocation |
| `.claude-plugin/marketplace.json` | Plugin name/description |
| `README.md` | Project name, command examples |
| `CLAUDE.md` | Project structure, trait refs |
| `TESTING.md` | Test instructions |
| `Makefile` | Build/test targets |
| `.gitignore` | Path patterns |
| `.specify/memory/constitution.md` | Project identity |
| `docs/smoke-test.md` | Test commands |
| `docs/design.md` | Architecture refs |
| `docs/plugin-schema.md` | Schema examples |
| `docs/upstream-sync-strategy.md` | Sync refs |
| `examples/todo-app/WALKTHROUGH.md` | Example commands |
| `examples/todo-app/README.md` | Example commands |
| `CHANGELOG.md` | Historical, but update header/title |

**Skip** (historical brainstorm docs): `brainstorm/02-*.md`, `brainstorm/03-*.md`, `brainstorm/worktrees-trait.md`

### 8. Hook XML Tags

The hook scripts emit XML tags like `<sdd-context>`, `<sdd-configured>`, `<sdd-initialized>`, `<sdd-init-command>`, `<sdd-traits-command>`. These need renaming to `<spex-context>`, `<spex-configured>`, etc. Consumers that parse these tags must also update.

## Decisions (resolved)

1. **Methodology name**: "SDD" (Spec-Driven Development) stays as the methodology name in prose. Only the command prefix and tooling names change to `spex`.
2. **`using-superpowers` skill**: References to "SDD methodology" in prose stay as-is. Only `sdd:` command/skill prefixes change.
3. **Migration**: `spex-init.sh` must detect old `sdd-traits.json` and auto-migrate (backwards compatibility for a transition period).
4. **Brainstorm docs**: Leave as-is (frozen planning artifacts, like specs/).
5. **CHANGELOG.md**: Leave as-is (historical record).

## Execution Order

1. Rename inside the plugin repo first (bulk find-replace `sdd:` to `spex:`, rename scripts)
2. Test the plugin loads and commands work
3. Rename the GitHub repo
4. Update all consumer projects (cc-deck and any others)
5. Update any Claude Code marketplace listing if applicable

## Command Mapping

| Old | New |
|-----|-----|
| `/sdd:brainstorm` | `/spex:brainstorm` |
| `/sdd:evolve` | `/spex:evolve` |
| `/sdd:help` | `/spex:help` |
| `/sdd:init` | `/spex:init` |
| `/sdd:review-code` | `/spex:review-code` |
| `/sdd:review-plan` | `/spex:review-plan` |
| `/sdd:review-spec` | `/spex:review-spec` |
| `/sdd:traits` | `/spex:traits` |
| `/sdd:verify` | `/spex:verify` |
| `/sdd:worktree` | `/spex:worktree` |

## Script Renaming

| Old | New |
|-----|-----|
| `sdd-init.sh` | `spex-init.sh` |
| `sdd-traits.sh` | `spex-traits.sh` |
| `sdd-traits.json` | `spex-traits.json` |
