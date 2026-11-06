# Implementation Plan: Evolve as Flow-Back via speckit-converge

**Branch**: `059-evolve-converge-cascade` | **Date**: 2026-11-06 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/059-evolve-converge-cascade/spec.md`

## Summary

Make `/speckit-spex-evolve` spex's **flow-back** implementation. Today evolve orders the agent to regenerate `plan.md` and `tasks.md` with `/speckit-plan` and `/speckit-tasks` after any spec change, which destroys completed-task history and makes agents skip the cascade. This feature replaces that directive with a per-resolution cascade: record accepted changes in `spec.md` and `plan.md` using community supersede/retire markers and dated revision notes, then hand off to the append-only `/speckit-converge` to add any remaining work as traced tasks. Review-code and verify are taught to judge code against **live** spec items only, so the append-only model does not produce false drift findings. The project constitution declares `Persistence model: flow-back`.

The entire change is instructional: it edits spex extension command and documentation files plus the project constitution. No source code is compiled; no new runtime scripts or ship-state commands are introduced (the evolve-inside-ship sequence runs within the existing review-code stage).

## Technical Context

**Language/Version**: Markdown (agent command/skill prose) and POSIX Bash. Existing Python 3 hooks/state scripts are unchanged.

**Primary Dependencies**: `specify` CLI (spec-kit); upstream `/speckit-converge` (append-only, honors `$ARGUMENTS`); `jq`, `yq`; ripgrep (`rg`) for cross-reference verification.

**Storage**: Plain files — `spec.md`, `plan.md`, `tasks.md`, `.specify/memory/constitution.md`, and the feature directory's design artifacts.

**Testing**: Schema validation via `make validate` and the full install/integration test via `make test-install` (installs the plugin from the local marketplace, checks all extensions/commands/hooks/skills, cleans up). Do NOT use `make release` for validation — it bumps the version, commits, tags, pushes, and creates a GitHub release. Behavior is prose-level, so correctness is validated by the scenario walkthroughs in `quickstart.md` (one per user story Independent Test) and by `rg` cross-reference/absence checks (e.g., no remaining "regenerate tasks.md" directive for completed features, converge referenced where required).

**Target Platform**: Agent harnesses that run spex — Claude Code and Codex. All edited files must stay agent-portable (no harness-specific assumptions beyond existing conventions).

**Project Type**: CLI / agent-tooling plugin (Markdown + Bash). Single project; no client/server split.

**Performance Goals**: N/A. There is no runtime performance surface; success is measured by artifact-correctness outcomes (SC-001 through SC-007).

**Constraints**:
- FR-026 boundary: only spex extension files and the project constitution may change. Files under `.specify/` that come from upstream spec-kit (templates, generated commands, scripts) MUST NOT be edited.
- Append-only `tasks.md`: evolve never edits `tasks.md`; only `/speckit-converge` appends.
- Canonical-source discipline (constitution): command source lives under `spex/extensions/<ext>/commands/`; scripts under `spex/scripts/` sync via `make sync-scripts`. This feature touches commands/docs/constitution, not scripts, so no `make sync-scripts` is required.

**Scale/Scope**: ~8 files edited: 1 evolve command (primary rewrite), 2 gates commands (review-code, verify), up to 5 files carrying `/speckit-analyze` guidance, README.md, 1–2 `help.md` copies, and the constitution. Two extensions touched (spex, spex-gates), independently.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| Principle | Assessment |
|---|---|
| I. Spec-Guided Development | PASS. Feature is spec-driven. FR-028 clarifies that the "generate plan/tasks via `/speckit-plan` and `/speckit-tasks`" guidance applies **before** implementation, resolving the tension the current evolve directive creates. |
| II. Extension Architecture | PASS. All behavior changes live in spex extension command files (FR-026). The constitution is project content, edited only as FR-028 requires. No upstream `.specify/` file is modified. |
| III. Extension Composability | PASS. Evolve lives in `spex`; review-code/verify in `spex-gates`. Changes are independent and do not edit each other's files. Evolve does not detect, call, or defer to a reconcile extension (Assumption). |
| IV. Quality Gates | PASS. The feature strengthens gates: review-code and verify assess compliance against live spec items only (FR-022–FR-025), reducing false findings. |
| V. Naming Discipline | PASS. Uses `/speckit-*` command and `spex:` skill prefixes. FR-028 also corrects a stale dotted `/speckit.plan` / `/speckit.tasks` phrasing in the constitution to the hyphen form. |
| VI. Skill Autonomy | PASS. Evolve keeps its single purpose (reconciliation) and delegates task generation to `/speckit-converge` rather than duplicating it. Its existing mismatch detection/analysis/recommendation are unchanged. |
| VII. State as Scripts | PASS. No new state and no inline-bash state management are introduced. The evolve-inside-ship sequence runs within the existing review-code stage and reuses that stage's retry limit (FR-017; Assumption: no new ship-state commands). |

**Result**: No violations. Complexity Tracking is empty.

## Project Structure

### Documentation (this feature)

```text
specs/059-evolve-converge-cascade/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output (entities: spec item, revision note, convergence phase, persistence model)
├── quickstart.md        # Phase 1 output (scenario validation, one per user story)
├── contracts/           # Phase 1 output (marker vocabulary + converge hand-off contract)
│   └── markers-and-converge-handoff.md
├── checklists/
│   └── requirements.md  # Spec quality checklist (existing)
└── tasks.md             # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (files edited by this feature)

