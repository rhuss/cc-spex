# Implementation Plan: Harden Deep Review Process

**Branch**: `019-harden-deep-review` | **Date**: 2026-05-22 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/019-harden-deep-review/spec.md`

## Summary

Harden the deep review's fix loop to catch regressions by running the project's test suite after each fix round, enhance the test-quality agent to cross-reference spec acceptance scenarios against test verification methods, add swallowed error detection to the correctness agent, and inject project-specific framework hints into all review agent prompts.

## Technical Context

**Language/Version**: Bash (POSIX-compatible), Markdown
**Primary Dependencies**: `jq`, `yq`, `grep`, existing deep review extension infrastructure
**Storage**: N/A (markdown command files, YAML config)
**Testing**: Manual verification via deep review execution
**Target Platform**: Claude Code (CLI agent)
**Project Type**: AI agent skill/extension (markdown-driven)
**Performance Goals**: N/A (review quality, not throughput)
**Constraints**: All changes in markdown command files; no new scripts or extensions
**Scale/Scope**: Single command file (`speckit.spex-deep-review.run.md`) + config template

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-Guided Development | Pass | Following SDD workflow via ship pipeline |
| II. Extension Architecture | Pass | Changes within existing `spex-deep-review` extension |
| III. Extension Composability | Pass | No cross-extension modifications |
| IV. Quality Gates | Pass | Enhancing quality gates, not bypassing them |
| VII. State as Scripts | Pass | No new state management needed |

No violations. No complexity tracking needed.

## Project Structure

### Documentation (this feature)

```text
specs/019-harden-deep-review/
├── spec.md
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 output (via /speckit-tasks)
```

### Source Code (repository root)

```text
spex/extensions/spex-deep-review/
├── commands/
│   └── speckit.spex-deep-review.run.md   # Primary modification target
├── config-template.yml                    # Add test config keys
└── extension.yml                          # No changes needed
```

**Structure Decision**: All changes land in the existing deep review extension. No new files created in the extension (only modifications to existing command and config files).

## Implementation Approach

### Change 1: Fix Loop Test Execution (FR-001, FR-002, FR-003, FR-004, FR-005, FR-005a, FR-005b, FR-013)

**What**: Add Step 7.6 to the fix loop between staging fixes (Step 7.5) and re-dispatching agents (Step 7.7).

**Where**: `speckit.spex-deep-review.run.md`, Step 7 (Autonomous Fix Loop), between current items 5 and 6.

**How**:
1. Add test command auto-detection logic at Step 2 (alongside external tool detection)
2. Insert Step 7.6 after staging: detect test command, run with timeout, parse results
3. Convert test failures to Critical findings with `source_agent = "test-suite"`, `category = "regression"`, `confidence = 95`
4. Test failures consume a fix round (same as review findings)
5. Add "Test Suite (regression)" row to the gate outcome summary table (Step 9)
6. Add test suite results to `review-findings.md` template (Step 8)
7. Add progress reporting line: `[Test suite... passed/N failures]`

**Config changes** (`config-template.yml`):
```yaml
test_command: ""
test_timeout_seconds: 300
```

### Change 2: Spec-Anchored Test Validation (FR-006, FR-007, FR-008)

**What**: Enhance the test-quality agent prompt with instructions to cross-reference spec acceptance scenarios against test verification methods.

**Where**: `speckit.spex-deep-review.run.md`, Agent 5 (Test Quality) prompt, after the existing checklist.

**How**: Add a new checklist section:
```
SPEC-ANCHORED VALIDATION (when spec is provided):
- [ ] For each acceptance scenario in the spec, find the corresponding test
- [ ] Check whether the test's verification method matches the spec's
- [ ] Flag mismatches: "Spec says [method] but test uses [different method]"
- [ ] If scenario doesn't specify a verification method, verify test exists only
```

### Change 3: Swallowed Error Detection (FR-009, FR-010)

**What**: Enhance the correctness agent prompt with instructions to detect swallowed errors.

**Where**: `speckit.spex-deep-review.run.md`, Agent 1 (Correctness) prompt, after the existing checklist.

**How**: Add new checklist items:
```
For all languages:
- [ ] Swallowed errors: Are there functions that call fallible operations
      (API calls, file I/O, network requests) and log the error but do not
      return or propagate it? Silent error swallowing hides failures and
      prevents callers from handling errors.
```

With language-specific variants for Go (`if err != nil { log... }` without return), Python (`except: log...` without raise), etc.

### Change 4: Review Hints Injection (FR-011, FR-012)

**What**: If `.specify/review-hints.md` exists, inject its content into every review agent's preamble.

**Where**: `speckit.spex-deep-review.run.md`, Step 3 (Dispatch Review Agents) and Common Preamble.

**How**:
1. At Step 2 (detect external tools), also check for `.specify/review-hints.md`
2. In the Common Preamble, add item 10: "PROJECT REVIEW HINTS" section
3. The injection is conditional: only added when the file exists and is non-empty
4. Wrap in clear delimiters to avoid prompt confusion

## Dependencies

All changes depend on the existing deep review command file structure. No external dependencies. Changes are additive (new steps, new checklist items, new config keys) and do not modify existing behavior.

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Test command auto-detection picks wrong command | Low | Config override via `test_command` in config |
| Test suite is slow, adding time to fix loop | Medium | Configurable timeout (default 300s), skip if no command detected |
| Review hints content could confuse agent prompts | Low | Wrapped in clearly delimited section header |
| Swallowed error detection produces false positives | Medium | Scoped to specific operation categories, reduced confidence for documented swallows |
