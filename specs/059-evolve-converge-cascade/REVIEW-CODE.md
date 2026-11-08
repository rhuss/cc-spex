# Code Review: Evolve as Flow-Back via speckit-converge

**Spec:** specs/059-evolve-converge-cascade/spec.md
**Contract:** specs/059-evolve-converge-cascade/contracts/markers-and-converge-handoff.md
**Date:** 2026-11-06
**Branch:** 059-evolve-converge-cascade
**Reviewer:** Claude (speckit.spex-gates.review-code + spex-deep-review)
**Mode:** autonomous (ship pipeline, stage 7/8, ask=smart)

This is a prose/instruction feature. The reviewed "code" is edited agent command/doc Markdown plus the project constitution. Correctness means: does the instruction prose faithfully and unambiguously implement the spec's requirements (FR-001..FR-028, SC-001..SC-007) and the exact marker/hand-off contract.

## Compliance Summary

**Overall Score: 100%** (28/28 functional requirements, 7/7 success criteria addressed at the instruction level) — gate threshold for deep review (95%) met.

Reviewed files:
- spex/extensions/spex/commands/speckit.spex.evolve.md (primary: cascade, markers, revision notes, converge hand-off, persistence model)
- spex/extensions/spex-gates/commands/speckit.spex-gates.review-code.md (FR-022/023/024)
- spex/extensions/spex-gates/commands/speckit.spex-gates.verify.md (FR-022/023/024, FR-016)
- spex/extensions/spex-gates/commands/speckit.spex-gates.review-spec.md (FR-025)
- spex/extensions/spex/commands/speckit.spex.spec-kit.md (FR-025)
- README.md, spex/docs/help.md, spex/extensions/spex/docs/help.md (FR-027, FR-025)
- .specify/memory/constitution.md (FR-028)

### Requirement coverage (highlights, verified against spec + contract)

- **Cascade (FR-001..FR-004):** no plan/tasks regeneration for completed-task features; per-resolution cascade table present; tasks.md append-only; converge invoked once after all edits, gated on all four conditions (spec/plan/tasks exist, >=1 complete, no open, >=1 routes to converge), with the open-tasks branch. Compliant.
- **Spec edits (FR-005..FR-008):** marker strings `**SUPERSEDED by <new-ID>**`, ID-less `**SUPERSEDED**`, `**RETIRED**` match contract §1 verbatim (including the leading space); next-unused-ID rule; no reuse/renumber/revive; `## Revision Notes` dated-subheading format matches contract §2. Compliant.
- **Plan edits (FR-009..FR-011):** in-place passage edit; `## Revision Notes` format matches contract §3; unchanged when no plan content affected. Compliant.
- **Converge hand-off (FR-012..FR-018):** `$ARGUMENTS` guidance matches contract §4 verbatim; converge-outcome routing (converged / appended-normal / appended-verify-finish / unavailable) matches contract §5; unrequested-task pause at every oversight level; pipeline containment per contract §6; FR-016 precedence over FR-014. Compliant.
- **Persistence model (FR-019..FR-021):** lenient matcher (case-insensitive label+value, hyphen==space, leading list marker tolerated, anywhere, first match wins; three recognized values; else not-declared -> flow-back + state once); flow-forward delivered-immutability; living-spec regenerate-only-when-no-task-complete. Compliant.
- **Downstream consumers (FR-022..FR-025):** review-code and verify assess live items only; no finding on completed-task wording alone; live gaps still reported; `/speckit-analyze` expected-noise note present at all five run-sites. Compliant.
- **Scope and docs (FR-026..FR-028):** only `.specify/memory/constitution.md` touched under `.specify/` (allowed); README + spex/docs/help.md describe all five flow-back aspects; constitution declares `Persistence model: flow-back` and clarifies generate-directive timing. Compliant.
- **SC-001..SC-007:** enforced at the instruction level (append-only guarantee, byte-identical tasks.md on catch-up, traced appended tasks, zero superseded/retired false findings, spec.md-alone auditability via markers+notes, flow-forward immutability, no remaining regenerate directive for completed-task features). SC-007 verified: the only remaining `regenerate` directives are the pre-implementation path, the FR-001 prohibition, the living-spec no-task-complete case, and "do NOT regenerate" statements.

## Deep Review Report

**Gate: PASS** (after 1 autonomous fix round). Critical + Important remaining = 0.

