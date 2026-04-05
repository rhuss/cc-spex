# Research: Upgrade speckit commands to Agent Skills format

**Date**: 2026-04-05

## Decision 1: Version parsing strategy

**Decision**: Extract semver from `specify version` output using grep/sed to find the `CLI Version` line and parse `X.Y.Z`.

**Rationale**: The `specify version` command outputs decorated ASCII art with a table containing `CLI Version    X.Y.Z`. Parsing this with `grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1` reliably extracts the version regardless of formatting changes to the ASCII art.

**Alternatives considered**:
- `specify --version` flag: Not available in current CLI
- Checking `init-options.json` speckit_version: Only updated after `specify init` runs, not reliable for pre-init version gate
- Feature detection (checking if `specify init` creates skills/): Wasteful, requires actual init run

## Decision 2: Semver comparison in Bash

**Decision**: Use a simple numeric comparison by splitting version into major.minor.patch components and comparing sequentially.

**Rationale**: No need for external semver libraries. The gate only checks `>= 0.5.0`, which is a straightforward numeric comparison. POSIX-compatible Bash can handle this.

**Alternatives considered**:
- `sort -V`: Not available on all platforms
- Python one-liner: Adds dependency
- Just check major >= 1 || (major == 0 && minor >= 5): Simple and sufficient

## Decision 3: Overlay directory structure

**Decision**: Mirror the skills directory structure in overlays: `spex/overlays/<trait>/skills/<skill-name>/SKILL.{append,prepend}.md`

**Rationale**: Consistent with upstream format. The mapping is unambiguous: overlay path mirrors target path. Enables both prepend and append operations.

**Alternatives considered**:
- Flat naming (`speckit-specify.append.md`): Simpler but inconsistent with skills structure
- Keep `commands/` subdirectory with rename: Confusing since targets are now in `skills/`

## Decision 4: Prepend implementation

**Decision**: For `SKILL.prepend.md`, insert content after YAML frontmatter (if present) but before the main skill content. Use a sentinel marker `<!-- SPEX-PREPEND:trait-name -->` for idempotency.

**Rationale**: SKILL.md files from upstream may have YAML frontmatter (between `---` markers). Prepending before frontmatter would break the file. Inserting after frontmatter but before content preserves file validity while allowing traits to inject early instructions.

**Alternatives considered**:
- Always prepend at line 1: Breaks YAML frontmatter
- Use a different sentinel format: Consistency with existing `<!-- SPEX-TRAIT:name -->` pattern is better

## Decision 5: Deprecated overlay handling

**Decision**: Migrate deprecated overlays (teams-spec, teams-vanilla) to the new directory structure alongside active overlays.

**Rationale**: These files are still referenced by the trait system for backward compatibility. Removing them now would break users who haven't migrated their trait config. They should be migrated alongside everything else.

**Alternatives considered**:
- Remove deprecated overlays entirely: Would break backward compatibility
- Leave them in old format: Inconsistent, would require dual-path support in spex-traits.sh

## Impact Assessment: Files Requiring Changes

### Scripts (core logic changes)
| File | Change Type | Scope |
|------|-------------|-------|
| `spex/scripts/spex-init.sh` | Major rewrite | Version gate, readiness check, migration cleanup, gitignore |
| `spex/scripts/spex-traits.sh` | Major rewrite | Overlay mapping, prepend support, sentinel handling |
| `spex/scripts/hooks/pretool-gate.py` | Update | Command name mapping dictionary |
| `spex/scripts/hooks/context-hook.py` | Update | Command URL mappings |

### Overlay files (rename + restructure)
| Count | Source | Target |
|-------|--------|--------|
| 5 | `_ship-guard/commands/speckit.X.append.md` | `_ship-guard/skills/speckit-X/SKILL.append.md` |
| 1 | `deep-review/commands/speckit.X.append.md` | `deep-review/skills/speckit-X/SKILL.append.md` |
| 3 | `superpowers/commands/speckit.X.append.md` | `superpowers/skills/speckit-X/SKILL.append.md` |
| 1 | `teams-spec/commands/speckit.X.append.md` | `teams-spec/skills/speckit-X/SKILL.append.md` |
| 2 | `teams-vanilla/commands/speckit.X.append.md` | `teams-vanilla/skills/speckit-X/SKILL.append.md` |
| 2 | `teams/commands/speckit.X.append.md` | `teams/skills/speckit-X/SKILL.append.md` |
| 3 | `worktrees/commands/speckit.X.append.md` | `worktrees/skills/speckit-X/SKILL.append.md` |

### Skills (text reference updates)
| File | Reference Count |
|------|----------------|
| `spex/skills/ship/SKILL.md` | 25+ |
| `spex/skills/brainstorm/SKILL.md` | 20+ |
| `spex/skills/spec-kit/SKILL.md` | 20+ |
| `spex/skills/using-superpowers/SKILL.md` | 15+ |
| `spex/skills/review-spec/SKILL.md` | 8+ |
| `spex/skills/evolve/SKILL.md` | 8+ |
| `spex/skills/worktree/SKILL.md` | 6+ |
| `spex/skills/review-code/SKILL.md` | 2+ |
| `spex/skills/deep-review/SKILL.md` | 2+ |
| `spex/skills/verification-before-completion/SKILL.md` | 2+ |
| `spex/skills/review-plan/SKILL.md` | 3+ |

### Commands (text reference updates)
| File | Reference Count |
|------|----------------|
| `spex/commands/init.md` | 1 |

### Documentation (text reference updates)
| File | Reference Count |
|------|----------------|
| `README.md` | 21+ |
| `CHANGELOG.md` | 1 |
| `docs/smoke-test.md` | 10+ |
| `docs/plugin-schema.md` | 1 |
| `spex/docs/help.md` | 15+ |
| `spex/docs/tutorial-full.md` | 3 |
| `spex/docs/tutorial-team.md` | 2 |

### Config/Meta
| File | Change |
|------|--------|
| `.gitignore` | Pattern update |
| `.specify/memory/constitution.md` | Naming section update |
| `.claude-plugin/marketplace.json` | Version bump to 4.0.0 |
| `spex/.claude-plugin/plugin.json` | Version bump to 4.0.0 |
