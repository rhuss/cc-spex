# Implementation Plan: Codex Integration for Deep Review

**Branch**: `041-codex-deep-review` | **Date**: 2026-07-14 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/041-codex-deep-review/spec.md`

## Summary

Add Codex as a third external review tool in the deep-review extension, alongside CodeRabbit and Copilot. Uses the direct `codex review` CLI following the existing external tool pattern. Includes config toggle, runtime detection, harness-marker recursion guard, output parsing, fix-loop integration, and ship pipeline flag support.

## Technical Context

**Language/Version**: Bash (POSIX-compatible), Markdown
**Primary Dependencies**: `codex` CLI (optional, detected at runtime), `jq`, `yq`
**Storage**: N/A (config files in YAML, findings in Markdown)
**Testing**: `make release` (integration test), manual verification via deep-review invocation
**Target Platform**: Cross-platform (macOS, Linux)
**Project Type**: AI agent plugin (Markdown commands + shell scripts)
**Performance Goals**: N/A (external tool invocation, runtime depends on Codex)
**Constraints**: Must not break existing deep-review behavior when Codex is unavailable
**Scale/Scope**: 4 files modified, 3 files with minor token additions

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-Guided Development | PASS | Following full SDD workflow |
| II. Extension Architecture | PASS | Changes stay within spex-deep-review extension |
| III. Extension Composability | PASS | Codex tool is independent, does not affect other extensions |
| IV. Quality Gates | PASS | Deep review is itself a quality gate, this extends it |
| V. Naming Discipline | PASS | No new commands, follows existing naming |
| VI. Skill Autonomy | PASS | Changes are within the deep-review command only |
| VII. State as Scripts | PASS | No new state management, uses existing patterns |
| No compiled artifacts | PASS | All changes are Markdown and YAML |

No violations. No complexity tracking needed.

## Project Structure

### Documentation (this feature)

```text
specs/041-codex-deep-review/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── spec.md              # Feature specification
└── checklists/
    └── requirements.md  # Spec quality checklist
```

### Source Code (repository root)

```text
spex/
├── extensions/
│   └── spex-deep-review/
│       ├── commands/
│       │   └── speckit.spex-deep-review.run.md   # MODIFY: Add Codex external tool section
│       └── config-template.yml                    # MODIFY: Add codex: true
├── scripts/
│   └── adapters/
│       ├── claude/
│       │   └── command-map.json                   # MODIFY: Add codex-review-tool token
│       ├── codex/
│       │   └── command-map.json                   # VERIFY: No codex-review-tool token (recursion guard)
│       └── opencode/
│           └── command-map.json                   # MODIFY: Add codex-review-tool token
```

**Structure Decision**: No new files created. All changes modify existing files within the established extension architecture.

## Global Constraints

Copied from spec and Technical Context. Every task inherits these implicitly:

- **Shell compatibility**: Bash (POSIX-compatible). No bashisms that break on `dash` or `sh`.
- **Target platforms**: macOS, Linux (cross-platform)
- **Dependencies**: `jq`, `yq` (assumed installed). `codex` CLI is optional, detected at runtime.
- **No new files**: All changes modify existing files within the established extension architecture.
- **Error isolation**: External tool failures (including Codex) MUST NOT block the review pipeline.

## Implementation Approach

### Phase 1: Config and Detection (FR-001, FR-002)

1. Add `codex: true` to `external_tools:` in `config-template.yml`
2. Add Codex CLI detection in Step 2 of the deep-review command, following the CodeRabbit pattern:
   ```bash
   # Codex (skip only if explicitly disabled in config)
   which codex >/dev/null 2>&1 && echo "CODEX_AVAILABLE=true"
   ```
3. Add config resolution for the `codex` key alongside existing `coderabbit` and `copilot` resolution

### Phase 2: Harness Marker Recursion Guard (FR-003, FR-009, FR-010, FR-011)

1. Wrap the Codex detection and dispatch sections in `{harness:codex-review-tool}...{/harness:codex-review-tool}` block markers
2. Add the `codex-review-tool` token to Claude adapter's `command-map.json` with the Codex detection and dispatch content
3. Add the same token to OpenCode adapter's `command-map.json`
4. Verify the Codex adapter's `command-map.json` does NOT include this token (absence = block omitted = no Codex self-invocation)

### Phase 3: Invocation and Output Parsing (FR-004, FR-005, FR-006)

1. Add Codex invocation in Step 4, following the CodeRabbit pattern:
   ```bash
   # Initial review
   codex review --base "${MAIN_BRANCH}" 2>&1

   # Fix loop re-review
   codex review --uncommitted 2>&1
   ```
2. Parse Codex review output:
   - Extract file paths, line numbers, severity keywords, descriptions
   - Map to common finding schema with `source_agent = "codex"`, `confidence = 75`
   - Handle empty output (zero findings), parse errors (warning + zero findings), timeouts (log + skip)

### Phase 4: Fix Loop and Reporting (FR-007, FR-008, FR-012)

1. Codex findings with Critical/Important severity enter the fix loop identically to CodeRabbit findings
2. Add "Codex (external)" row to the agent summary table in Step 9
3. Error handling follows CodeRabbit pattern: log failure, continue review, never block

### Phase 5: Ship Pipeline Flags (FR-013)

1. Add `--codex` and `--no-codex` flags to the ship pipeline's external tool flag resolution
2. Add `codex` to the config default reading alongside `coderabbit` and `copilot`

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Codex review output format changes | Low | Medium | Parse defensively, treat unparseable output as zero findings |
| Codex CLI not installed on most machines | Medium | Low | Graceful skip with clear status message |
| Harness marker not stripped correctly | Low | High | Test with `spex-adapt-commands.sh --debug` |

## Dependencies

- Codex CLI must be installed and authenticated for the feature to activate
- The harness adapter system (`spex-adapt-commands.sh`) must support the new marker token
- No upstream changes needed to Codex CLI or spec-kit
