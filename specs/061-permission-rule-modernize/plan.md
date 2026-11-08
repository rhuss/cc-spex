# Implementation Plan: Modernize Generated Permission Rules

**Branch**: `061-permission-rule-modernize` | **Date**: 2026-11-03 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/061-permission-rule-modernize/spec.md`

## Summary

spex writes `Bash(*)`, `Read(*)`, `Edit(*)` and `Write(*)` for the YOLO level, which current Claude Code releases flag. A new script, `spex/scripts/spex-permissions.sh`, owns all Claude permission writes. It has two subcommands. `migrate` rewrites the four legacy rules to their bare names in the project settings files. `apply` merges a caller-supplied rule list into a settings file without reordering it, then migrates. Every init entry point calls the script: `setup.yml` (permission step plus a new unconditional migration step), `spex-init.sh --refresh/--update`, and the init skill's Step 2 (which replaces its prose jq merge). The setup report relays the new step's output.

## Technical Context

**Language/Version**: POSIX sh (`#!/bin/sh`, like `spex-setup-report.sh` and `spex-apply-extensions.sh`)

**Primary Dependencies**: `jq` (already required by init)

**Storage**: `.claude/settings.json`, `.claude/settings.local.json` (JSON files in the project)

**Testing**: Bash test script `tests/test_permissions.sh` in the style of `tests/test_apply_extensions.sh` (temp project dirs, `assert_eq`, PASS/FAIL counters), wired into a new `make test-permissions` target

**Target Platform**: macOS and Linux shells used by Claude Code, Codex and the `specify` workflow engine

**Project Type**: CLI plugin (Markdown skills + shell scripts)

**Performance Goals**: N/A (two small files per run)

**Constraints**: Never damage settings files that hold hooks from other tools; a no-op run must leave exact bytes; messages go to stderr so the workflow engine captures them for `spex-setup-report.sh`

**Scale/Scope**: 1 new script, 1 new test file, edits to `setup.yml`, `spex-init.sh`, `spex-setup-report.sh`, `spex/skills/init/SKILL.md`, `README.md`, `spex/docs/help.md`, `Makefile`

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-Guided Development | Pass | Spec 061 with clarifications and review fixes precedes code |
| II. Extension Architecture | Pass | No extension changes; init is a standalone skill plus scripts |
| III. Extension Composability | Pass | Migration is independent of enabled extensions |
| IV. Quality Gates | Pass | Pipeline runs review-plan and review-code |
| V. Naming Discipline | Pass | Script follows `spex-<noun>.sh`; no command renames |
| VI. Skill Autonomy | Pass | Skill calls one script with fixed arguments |
| VII. State as Scripts | Pass (improves) | Removes the prose jq merge from SKILL.md Step 2; all settings writes go through one script |
| Constraint: canonical scripts in `spex/scripts/` | Pass | No extension command uses the script, so no `sync-scripts` entry is needed |
| Constraint: no compiled artifacts | Pass | sh + jq only |

Post-design re-check: unchanged, all pass.

## Project Structure

### Documentation (this feature)

```text
specs/061-permission-rule-modernize/
├── spec.md
├── plan.md              # this file
├── research.md          # decisions
├── data-model.md        # settings file shape and rewrite rules
├── quickstart.md        # validation scenarios
├── contracts/
│   └── spex-permissions-cli.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
spex/scripts/spex-permissions.sh      # NEW: migrate | apply
spex/scripts/spex-init.sh             # do_refresh, do_update call migrate
spex/scripts/spex-setup-report.sh     # relay new step id
spex/setup.yml                        # claude-permissions uses apply; new migrate-permissions step
spex/skills/init/SKILL.md             # Step 1 refresh text, Step 2 permissions via script, Step 4 relay
tests/test_permissions.sh             # NEW
tests/test_workflow_setup.sh          # setup.yml wiring cases
Makefile                              # test-permissions target
README.md, spex/docs/help.md          # refresh migration docs
```

