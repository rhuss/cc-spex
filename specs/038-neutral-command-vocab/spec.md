# Feature Specification: Neutral Command Vocabulary with Per-Harness Adaptation

**Feature Branch**: `038-neutral-command-vocab`  
**Created**: 2026-07-08  
**Status**: Draft  
**Input**: User description: "Rewrite spex command/skill files to use harness-neutral vocabulary, then apply per-harness transformations via the setup workflow's adapt-commands step. This removes the upstream dependency identified in brainstorm #28."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Author writes a new extension command in neutral vocabulary (Priority: P1)

An extension author writes a spex command using generic, harness-neutral language. Instead of referencing specific tools like "use the AskUserQuestion tool" or "spawn a subagent via the Agent tool," the author describes the desired behavior in plain language: "present the user with a structured choice" or "dispatch a parallel worker with the following prompt." The command file works correctly on any harness out of the box because it contains no harness-specific references.

**Why this priority**: This is the foundational change. Every other user story depends on commands being written in neutral vocabulary first. Without this, multi-harness support requires maintaining N copies of every command.

**Independent Test**: Can be fully tested by writing a sample command in neutral vocabulary, installing spex on a Claude Code project, and verifying the command executes correctly without any adaptation step.

**Acceptance Scenarios**:

1. **Given** a newly written extension command using neutral vocabulary, **When** the command is installed via `specify extension add`, **Then** the command contains zero harness-specific tool names (AskUserQuestion, Agent, EnterWorktree, ExitWorktree, settings.json, settings.local.json, UserPromptSubmit, PreToolUse).
2. **Given** an existing extension command that currently references Claude Code tools, **When** the command is rewritten to neutral vocabulary, **Then** the behavioral intent of every instruction is preserved (same user-facing outcomes) while tool-specific references are replaced with natural language descriptions.
3. **Given** a command with complex, multi-paragraph tool-specific instructions (e.g., Agent tool dispatch with subagent types, worktree isolation, schema validation), **When** the section is rewritten, **Then** it is wrapped in capability markers (`<!-- harness:capability-name -->...<!-- /harness:capability-name -->`) that identify the section's capability requirement for the adaptation script.

---

### User Story 2 - Setup workflow adapts commands for the detected harness (Priority: P1)

A user runs the setup workflow (`specify workflow run setup.yml`) which detects their harness (Claude Code, Codex, OpenCode, or generic) and transforms neutral command vocabulary into harness-optimized instructions. For Claude Code, this means re-injecting specific tool references (AskUserQuestion, Agent tool) that improve precision. For other harnesses, it means replacing or removing sections that reference capabilities they lack.

**Why this priority**: Equally critical as P1. Neutral vocabulary alone may produce suboptimal behavior on Claude Code (where specific tool references yield better results). The adaptation step ensures each harness gets optimized instructions.

**Independent Test**: Can be tested by running the setup workflow with different `--integration` values (claude, codex, opencode) and verifying that the installed commands contain harness-appropriate vocabulary in each case.

**Acceptance Scenarios**:

1. **Given** a project with neutral-vocabulary commands installed, **When** the setup workflow runs with `--integration claude`, **Then** the `adapt-commands` step rewrites neutral descriptions to Claude Code-specific tool references (e.g., "present the user with a structured choice" becomes "use the AskUserQuestion tool with structured options").
2. **Given** a project with neutral-vocabulary commands installed, **When** the setup workflow runs with `--integration codex`, **Then** sections marked with capabilities that Codex lacks (e.g., `<!-- harness:interactive-choice -->`) are replaced with Codex-appropriate alternatives or removed with a fallback instruction.
3. **Given** a project where the setup workflow has already run, **When** the user re-runs the workflow (e.g., after updating spex), **Then** the adaptation step is idempotent: running it twice produces the same result as running it once.

---

### User Story 3 - Adaptation script uses mapping tables for maintainability (Priority: P2)

The `spex-adapt-commands.sh` script reads per-harness mapping tables rather than embedding substitution rules inline. Each mapping table defines vocabulary transformations and section-level replacements for one harness. Adding support for a new harness means creating a new mapping table without modifying the script logic.

**Why this priority**: Maintainability. Inline sed rules across 30+ command files would be fragile and hard to extend. A data-driven approach makes the system sustainable as more harnesses are supported.

