# Research: Smart Phase Splitting

## R1: File Path Extraction from plan.md

**Question**: How reliably can file paths be extracted from plan.md?

**Finding**: plan.md files in this project consistently reference files in two patterns:
1. Backtick-quoted paths: `` `spex/extensions/spex-collab/commands/speckit.spex-collab.phase-split.md` ``
2. Prose references: `spex/extensions/spex-collab/config-template.yml`
3. Code block paths: inside ```text blocks showing directory structures

A regex matching `[a-zA-Z0-9_./-]+\.[a-zA-Z]{1,5}` with a `/` requirement captures most references. False positives (URLs, version numbers like `v1.5`) can be filtered by excluding lines starting with `http` and patterns without a directory separator.

**Decision**: Use grep-based extraction with deduplication. Accept that estimation is approximate (the spec explicitly acknowledges this).

**Alternatives considered**:
- AST-based markdown parsing: Too complex for the benefit, requires external tools
- Structured file list in plan.md: Would require changing the plan template, too invasive

## R2: Task-to-Phase File Mapping

**Question**: How to determine which files a specific phase's tasks will touch?

**Finding**: plan.md does not explicitly map files to tasks. Tasks are referenced by ID (T001, T002) and phases group tasks by heading. The file-to-task mapping cannot be precisely determined without implementation.

**Decision**: For the threshold gate, use the total estimated file count (not per-phase). For the merge algorithm, distribute files proportionally across phases based on task count. This is imprecise but sufficient for deciding whether to merge small phases.

**Rationale**: The goal is a heuristic that prevents obviously wrong splits (7 phases for 15 files), not a precise file accounting system.

## R3: Phase-Manager Hook Behavior

**Question**: How does phase-manager currently get invoked, and how to prevent it from firing in single-phase mode?

**Finding**: Phase-manager is NOT registered as a lifecycle hook in extension.yml. It is invoked explicitly by the instructions that phase-split outputs. Each phase's instructions say "Run /speckit-implement... Then /speckit-spex-collab-phase-manager".

**Decision**: The fix is straightforward. In single-phase mode, phase-split should output instructions that call phase-manager only once after all tasks complete, not between phases. No changes to hook registration needed.

**Key insight**: The phase-manager ship pipeline guard already skips in ship mode. For interactive (non-ship) single-phase mode, the phase-split output instructions are the control mechanism.

## R4: Existing Test Coverage

**Question**: What tests exist for phase-split and phase-manager?

**Finding**: The `make release` target runs schema validation and integration tests that verify all extensions, commands, hooks, and skills are present and correctly structured. There are no unit tests for phase-split or phase-manager logic specifically. Testing is done via the integration test which installs the plugin and verifies the command files exist.

**Decision**: Changes must preserve the existing command file structure (frontmatter, heading hierarchy) to pass schema validation. Functional testing is manual via the brainstorm/specify/implement workflow.
