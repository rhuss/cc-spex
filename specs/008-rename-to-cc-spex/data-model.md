# Data Model: Rename Plugin to cc-spex

**Date**: 2026-03-27

## Entities

This feature has no new data entities. It renames existing identifiers across files.

### Rename Mapping

| Old Identifier | New Identifier | Type |
|----------------|----------------|------|
| `sdd` | `spex` | Plugin name |
| `sdd:*` | `spex:*` | Command prefix |
| `{Skill: sdd:*}` | `{Skill: spex:*}` | Skill delegation |
| `sdd-init.sh` | `spex-init.sh` | Script filename |
| `sdd-traits.sh` | `spex-traits.sh` | Script filename |
| `sdd-traits.json` | `spex-traits.json` | Config filename |
| `<sdd-*>` | `<spex-*>` | XML context tags |
| `.claude-sdd-*` | `.claude-spex-*` | Temp marker files |
| `.sdd-phase` | `.spex-phase` | Phase marker file |
| `sdd/` | `spex/` | Directory path |
| `cc-sdd` | `cc-spex` | Repo name |
| `cc-superpowers-sdd` | `cc-superpowers-spex` | Parent directory |

### Preserved Identifiers

| Identifier | Reason |
|------------|--------|
| `SDD` (in prose) | Methodology name "Spec-Driven Development" |
| `<!-- SDD-TRAIT:name -->` | Sentinel markers use methodology name |
| `SDD Plugin Constitution` | Document title uses methodology name |
