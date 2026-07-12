# Feature Specification: Unified Harness Marker Syntax

**Feature Branch**: `039-robust-harness-markers`  
**Created**: 2026-07-12  
**Status**: Draft  
**Input**: User description: "Replace the fragile two-mechanism adaptation system (HTML-comment markers + prose-matching inline substitutions) with a unified `{harness:X}` token syntax for both inline and block replacements."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Adaptation script replaces unified markers correctly (Priority: P1)

A developer runs the adaptation script against neutral command files that use the new `{harness:key}` token syntax. The script replaces all inline tokens and block markers with harness-specific content from the mapping table, stripping all marker syntax from the output. The adapted files contain zero leftover `{harness:` references.

**Why this priority**: This is the core mechanism. If unified markers don't work, nothing else matters.

**Independent Test**: Run `spex-adapt-commands.sh claude .specify/extensions spex/scripts/adapters` on command files containing `{harness:key}` tokens and `{harness:key}...{/harness:key}` blocks. Verify all markers are replaced and `grep '{harness:' adapted-files` returns 0 matches.

**Acceptance Scenarios**:

1. **Given** a command file with an inline token `{harness:no-interactive-prompts}`, **When** the adaptation script runs with the Claude mapping table, **Then** the token is replaced with the mapped value (e.g., `do NOT use AskUserQuestion`) and no `{harness:` text remains.
2. **Given** a command file with a block marker `{harness:agent-teams}...{/harness:agent-teams}`, **When** the adaptation script runs with the Claude mapping table, **Then** the entire block (including both marker lines and content between them) is replaced with the mapped section content.
3. **Given** a command file with a token that has no mapping entry, **When** the adaptation script runs, **Then** the token is replaced with the `fallback_note` template text explaining the limitation.
4. **Given** the adaptation script runs twice on the same files (idempotency), **When** comparing the output of both runs, **Then** the files are byte-identical.

---

### User Story 2 - Command files use unified marker syntax (Priority: P1)

All 7 command files that previously used HTML-comment markers or were referenced by inline prose-matching substitutions now use the unified `{harness:key}` syntax. Source files contain zero HTML-comment capability markers and zero prose strings that rely on exact text matching.

**Why this priority**: Equally critical as US1. The adaptation script needs files in the new format to process.

**Independent Test**: Run `grep -c '<!-- harness:' spex/extensions/*/commands/*.md` and verify 0 matches. Run `grep -c '{harness:' spex/extensions/*/commands/*.md` and verify at least 15 inline tokens and 5 block marker pairs exist across 7 files.

**Acceptance Scenarios**:

1. **Given** the 4 command files that currently contain HTML-comment markers (`deep-review.run.md`, `teams.orchestrate.md`, `teams.research.md`, `worktrees.manage.md`), **When** rewritten, **Then** all `<!-- harness:X -->...<!-- /harness:X -->` blocks are replaced with `{harness:X}...{/harness:X}` blocks.
2. **Given** the 7 command files referenced by the 15 inline substitution entries (`ship.md`, `stamp.md`, `verify.md`, `teams.implement.md`, `teams.orchestrate.md`, `teams.research.md`, `deep-review.run.md`), **When** rewritten, **Then** all prose phrases that were targets of inline substitutions are replaced with `{harness:key}` tokens.
3. **Given** all command files after rewrite, **When** scanning for legacy markers, **Then** zero `<!-- harness:` strings and zero prose phrases from the old `inline` array remain.

---

### User Story 3 - Mapping tables use unified token format (Priority: P1)

All per-harness mapping tables (Claude, Codex, OpenCode) use a single `"tokens"` object instead of separate `"inline"` and `"sections"` fields. The mapping table version is bumped to `"2.0.0"`.

**Why this priority**: The mapping tables are the data source for the adaptation script. They must match the new marker format.

**Independent Test**: Validate each `command-map.json` with `jq '.tokens | keys | length'` and verify the expected token count. Verify no `"inline"` or `"sections"` keys remain.

