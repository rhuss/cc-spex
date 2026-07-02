# Feature Specification: Replace find calls with plugin root references

**Feature Branch**: `033-plugin-root-refs`  
**Created**: 2026-07-02  
**Status**: Draft  
**Input**: Brainstorm 29 - Replace find calls with plugin root references

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Script resolution uses direct path (Priority: P1)

When a spex extension command runs, it locates helper scripts via the plugin root path injected by the context hook rather than searching the filesystem with `find`. The command executes the same script as before but resolves it instantly through a known path.

**Why this priority**: This is the core change. Every command that calls a helper script benefits from direct path resolution. It eliminates filesystem traversal and removes the `~/.claude` path assumption.

**Independent Test**: Can be tested by running any affected command (e.g., `/speckit-spex-flow-state`) and verifying the correct script executes without `find` being invoked.

**Acceptance Scenarios**:

1. **Given** a command file that previously used `find ~/.claude -name 'spex-flow-state.sh' 2>/dev/null | head -1`, **When** the command executes, **Then** it resolves the script path using the `<plugin-root>` value from the system reminder instead of filesystem search.
2. **Given** the plugin root path is `/Users/example/.claude/plugins/cache/spex-plugin/spex/5.8.0`, **When** a command references `<PLUGIN_ROOT>/scripts/spex-flow-state.sh`, **Then** the full path `/Users/example/.claude/plugins/cache/spex-plugin/spex/5.8.0/scripts/spex-flow-state.sh` is used.

---

### User Story 2 - All 16 find patterns replaced consistently (Priority: P1)

All 16 occurrences of the `find ~/.claude -name '...' 2>/dev/null | head -1` pattern across the following 11 command files are replaced with the `<PLUGIN_ROOT>/scripts/...` reference pattern. The replacement follows the same convention already established in the collab extension commands (phase-manager, triage).

**Affected files** (occurrence count in parentheses):

1. `spex/extensions/spex/commands/speckit.spex.ship.md` (2)
2. `spex/extensions/spex/commands/speckit.spex.submit.md` (3)
3. `spex/extensions/spex/commands/speckit.spex.finish.md` (2)
4. `spex/extensions/spex/commands/speckit.spex.brainstorm.md` (1)
5. `spex/extensions/spex/commands/speckit.spex.flow-state.md` (1)
6. `spex/extensions/spex/commands/speckit.spex.smoke-test.md` (1)
7. `spex/extensions/spex/commands/speckit.spex-detach.detach.md` (1)
8. `spex/extensions/spex-gates/commands/speckit.spex-gates.review-code.md` (2)
9. `spex/extensions/spex-gates/commands/speckit.spex-gates.review-plan.md` (1)
10. `spex/extensions/spex-gates/commands/speckit.spex-gates.review-spec.md` (1)
11. `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md` (1)

Note: `speckit.spex.ship.md` already uses `<PLUGIN_ROOT>` for one script reference but still has two `find` patterns that need replacement.

**Why this priority**: Consistency across the codebase. Partial migration leaves the codebase in a mixed state where some commands use the old pattern and others use the new one.

**Independent Test**: Can be verified by searching the affected command files for any remaining `find ~/.claude` patterns and confirming zero matches.

**Acceptance Scenarios**:

1. **Given** the 11 command files listed above, **When** all replacements are applied, **Then** `grep -r "find ~/.claude" spex/extensions/` returns zero matches in command files.
2. **Given** a command file that references multiple scripts (e.g., submit references 3 scripts), **When** the replacements are applied, **Then** each script reference uses the `<PLUGIN_ROOT>` pattern independently.

---

### User Story 3 - Standard preamble added where missing (Priority: P2)

Command files that do not already have the plugin root extraction preamble get it added. The preamble instructs the AI agent to extract the plugin root path from the `<plugin-root>` tag in the `<spex-context>` system reminder.