**Independent Test**: Can be tested by adding a new mapping table for a hypothetical harness and verifying the adaptation script applies it correctly without code changes.

**Acceptance Scenarios**:

1. **Given** a mapping table for Claude Code that defines tool-name substitutions and section replacements, **When** the adapt-commands script runs against a neutral command file, **Then** the output matches what the current Claude Code-specific command contains.
2. **Given** the adaptation script and mapping tables, **When** a contributor wants to add support for a new harness, **Then** they only need to create one new mapping table file and add one case entry to setup.yml, without modifying the adaptation script itself.

---

### User Story 4 - Zero regression for Claude Code users (Priority: P1)

After the neutral vocabulary rewrite and Claude Code adaptation are applied, the end result for Claude Code users is functionally identical to today's commands. No behavioral regressions, no missing tool optimizations, no degraded precision in how instructions are interpreted.

**Why this priority**: Claude Code is the primary user base. Regressions would directly impact existing users. This is a non-negotiable quality constraint on P1 work.

**Independent Test**: Can be tested by comparing the adapted Claude Code commands against the current pre-rewrite commands and verifying functional equivalence through side-by-side execution of key workflows (brainstorm, ship, review).

**Acceptance Scenarios**:

1. **Given** the current set of extension commands before any changes, **When** the neutral rewrite + Claude Code adaptation pipeline produces the final commands, **Then** every Claude Code-specific tool reference that exists today is present in the adapted output.
2. **Given** a command that uses the Agent tool for subagent dispatch (e.g., ship pipeline stages), **When** the neutral version is adapted for Claude Code, **Then** the adapted version includes the same subagent_type, isolation mode, schema, and prompt structure as the current version.

---

### Edge Cases