```text
spex/extensions/spex/commands/speckit.spex.evolve.md     # PRIMARY: replace regenerate directive with flow-back cascade
spex/extensions/spex-gates/commands/speckit.spex-gates.review-code.md   # live-items-only assessment (FR-022–024)
spex/extensions/spex-gates/commands/speckit.spex-gates.verify.md        # live-items-only (FR-022–024) + converge-appended → not pass (FR-016)
spex/extensions/spex-gates/commands/speckit.spex-gates.review-spec.md   # /speckit-analyze guidance note (FR-025)
spex/extensions/spex/commands/speckit.spex.spec-kit.md                  # /speckit-analyze guidance note (FR-025)
spex/docs/help.md                                                       # flow-back cascade description (FR-027) + analyze note (FR-025)
spex/extensions/spex/docs/help.md                                       # same (if a distinct synced copy)
README.md                                                               # flow-back cascade description (FR-027)
.specify/memory/constitution.md                                         # Persistence model: flow-back + generate-directive clarification (FR-028)
```

No files under `.specify/` other than the project-owned `constitution.md` are edited (FR-026). The spex-collab `revise` workflow is explicitly out of scope and keeps its regenerate-and-reconcile model (Assumption).

## Complexity Tracking

No constitution violations. No entries.

## Phase 0: Research

See [research.md](./research.md). Resolved items: the supersede/retire marker vocabulary and its placement rules; the `/speckit-converge` argument channel for interpretation guidance; the persistence-model detection rule (lenient matching per the 2026-11-06 clarifications); how review-code/verify distinguish live from superseded/retired items; the testing strategy for a prose-only feature; and the set of files that carry `/speckit-analyze` guidance.

## Phase 1: Design & Contracts

- [data-model.md](./data-model.md): the four conceptual entities (spec item with live/superseded/retired states; revision note; convergence phase; persistence model), their fields, states, and invariants (IDs never reused; superseded/retired items never revived).
- [contracts/markers-and-converge-handoff.md](./contracts/markers-and-converge-handoff.md): the exact marker strings, revision-note structure for spec.md and plan.md, and the guidance string evolve passes to `/speckit-converge`. This is the user-facing/tool-facing contract of the workflow.
- [quickstart.md](./quickstart.md): runnable validation scenarios mapped to each user story's Independent Test and to SC-001–SC-007.

### Post-Design Constitution Re-Check

Re-evaluated after Phase 1: still PASS on all seven principles. The contracts keep behavior inside spex extension files, preserve append-only `tasks.md`, and add no new state. No new violations.
