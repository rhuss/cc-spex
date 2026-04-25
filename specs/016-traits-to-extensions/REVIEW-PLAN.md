# Review Plan: Replace Traits with Spec-Kit Extensions

**Reviewed**: 2026-04-09 | **Branch**: `016-traits-to-extensions`

## Coverage Matrix

### Functional Requirements → Tasks

| Requirement | Task(s) | Status |
|-------------|---------|--------|
| FR-001: Five extensions with manifests | T01, T02, T03, T04, T05 | COVERED |
| FR-002: `speckit.{ext-id}.{command}` naming | T01-T05 | COVERED |
| FR-003: Hooks in `extensions.yml` | T02, T03, T04, T05, T07 | COVERED |
| FR-004: `spex-init.sh` installs via `specify extension add --dev` | T06 | COVERED |
| FR-005: Core always installed, optionals default-enabled | T01, T06 | COVERED |
| FR-006: Disable removes commands/hooks/skills | T09 | COVERED |
| FR-007: Ship sequences, skips clarify, sets state, creates PR | T10 | COVERED |
| FR-008: Teams standalone implement, ship routes | T04, T10, T11 | COVERED |
| FR-009: Remove old overlay system | T13 | COVERED |
| FR-010: Remove old skills/commands directories | T13 | COVERED |
| FR-011: Multiple hooks sequential in order | T07 | COVERED (implicit) |
| FR-012: Constitution update | T14 | COVERED |
| FR-013: Mandatory hook failure halts pipeline | - | DEFERRED (spec-kit native behavior, not spex implementation) |

### User Stories → Tasks

| User Story | Task(s) | Status |
|------------|---------|--------|
| US1: Init with extensions (P1) | T01-T06 | COVERED |
| US2: Quality gates via hooks (P1) | T07 | COVERED |
| US3: Enable/disable extensions (P2) | T08, T09 | COVERED |
| US4: Ship pipeline (P2) | T10 | COVERED |
| US5: Teams standalone (P3) | T11 | COVERED |
| US6: Worktree via hook (P3) | T12 | COVERED |

### Success Criteria → Tasks

| Criterion | Task(s) | Status |
|-----------|---------|--------|
| SC-001: Trait capabilities function identically | T07, T09, T10, T11, T12 | COVERED |
| SC-002: Codebase reduced (overlays/traits removed) | T13 | COVERED |
| SC-003: Two-agent support | - | GAP (see below) |
| SC-004: Zero context pollution | T09 | COVERED |
| SC-005: Ship completes autonomously | T10 | COVERED |
| SC-006: `make release` passes | T15 | COVERED |

## Red Flags

### RF-1: T01 is oversized (Medium risk)

T01 migrates 7 skills (brainstorm: 732 lines, ship: 742 lines, using-superpowers, evolve, help, init, spec-kit, spec-refactoring) plus the extensions management command and ship-guard integration into a single task. This is the largest task by far.

**Recommendation**: Consider splitting T01 into T01a (core commands: brainstorm, help, init, evolve, spec-refactoring, extensions) and T01b (ship command + ship-guard integration, using-superpowers routing). T01a and T01b can run in parallel since they produce independent command files.

### RF-2: SC-003 multi-agent validation gap (Low risk)

No task explicitly validates that extension commands work with a second AI agent (e.g., Codex). SC-003 relies on spec-kit's agent detection, which is upstream functionality. The risk is low since this is spec-kit's responsibility, but validation would increase confidence.

**Recommendation**: Add a note to T15 to verify that `specify extension add` registers commands correctly for at least the Claude agent, and document how a second agent would be tested when available.

### RF-3: Migration data loss risk (Medium risk)

T13 deletes `spex/skills/` (18 directories, some with 700+ line SKILL.md files) and `spex/commands/` (14 files). If T01-T05 miss any content during migration, it's lost.

**Recommendation**: Before T13 execution, verify that every file in `spex/skills/*/SKILL.md` has a corresponding command file in `spex/extensions/*/commands/`. Use a diff-based check.

### RF-4: FR-013 not explicitly tested (Low risk)

Hook failure behavior (pipeline halts on mandatory hook failure) is a spec-kit native feature, not something spex implements. No task verifies it. Risk is low because this is upstream behavior.

**Recommendation**: Accept as deferred. If spec-kit's hook failure behavior is ever in doubt, add a manual test.

## Task Quality Assessment

| Task | Scope | Files Clear | Verify Clear | Dependencies |
|------|-------|-------------|--------------|--------------|
| T01 | LARGE | Yes | Yes | None |
| T02 | Medium | Yes | Yes | None |
| T03 | Small | Yes | Yes | None |
| T04 | Medium | Yes | Yes | None |
| T05 | Small | Yes | Yes | None |
| T06 | Medium | Yes | Yes | T01-T05 |
| T07 | Small (validation) | N/A | Yes | T02, T06 |
| T08 | Medium | Yes | Yes | T06 |
| T09 | Small (validation) | N/A | Yes | T06, T07 |
| T10 | Medium | Yes | Yes | T01, T02, T05 |
| T11 | Medium | Yes | Yes | T04 |
| T12 | Small (validation) | N/A | Yes | T03, T07 |
| T13 | Large (deletions) | Yes | Yes | T01-T06, T08 |
| T14 | Medium | Yes | Yes | None |
| T15 | Small (validation) | Conditional | Yes | T13, T14 |

## Parallel Execution Viability

The wave-based execution plan is sound:

- **Wave 1** (T01-T05): All independent, create separate extension directories. Good parallel candidates.
- **Wave 2** (T06): Single task, must wait for extension bundles.
- **Wave 3** (T07, T08, T10, T11): Independent post-init tasks. Good parallel candidates.
- **Wave 4** (T09, T12): Validation tasks, depend on wave 3.
- **Wave 5** (T13, T14): Cleanup. T14 is independent of T13.
- **Wave 6** (T15): Final validation.

## Overall Assessment

**PASS** - Plan is ready for implementation.

- 15 tasks cover all 13 functional requirements (1 deferred to upstream)
- All 6 user stories have task coverage
- 5/6 success criteria have task coverage (SC-003 is upstream)
- Dependency graph is well-structured with clear parallel opportunities
- All tasks have verification steps

**Recommendations** (non-blocking):
1. Consider splitting T01 into two parallel sub-tasks (core commands vs. ship/routing)
2. Add migration verification step before T13 executes
3. Document multi-agent testing approach for future SC-003 validation