**Why this priority**: Without the preamble, the `<PLUGIN_ROOT>` placeholder has no definition, and the agent would not know how to resolve it. Commands that already have the preamble (from prior collab extension work) do not need modification.

**Independent Test**: Can be verified by reading each affected command file and confirming the preamble is present before any `<PLUGIN_ROOT>` reference.

**Acceptance Scenarios**:

1. **Given** a command file that previously had no plugin root extraction instructions, **When** the replacement is applied, **Then** the file contains the standard preamble instructing extraction from the system reminder.
2. **Given** a command file that already has the preamble (e.g., phase-manager), **When** the refactor runs, **Then** the existing preamble is preserved and no duplicate is added.

---

### Edge Cases

- What happens when a command file uses `find` for a script that does not exist under `scripts/`? The script path must be validated against the actual directory structure.
- What if a command references the same script multiple times? Each reference should be replaced independently, using the same `<PLUGIN_ROOT>` variable.
- What if the `<spex-context>` system reminder is absent (e.g., command invoked outside the plugin context)? The preamble instructions should note that `<plugin-root>` is required and the command cannot proceed without it.
- What if a command file already has a partial migration (uses `<PLUGIN_ROOT>` for some references but `find` for others, as in `ship.md`)? Replace only the remaining `find` patterns; preserve the existing `<PLUGIN_ROOT>` references and avoid duplicating the preamble.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: All `find ~/.claude -name 'X' 2>/dev/null | head -1` patterns in extension command files MUST be replaced with `<PLUGIN_ROOT>/scripts/X` references.
- **FR-002**: Each affected command file MUST include the standard plugin root extraction preamble if not already present.
- **FR-003**: The replacement MUST cover all 16 occurrences across the 11 files identified in scope.
- **FR-004**: The replacement MUST NOT change the script that gets executed, only how its path is resolved.
- **FR-005**: Commands that already use the `<PLUGIN_ROOT>` pattern (phase-manager, triage) MUST NOT be modified.
- **FR-006**: The `<PLUGIN_ROOT>` placeholder in command files MUST reference the path extracted from the `<plugin-root>` tag in the `<spex-context>` system reminder.

### Key Entities

- **Extension Command File**: A markdown skill file under `spex/extensions/` that contains instructions for the AI agent, including shell commands with script references.
- **Plugin Root Path**: The filesystem path to the spex plugin installation directory, injected by the context hook as `<plugin-root>` in the system reminder.
- **Helper Script**: A shell script under the plugin's `scripts/` directory that is called by extension commands at runtime.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Zero `find ~/.claude` patterns remain in extension command files after the change.
- **SC-002**: All 11 affected command files use the `<PLUGIN_ROOT>/scripts/` pattern for script references.
- **SC-003**: All affected commands produce identical behavior before and after the change when run in Claude Code.
- **SC-004**: No new `find` patterns are introduced by the change.

## Out of Scope

- **Context hook changes**: The `context-hook.py` that injects the `<plugin-root>` tag is not modified by this feature. It already provides the necessary data.
- **Script content changes**: The helper scripts themselves (e.g., `spex-flow-state.sh`, `spex-ship-state.sh`) are not modified. Only the path resolution mechanism in command files changes.
- **Non-command-file find patterns**: Any `find` patterns in shell scripts, Python hooks, or other non-command files are not in scope.
- **Collab extension commands**: `phase-manager` and `triage` already use the `<PLUGIN_ROOT>` pattern and are excluded from this change.

## Assumptions

- The `<plugin-root>` tag is always present in the `<spex-context>` system reminder when spex commands execute. This is guaranteed by the context hook.
- All referenced scripts exist under the `scripts/` directory of the plugin root. No scripts are located elsewhere.
- The two commands already using the `<PLUGIN_ROOT>` pattern (phase-manager, triage) serve as the canonical reference implementation for the replacement pattern.
- This change only affects Claude Code command files (markdown). No shell scripts, Python code, or configuration files need modification.
