# Research: Replace find calls with plugin root references

## Decision: Path Resolution Strategy

**Decision**: Use the `<PLUGIN_ROOT>` placeholder pattern already established in the collab extension commands.

**Rationale**: The pattern is proven, used in production commands (phase-manager, triage), and aligns with the constitution's "Plugin root detection" constraint. It eliminates filesystem traversal and removes the `~/.claude` path assumption.

**Alternatives considered**:
- **Environment variable injection**: Set `$SPEX_PLUGIN_ROOT` in the shell environment. Rejected because command files are markdown interpreted by AI agents, not shell scripts. Environment variables are not reliably available.
- **Config file lookup**: Store the plugin root in a config file. Rejected because the context hook already provides this data in every prompt, making a config file redundant.

## Decision: Script Path Structure

**Decision**: Reference scripts at their actual relative paths under the plugin root.

**Rationale**: Most scripts are at `scripts/<name>.sh`, but `spex-detach.sh` is at `scripts/bash/spex-detach.sh`. Using actual paths prevents breakage.

**Alternatives considered**:
- **Move all scripts to a flat directory**: Rejected because it would change the existing directory structure, which is out of scope for this refactor.
- **Symlinks**: Rejected as unnecessary complexity.

## Decision: Preamble Placement

**Decision**: Add "Step 0: Resolve Plugin Root" section near the top of each command file's execution flow, before any script references.

**Rationale**: Follows the convention in phase-manager and triage. The preamble is a natural first step that establishes context for all subsequent script calls.

**Alternatives considered**:
- **Inline the path at each usage site**: Rejected because repeated extraction instructions are verbose and error-prone.
- **Add to a shared "common setup" file**: Rejected because each command must be self-contained per the Skill Autonomy constitution principle.