**Acceptance Scenarios**:

1. **Given** the Claude mapping table, **When** inspected, **Then** it contains a `"tokens"` object with entries for all 15 former inline substitutions and all 5 former section replacements, and no `"inline"` or `"sections"` keys exist.
2. **Given** the Codex mapping table, **When** inspected, **Then** it uses the same `"tokens"` structure and its version is `"2.0.0"`.
3. **Given** the OpenCode mapping table, **When** inspected, **Then** it uses the same `"tokens"` structure (may be empty) and its version is `"2.0.0"`.

---

### User Story 4 - Debug mode traces marker processing (Priority: P2)

A developer runs the adaptation script with `--debug` to see which markers were found and what they were replaced with. Debug output goes to stderr so it doesn't pollute `--dry-run` stdout output.

**Why this priority**: Debugging aid, not core functionality. Important for maintainability but not blocking.

**Independent Test**: Run `spex-adapt-commands.sh --debug claude .specify/extensions spex/scripts/adapters 2>debug.log` and verify `debug.log` contains per-marker trace lines.

**Acceptance Scenarios**:

1. **Given** a command file with 3 markers, **When** the script runs with `--debug`, **Then** stderr contains one trace line per marker showing: file name, marker key, and whether it was replaced or fell back.
2. **Given** `--debug` combined with `--dry-run`, **When** the script runs, **Then** stdout contains the unified diff (dry-run output) and stderr contains the debug trace lines, with no mixing.

---

### User Story 5 - Post-adaptation validation catches leftover markers (Priority: P2)

After adaptation completes, the script automatically scans all processed files for leftover `{harness:` markers and warns if any remain. This catches mapping table gaps before they reach users.

**Why this priority**: Safety net. Prevents silent failures where a token has no mapping entry and no fallback was applied.

**Independent Test**: Remove one entry from the mapping table, run the script, and verify it outputs a warning listing the unmapped marker.

**Acceptance Scenarios**:

1. **Given** all markers have matching entries in the mapping table, **When** adaptation completes, **Then** the validation passes silently (no warnings).
2. **Given** a marker `{harness:unknown-key}` with no mapping entry and no `fallback_note` configured, **When** adaptation completes, **Then** the script outputs a warning to stderr listing the file and unmapped marker key.

---

### Edge Cases

- What happens when a `{harness:key}` token appears inside a fenced code block (triple backticks)? It should be replaced normally (code blocks in command files are instructional, not literal code).
- What happens when `{/harness:key}` appears without a matching opening `{harness:key}`? The script should warn to stderr and skip (do not crash). Exit code remains 0 (warning only).
- What happens when `{harness:key}` opening appears without a matching `{/harness:key}` closer? The script should error with a clear message identifying the file and unclosed marker, and exit with code 1.
- What happens when a token value in the mapping table contains `{harness:` as a literal substring (e.g., documentation about the marker syntax)? The post-adaptation validator should not flag these as leftover markers. Use the validator only on the final output, where adapted content should never contain the marker syntax.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The adaptation script MUST support `{harness:key}` inline tokens, replacing each occurrence with the value from the mapping table's `tokens[key]`.
- **FR-002**: The adaptation script MUST support `{harness:key}...{/harness:key}` block markers, replacing the entire block (opening marker, content, closing marker) with the value from `tokens[key]`.
- **FR-003**: Both inline tokens and block markers MUST use the same `tokens` lookup in the mapping table. There is no separate namespace for blocks vs inline.
- **FR-004**: All markers (inline and block) MUST be stripped completely after adaptation. No trace markers, no harness-specific tags, no HTML comments remain in adapted output.
- **FR-005**: The mapping table schema MUST use a single `"tokens"` object replacing the former `"inline"` array and `"sections"` object.
- **FR-006**: The `"inline"` and `"sections"` keys MUST NOT exist in any mapping table after migration.
- **FR-007**: When a marker key has no entry in the mapping table, the script MUST apply the `fallback_note` template with `{harness}` and `{fallback_text}` placeholders filled.
- **FR-008**: The script MUST support a `--debug` flag that outputs per-marker trace information to stderr.
- **FR-009**: After processing all files, the script MUST scan adapted output for leftover `{harness:` markers and warn on stderr if any remain.
- **FR-010**: All 4 command files with HTML-comment markers MUST be converted to `{harness:key}...{/harness:key}` block syntax.
- **FR-011**: All 7 command files referenced by the 15 inline substitution entries MUST be converted to use `{harness:key}` inline tokens.
- **FR-012**: The adaptation script MUST remain idempotent, atomic (temp directory + move), and support `--dry-run`.
- **FR-013**: All 3 mapping tables (Claude, Codex, OpenCode) MUST be updated to the `"tokens"` format with version `"2.0.0"`.

