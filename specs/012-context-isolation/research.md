# Research: Context Isolation for Workflow Transitions

**Date**: 2026-04-03
**Feature**: 012-context-isolation

## Research Topics

### 1. Spec-kit Branch Resolution API

**Decision**: Use `check-prerequisites.sh --json --paths-only` for branch-to-spec resolution in spex skills.

**Rationale**: This is the same script spec-kit's own commands use internally. It resolves the current branch name via `common.sh:get_current_branch()`, then finds the matching spec directory via `find_feature_dir_by_prefix()`. The `--json --paths-only` flag returns a minimal JSON payload with `FEATURE_SPEC`, `FEATURE_DIR`, etc.

**Alternatives considered**:
- Inline branch parsing in each skill (rejected: duplicates logic, fragile)
- Using `common.sh` functions directly (rejected: requires sourcing bash, can't run from skill markdown)
- Custom resolution script (rejected: unnecessary when check-prerequisites.sh already does this)

### 2. Claude Code `context: fork` in Plugin Skills

**Decision**: Use the Agent tool with `context: fork`-style isolation for ship pipeline stages, rather than `context: fork` in skill frontmatter.

**Rationale**: Plugin skills have limitations with `context: fork` in frontmatter (hooks, mcpServers, and permissionMode are ignored for plugin subagents). The ship skill can achieve the same isolation by using the Agent tool to spawn subagents for implementation and review stages, passing file paths as context.

**Alternatives considered**:
- `context: fork` in frontmatter (rejected: plugin limitations, would fork entire skill execution)
- `/compact` between stages (rejected: lossy, imprecise)
- `/clear` programmatically (rejected: not available programmatically)
- Separate `claude` CLI sessions (rejected: loses interactive capabilities)

### 3. Overlay Size Constraints

**Decision**: Context clear warnings fit within the 30-line overlay limit.

**Rationale**: Each warning is approximately 5-6 lines of markdown. The existing overlays have room for this addition. The `speckit.plan.append.md` overlay is currently ~30 lines; the warning can be appended without exceeding reasonable limits. The `speckit.implement.append.md` overlay is ~14 lines; plenty of room.

**No alternatives needed**: Constraint easily satisfied.
