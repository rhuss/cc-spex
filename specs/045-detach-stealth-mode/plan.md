# Implementation Plan: Detach Stealth Mode

**Branch**: `045-detach-stealth-mode` | **Date**: 2026-07-21 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/045-detach-stealth-mode/spec.md`

## Summary

Replace the spex-detach extension's pr/ branch stripping mechanism with .git/info/exclude stealth mode. The new approach prevents spec files from ever being committed to the code repo by adding them to .git/info/exclude, making leaks structurally impossible. The archive subcommand is simplified and wired to the before_finish hook to copy specs to a sibling repo for version control.

## Technical Context

**Language/Version**: Bash (POSIX-compatible), Python 3 (existing spex-detach.py)
**Primary Dependencies**: `jq`, `yq`, `git`, `specify` CLI
**Storage**: .git/info/exclude (local git exclude file), filesystem (sibling specs repo)
**Testing**: `make release` (integration test suite), manual smoke tests
**Target Platform**: macOS, Linux (any system with git and bash)
**Project Type**: CLI extension (spec-kit plugin extension)
**Performance Goals**: Enable command completes in under 1 second
**Constraints**: No changes to upstream project's committed files; backward compatible (opt-in extension)
**Scale/Scope**: 6 files modified, 2 files removed, 2 files updated in docs

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-Guided Development | PASS | Following SDD workflow |
| II. Extension Architecture | PASS | Changes stay within spex-detach extension bundle |
| III. Extension Composability | PASS | Detach remains independent; other extensions unaffected |
| IV. Quality Gates | PASS | Running through ship pipeline with all gates |
| V. Naming Discipline | PASS | Using established `speckit.spex-detach.*` naming |
| VI. Skill Autonomy | PASS | Detach command skill is self-contained |
| VII. State as Scripts | PASS | Logic stays in spex-detach.py script |

## Project Structure

### Documentation (this feature)

```text
specs/045-detach-stealth-mode/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
└── tasks.md             # Phase 2 output (via /speckit-tasks)
```

### Source Code (files to change)

```text
spex/extensions/spex-detach/
├── extension.yml                              # UPDATE: new command, updated hooks
├── config-template.yml                        # UPDATE: remove obsolete sections
├── scripts/
│   ├── spex-detach.sh                         # KEEP: shim unchanged
│   └── spex-detach.py                         # REWRITE: remove detach/verify/clean-branch-name, add enable
└── commands/
    └── speckit.spex-detach.detach.md           # REWRITE: new command doc for enable/archive

.claude/skills/
├── speckit-spex-detach-detach/SKILL.md         # UPDATE: match new command doc
├── speckit-spex-brainstorm/SKILL.md            # UPDATE: detach-aware output directory logic (unchanged behavior, already works)
└── speckit-spex-submit/SKILL.md                # UPDATE: remove detach detection in Phase 2b

README.md                                       # UPDATE: detach extension description
spex/docs/help.md                               # UPDATE: detach extension description
```

**Structure Decision**: No new directories or files. This is a modification of an existing extension. The Python script is rewritten in place.

## Complexity Tracking

No constitution violations. No complexity justifications needed.