**Structure Decision**: Single canonical script under `spex/scripts/`, called by path relative to the caller: `$(dirname "$0")/spex-permissions.sh` from `spex-init.sh`, `$SOURCE/scripts/spex-permissions.sh` from `setup.yml`, `<scripts>/spex-permissions.sh` from the skill (same `<scripts>` directory Step 2 already uses).

## Design

### `migrate` (FR-004 to FR-012, FR-009a, FR-011a)

1. For each of `.claude/settings.json` and `.claude/settings.local.json` under `--root` (default `$PWD`) that exists:
2. Parse with `jq`. Invalid JSON: `WARNING: <file> is not valid JSON; permission rules not migrated` and continue.
3. Shape guard in jq: top level object, `permissions` object, `permissions.allow` array; anything else is a silent no-op.
4. Compute in one jq program: the rewritten list (exact-string map of the four legacy rules), the list of `old -> new` pairs (first occurrence order, each once), and, when pairs is non-empty, deduplicate only the four bare names keeping the first occurrence. Non-string entries pass through.
5. No pairs: do not write (exact bytes kept).
6. Pairs: write `.permissions.allow = $new` with `jq` default 2-space output into a temp file in the directory of the resolved target, then `mv` it onto the resolved target. Resolving a symlink keeps the link in place. Preserve the target's file mode. On any failure, remove the temp file, print `WARNING: could not write <file>; permission rules not migrated`, and continue.
7. Print `Migrated: <relpath> permissions: Read(*) -> Read, ...` on stderr.
8. Always exit 0, except for usage errors (exit 2).

### `apply` (FR-001 to FR-003, FR-017)

`spex-permissions.sh apply [--root DIR] [--default-mode MODE] RULE...`

1. Target is `.claude/settings.json`; created as `{}` if missing (`mkdir -p .claude`). Missing `permissions`/`allow` are created; only a non-object top level/`permissions` or non-array `allow` is wrong shape.
2. Invalid JSON or wrong shape: `WARNING: <file> ...; permissions not applied` and exit 0 (today the jq-then-mv pattern would truncate the file).
3. Append each RULE not already present, keeping existing order. Set `permissions.defaultMode` when `--default-mode` is given.
4. Run `migrate_file` on the merged list so legacy rules collapse into the bare forms just added. Write via `safe_write` only when a rule was added, `defaultMode` changed or a migration happened (re-apply is byte-identical).
5. Print `Permissions configured in <file> (<n> rules added)` on stderr, with n counted after migration.

### Callers

- `setup.yml` `claude-permissions`: replace the inline jq with `sh "$SOURCE/scripts/spex-permissions.sh" apply ...`, keeping the existing per-level rule lists, with the YOLO list switched to bare `Bash`, `Read`, `Edit`, `Write`.
- `setup.yml` new step `migrate-permissions` (after `configure-permissions`, at top level, so it runs for `safe` and for every harness): `sh "$SOURCE/scripts/spex-permissions.sh" migrate`. It is a no-op without `.claude/` files.
- `spex-setup-report.sh`: add `migrate-permissions` and `claude-permissions` to the relayed step ids.
- `spex-init.sh`: `do_refresh` and `do_update` call `sh "$(dirname "$0")/spex-permissions.sh" migrate` after `install_agent_adapter`.
- `SKILL.md` Step 1: replace "Permissions are unchanged" with a sentence on the rule migration. Step 2: replace the JSON blocks and "Merge permission entries" prose with one `apply` call per level followed by `migrate` at every level (so `settings.local.json` is migrated too), showing the exact argument lists (YOLO with bare names) and a note that bare tool names allow every path. Step 4: relay `Migrated:` and `WARNING:` lines from Step 1 and Step 2 output; restart advice when `Permissions configured` reports n > 0 or any `Migrated:` line appears.

## Complexity Tracking

No violations. The `apply` subcommand goes slightly beyond "rewrite four strings". FR-003, FR-016 and FR-017 require it, because the skill's prose merge cannot preserve order or migrate deterministically.