- What happens when a command contains a tool reference in a context where no neutral equivalent exists (e.g., ExitWorktree's specific cleanup semantics)? The section should be wrapped in a capability marker and the adaptation script should include the full tool-specific block for capable harnesses and a plain-text fallback note for others (per FR-009).
- How does the system handle mixed content where some tool references are embedded within larger paragraphs rather than in standalone sections? These inline references should be rewritten to natural language directly (not marked), since they can be expressed generically without section-level replacement.
- What if a new version of spex adds a command that uses neutral vocabulary but no mapping table entry exists for it? The adapt-commands script should pass through unmapped content unchanged, treating neutral vocabulary as the safe default.
- What happens if the adaptation script fails mid-run (e.g., disk full, malformed mapping table)? The script should not leave partially transformed files. Either all files are transformed successfully, or the original files remain unchanged.
- What if a mapping table contains an entry that references a capability marker not present in any command file? The entry should be silently skipped without error.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: All extension command files MUST be rewritten to use harness-neutral vocabulary for behavioral instructions, replacing tool-specific references (AskUserQuestion, Agent tool, EnterWorktree, ExitWorktree, settings.json, settings.local.json, UserPromptSubmit, PreToolUse) with natural language descriptions of the desired behavior.
- **FR-002**: Command sections that require capability-specific behavior (e.g., subagent dispatch, interactive structured choices, worktree isolation) MUST be wrapped in HTML-comment capability markers (`<!-- harness:capability-name -->...<!-- /harness:capability-name -->`) to enable section-level replacement by the adaptation script.
- **FR-003**: An `spex-adapt-commands.sh` script MUST be created that reads per-harness mapping tables and applies vocabulary transformations and section replacements to installed command files.
- **FR-004**: The setup workflow (`setup.yml`) MUST include an `adapt-commands` step that runs after extension installation and before the workflow completes, using the detected harness to select the appropriate mapping table.
- **FR-005**: The adapt-commands step MUST be idempotent: running the setup workflow multiple times produces the same final command content.
- **FR-006**: The Claude Code mapping table MUST restore all tool-specific references that exist in the current pre-rewrite commands, ensuring zero behavioral regression for Claude Code users.
- **FR-007**: The adaptation script MUST pass through any command content that has no matching mapping entry, treating neutral vocabulary as a safe default.
- **FR-009**: When a mapping table does not provide a replacement for a capability-marked section (i.e., the harness lacks that capability), the default behavior MUST be to replace the section with a short plain-text note explaining the limitation and any manual workaround, rather than silently removing the section.
- **FR-010**: The adaptation script MUST support a `--dry-run` flag that outputs a diff-style preview of all transformations without modifying any files, enabling developers to verify mapping table correctness before applying changes.
- **FR-008**: Mapping tables MUST be stored as separate files (one per harness) in a well-known location within the spex directory structure.

### Key Entities

- **Command File**: A markdown file in an extension's `commands/` directory that contains instructions for the agent harness. Currently written for Claude Code; will be rewritten to neutral vocabulary.
- **Capability Marker**: An HTML-comment delimiter pair (`<!-- harness:X -->...<!-- /harness:X -->`) that identifies a section of a command file as requiring harness-specific adaptation.
- **Mapping Table**: A per-harness data file that defines vocabulary substitutions (inline text replacements) and section replacements (for capability-marked blocks).
- **Adaptation Script**: `spex-adapt-commands.sh`, the shell script that reads mapping tables and transforms neutral command files into harness-optimized versions.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Zero Claude Code-specific tool references remain in source command files after the rewrite.
- **SC-002**: After running the setup workflow with `--integration claude`, the adapted commands contain all tool-specific references present in today's pre-rewrite commands.
- **SC-003**: Adding support for a new harness requires only a new mapping table file and a setup.yml case entry, with zero changes to the adaptation script or command source files.
- **SC-004**: The setup workflow completes the adapt-commands step in under 5 seconds for the full set of extension commands.
- **SC-005**: Users of existing Claude Code installations experience no behavioral change in any spex workflow (brainstorm, ship, review, gates) after the migration. Verified by grepping adapted command files for the same tool references present in a pre-rewrite snapshot, and by executing the smoke test scenarios.

## Smoke Test

1. Run `specify workflow run setup.yml --integration claude` on a clean project and verify that all installed spex commands contain the expected Claude Code tool references (AskUserQuestion, Agent tool, etc.) by grepping the installed command files.
2. Run `specify workflow run setup.yml --integration codex` on a clean project and verify that installed commands contain no Claude Code-specific tool references and that Codex-appropriate alternatives are present where applicable.
3. Run the ship workflow end-to-end on a Claude Code project after the migration and verify that all stages (brainstorm, specify, plan, tasks, implement, review) produce the same quality of output as before the rewrite.

## Out of Scope

- **Phase 3 (Claude Code preset as a separate installable package)**: This feature builds the Claude Code mapping table as a built-in part of the spex distribution. Packaging it as a standalone, separately installable preset is future work.
- **Phase 4 (Community presets for other harnesses)**: Creating and publishing mapping tables for Codex, OpenCode, or other harnesses beyond a minimal proof-of-concept is out of scope. The architecture supports it, but the content is left to future contributors.
- **Upstream spec-kit changes**: No PRs to spec-kit core are required or planned. This feature works entirely within existing workflow primitives.
- **Command content redesign**: This feature rewrites vocabulary and adds capability markers. It does not redesign command logic, restructure sections, or change the behavioral intent of any instruction.

## Assumptions

- Feature 037 (setup workflow) is merged and the `setup.yml` infrastructure is available for adding new steps.
- Feature 033 (plugin root refs) is merged and all `find ~/.claude` patterns are already replaced with `<PLUGIN_ROOT>` references.
- The spec-kit maintainer's position (no upstream hooks needed, use workflow primitives) is stable and will not change during implementation.
- Commands will be written neutral-first, with all harnesses (including Claude Code) receiving adaptation. This is more principled than writing for Claude Code and de-specializing for others, even though it means the source files look different from what Claude Code users ultimately see.
- The initial scope covers the 8 extension command files that contain Claude Code-specific references. Additional commands that are already neutral need no changes.
- The capability marker format (`<!-- harness:X -->`) is acceptable noise in source command files, given that it serves an explicit purpose and is stripped/replaced at install time.

## Clarifications

### Session 2026-07-08

- Q: Canonical term for the marker mechanism ("capability marker" vs "delimiter marker" vs "harness block")? → A: **capability marker**
- Q: Default fallback when a harness lacks a capability (remove section vs replace with note vs per-capability decision)? → A: **Replace with plain-text note** explaining the limitation and any manual workaround
- Q: Should spex-adapt-commands.sh support a --dry-run preview mode? → A: **Yes, --dry-run** outputs diff-style preview without modifying files