### Agent summary

| Agent | Found | Fixed | Remaining | Status |
|-------|-------|-------|-----------|--------|
| Correctness | 2 | 2 | 0 | completed |
| Architecture & Idioms | 3 | 2 | 1 (Notable) | completed |
| Security | 1 | 0 | 1 (Notable) | completed |
| Production Readiness | 2 | 1 | 1 (Notable) | completed |
| Test Quality | 2 | 2 | 0 | completed |
| Goal Alignment | - | - | - | skipped (no PR) |
| CodeRabbit (external) | 3 | 1 | 2 (verified not-actionable) | completed |
| Codex (external) | 0 | 0 | 0 | completed (no actionable bugs) |
| Copilot (external) | - | - | - | skipped (disabled in config) |
| Test Suite (regression) | - | - | - | skipped (no test command) |

Findings deduplicated to 3 distinct Important issues (all fixed) + 6 remaining Minor/Notable (none gate-blocking). Full detail in `review-findings.md`.

### Fixed (Important)

1. **Stale examples + legacy auto-update sections contradicted the flow-back cascade** (correctness + architecture + test). Added scoping caveats to evolve.md (Examples banner, decision-flow restriction, Thresholds caveat, "Minor (Auto-Update Eligible)" caveat) binding the legacy content to the pre-implementation path and cross-referencing the section-5 cascade. (FR-002/003/005/008 + spec Assumption.)
2. **ID-less `**SUPERSEDED**` marker not recognized by compliance filters / evolve guard** (architecture + CodeRabbit). Added the bare form to review-code.md:112/114, verify.md:272/274, evolve.md:259. (FR-005/007/022, SC-004, contract §1.)
3. **EC9 trigger-detection ambiguity (FR-016 vs FR-017)** (test + production). Added a trigger-precedence clarification to evolve.md:348: the implement path applies only to a review-code-stage trigger; verify/finish take the FR-016 path even when `.spex-state` is `running`.

### Remaining (not gate-blocking; verified against spec)

| # | Severity | File:line | Issue | Classification |
|---|----------|-----------|-------|----------------|
| 4 | Minor | evolve.md:~321 / contract §4 | Converge hand-off guidance names only `SUPERSEDED by <ID>`/`RETIRED` (not the ID-less bare form); left unchanged as a verbatim contract reproduction | Ambiguous (faithful to contract) |
| 5 | Notable | evolve.md:348 | Anti-recursion hook-skip mechanism stated but not operationalized; mechanism lives in out-of-scope `/speckit-implement`; bounded by FR-014 + retry limit | Ambiguous |
| 6 | Notable | evolve.md:96-103 | Persistence matcher "first match anywhere" can mis-select from prose; conservative impact; faithful to clarified spec | Unambiguous (faithful, low impact) |
| 7 | Minor | review-spec.md:252 (+spec-kit.md:72, evolve.md:651) | FR-025 "only live items actionable" slightly broader than FR-025 requires | Ambiguous |
| 8 | Notable | evolve.md:~334 | CodeRabbit "invalidate stale verification pass" suggestion; no FR requires it; out of scope | Ambiguous (out of scope) |
| 9 | Notable | two help.md files; README.md:435 | Pre-existing help-file naming drift (unchanged lines); README analyze row lacks FR-025 caveat (not required there) | Unambiguous (pre-existing / not required) |

### External tools

- **CodeRabbit** (CLI 0.7.6, local, `--uncommitted`): 3 "major" findings. One (ID-less `**SUPERSEDED**`) corroborated an internal finding and was fixed. Two (FR-025 over-broad; invalidate stale verification pass) were verified against the spec and found not actionable (FR-025 is satisfied as written; no FR requires a verification-pass cache). Note: the CLI reports it is outdated and suggests `coderabbit update`.
- **Codex** (v0.166.0, local, `--uncommitted`): no actionable bugs; "the added workflow guidance is consistent across the specification, evolve instructions, gates, and documentation; `git diff --check` passes."
- **Copilot:** disabled in `deep-review-config.yml`.

## Conclusion

Spec compliance 100%; deep review gate PASS after one autonomous fix round that resolved three corroborated Important consistency/faithfulness issues with minimal additive clarifications. Remaining items are Minor/Notable and do not block the gate. No requirement text was removed. No commit was made (per pipeline instruction).