### Key Entities

- **Inline Token**: A `{harness:key}` placeholder within flowing text that gets replaced with a harness-specific phrase.
- **Block Marker**: A `{harness:key}...{/harness:key}` pair wrapping multi-line content that gets replaced as a unit.
- **Tokens Object**: The unified key-value map in `command-map.json` that provides replacement content for both inline tokens and block markers.
- **Mapping Table**: A per-harness JSON file (`command-map.json`) containing the `tokens` object, `fallback_note` template, harness identifier, and version.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Zero `<!-- harness:` HTML-comment markers remain in any command source file after migration.
- **SC-002**: Zero prose-matching `"inline"` entries remain in any mapping table after migration.
- **SC-003**: After running the adaptation script with the Claude mapping table, `grep '{harness:' adapted-files` returns 0 matches (all markers replaced).
- **SC-004**: The adaptation script completes in under 5 seconds for all extension commands (same performance target as feature 038).
- **SC-005**: Running the adaptation script twice produces byte-identical output (idempotency preserved).
- **SC-006**: `make release` passes after all changes (schema validation + integration tests).

## Smoke Test

1. Run `spex-adapt-commands.sh --dry-run claude .specify/extensions spex/scripts/adapters` and verify the diff shows all `{harness:key}` tokens being replaced with Claude-specific content, with no leftover markers.
2. Run `spex-adapt-commands.sh --dry-run codex .specify/extensions spex/scripts/adapters` and verify the diff shows Codex-appropriate replacements and fallback notes for unsupported capabilities.
3. Run `spex-adapt-commands.sh --debug claude .specify/extensions spex/scripts/adapters 2>debug.log` and verify `debug.log` contains trace lines for each processed marker.

## Out of Scope

- Creating mapping tables for new harnesses beyond the existing 3 (Claude, Codex, OpenCode).
- Changing the adaptation script's overall architecture (temp directory approach, file discovery, setup.yml integration).
- Modifying command file content beyond marker syntax changes (no behavioral rewrites).
- Upstream spec-kit changes.

## Clarifications

### Session 2026-07-12

- Q: Should token keys follow a specific naming convention? → A: Yes, lowercase kebab-case matching `[a-z][a-z0-9-]*`, consistent with the old capability marker names.
- Q: Can the same token key be used as an inline token in one file and a block opener in another? → A: Yes. The same `tokens[key]` value serves both uses. For inline, it replaces the token. For blocks, it replaces the entire block content (opening marker through closing marker).

## Assumptions

- Feature 038 (neutral command vocabulary) is merged and all command files currently use the two-mechanism system (HTML-comment markers + prose-matching inline substitutions).
- The `spex-adapt-commands.sh` script, `setup.yml` integration, and per-harness mapping tables all exist and work correctly with the current format.
- The 15 inline substitution entries and 5 section marker names in the Claude mapping table represent the complete set of harness-specific adaptations needed.
- Multi-line token values are stored as JSON strings with `\n` escape sequences (no external file references needed at this scale).
- The `--debug` flag outputs to stderr to avoid polluting `--dry-run` stdout.
