# Implementation Plan: First-Class Codex Plugin Support

**Branch**: `047-codex-plugin-support` | **Date**: 2026-07-24 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/047-codex-plugin-support/spec.md`

## Summary

Add a native Codex plugin distribution with `.codex-plugin/plugin.json` and a personal-marketplace entry while retaining the existing Claude distribution and one canonical Spex core. A deterministic materializer will combine shared extensions, scripts, and skills with thin harness adapters, then fail closed on unresolved markers, foreign harness references, or identity collisions. `spex:init` will persist an initialization profile, map Safe/Autonomous/YOLO into trusted project `.codex/config.toml` capabilities, and preserve existing extension choices on refresh.

Replace CWD- and environment-dependent workflow recovery with a versioned state contract, transactional worktree transfer, and deterministic state resolution. Extend ship with bounded recovery episodes, cascade invalidation, non-convergence detection, and precise resume reports. Codex progress and subagent orchestration remain adapter-owned presentations over shared state and assignment contracts; Claude keeps its existing status-line specialization.

## Technical Context

**Language/Version**: POSIX shell and Bash (existing scripts), Python 3 (state and Codex hook adapters), Markdown (skills/commands), JSON/YAML/TOML (manifests, contracts, profiles, Codex configuration)

**Primary Dependencies**: `specify` CLI >= 0.12.16, `git` with worktree support, `jq`, `yq`, Codex CLI/plugin marketplace for Codex integration tests, Claude CLI/plugin marketplace for regression tests

**Storage**: Versioned project files (`.specify/spex-profile.yml`, `.specify/.spex-state`, `.codex/config.toml`), harness plugin manifests and generated staging trees; no database

**Testing**: Shell integration tests, Python unit tests for state/hook logic, JSON Schema validation, temporary Git repositories/worktrees, Claude-only/Codex-only/combined marketplace installation suites, `make sync-scripts-check`, `make release`

**Target Platform**: macOS and Linux; trusted Codex repositories with current plugin, hook, project-config, and subagent support; existing Claude Code platforms remain supported

**Project Type**: Multi-harness AI-agent plugin and extension bundle

**Performance Goals**: Initialization completes without manual repair; 100 repeated worktree lifecycle runs produce zero wrong-checkout mutations; progress emits within one state transition; recovery stops at 3 attempts or 30 minutes by default

**Constraints**: Shared semantics have one canonical source; state mutations use external scripts; no compiled artifacts; project configuration cannot grant authority beyond host/user policy; Codex hooks require trust review; generated distributions must be collision-free and contain no unresolved harness tokens

**Scale/Scope**: Two production harness distributions, seven extensions, three adapter definitions including an OpenCode proof fixture, approximately 52 functional requirements and six external/state contracts

## Constitution Check

*GATE: Passed before Phase 0 and re-checked after Phase 1 design.*

| Principle / constraint | Pre-design | Post-design evidence |
|---|---|---|
| I. Spec-Guided Development | PASS | Spec, clarifications, review gate, plan, research, contracts, and validation guide are present. |
| II. Extension Architecture | PASS | Existing extension directories remain self-contained; distribution adapters package them without cross-editing. |
| III. Extension Composability | PASS | Initialization profile records independent enablement; dependencies are validated rather than silently coupled. |
| IV. Quality Gates | PASS | Release and task workflows retain spec/plan/code gates and add cross-harness validation. |
| V. Naming Discipline | PASS | `specify`, `/speckit-*`, `spex:*`, and branch `047-codex-plugin-support` retain canonical names. |
| VI. Skill Autonomy | PASS | Init, state, progress, Teams, and review responsibilities stay in their owning skills/extensions. |
| VII. State as Scripts | PASS | State resolution, transfer, recovery, and progress events extend canonical Python/shell helpers rather than inline command prose. |
| Extension-local scripts | PASS | Canonical scripts remain under `spex/scripts/` and materialize into owning extensions through the existing sync inventory. |
| No compiled artifacts | PASS | Design uses Markdown, shell, Python, JSON, YAML, and TOML only. |
| Documentation maintenance | PASS | README, help, testing, marketplace, and migration documentation are explicit implementation scope. |

No constitutional violations require complexity exceptions.

## Global Constraints

Every implementation task inherits these specification and constitution constraints:

- Safe MUST leave the host's approval policy and sandbox boundaries unchanged; Spex MUST NOT add approval bypasses or expand writable, network, or external-action permissions.
- Autonomous MUST allow only enumerated, non-destructive Spex workflow operations within the active repository and feature worktree to proceed without repeated approval: repository reads, file edits, artifact generation, local tests, linters, builds, and non-destructive local Git operations.
- YOLO MUST allow any non-destructive project operation within the active repository and feature worktree to proceed without repeated approval, while network access, external side effects, destructive actions, and operations outside the writable workspace or granted authority retain host approval requirements.
- Each recovery episode defaults to a maximum of 3 attempts and 30 minutes; configured overrides MUST remain finite.
- Behavior shared by supported harnesses MUST have one canonical source of truth, and materialized artifacts MUST contain no unresolved harness directives or unavailable tool, command, path, or UI references.
- Adding a future OpenCode adapter MUST NOT require copying or forking the complete shared Spex workflow set.
- State operations MUST be implemented in dedicated scripts under `spex/scripts/`; this plugin adds no compiled artifacts or dependencies beyond the existing shell/Python tooling, `jq`, `yq`, `git`, and `specify` CLI.
- Documentation and cross-references MUST be updated whenever commands, skills, extensions, hooks, or workflows change.

## Project Structure

### Documentation (this feature)

```text
specs/047-codex-plugin-support/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── harness-adapter.schema.json
│   ├── initialization-profile.schema.json
│   ├── progress-event.schema.json
│   ├── subagent-assignment.schema.json
│   ├── workflow-state.schema.json
│   └── worktree-identity.schema.json
└── tasks.md                         # Generated later by /speckit-tasks
```

### Source Code (repository root)

```text
.claude-plugin/                       # Existing Claude marketplace metadata
plugins/
├── claude/                           # Thin Claude distribution descriptor/overlay
└── codex/
    └── .codex-plugin/plugin.json     # Native Codex plugin manifest

spex/
├── extensions/                       # Canonical shared extensions and commands
├── skills/init/SKILL.md              # Neutral initialization orchestration
├── scripts/
│   ├── adapters/{claude,codex,opencode}/
│   ├── hooks/shared/                 # Shared enforcement semantics
│   ├── spex-adapt-commands.sh
│   ├── spex-materialize-plugin.sh    # New deterministic staging/materialization
│   ├── spex-ship-state.{sh,py}       # Versioned state/recovery authority
│   ├── spex-worktree-cwd.sh          # Resolver client, never authority
│   └── spex-init.sh                  # Harness-aware bootstrap shim
├── setup.yml                         # Canonical interactive setup workflow
└── templates/agents-md/              # Sentinel-managed harness guidance

tests/
├── fixtures/adapters/opencode-minimal/
├── unit/                             # Adapter, profile, hooks, state, recovery
└── integration/
    ├── test_install_claude.sh
    ├── test_install_codex.sh
    ├── test_install_combined.sh
    └── test_worktree_lifecycle.sh
```

**Structure Decision**: Keep `spex/` as the canonical workflow core and introduce thin, explicit distribution descriptors under `plugins/`. Materialization copies canonical content to a temporary staging directory, applies one adapter, validates it, and emits a distribution without mutating canonical sources. Existing Claude paths remain compatible during migration.

## Implementation Strategy

### Phase A — Distribution and initialization foundation

1. Define adapter and initialization-profile validators from `contracts/`.
2. Add the Codex manifest, personal-marketplace entry, and collision-free distribution identity.
3. Implement deterministic staged materialization and fail-closed harness leakage checks.
4. Refactor setup/init into one harness-neutral flow with recommended extension defaults, preservation on refresh, capability probing, and atomic profile/config updates.
5. Merge sentinel-owned Spex guidance into `AGENTS.md`; never replace unrelated user content.

### Phase B — Durable feature/worktree authority

1. Upgrade ship state to the versioned workflow-state contract.
2. Add machine-readable worktree identity, validation, two-phase state transfer, and conflict diagnostics.
3. Resolve state by Git common directory, worktree, branch, and spec identity; timestamps remain diagnostic only.
4. Require commands, hooks, reviews, and subagents to consume explicit resolved context and revalidate after delegation.

### Phase C — Continuous ship recovery and progress

1. Add RecoveryEpisode transitions, persisted deadlines, attempt/result fingerprints, downstream invalidation, and terminal reports.
2. Emit shared progress events from state transitions; Codex uses native task/transcript presentation and Claude retains its status-line adapter.
3. Add authority-boundary pauses and prevent retry exhaustion, compaction, or subagent return from becoming implicit stops.

### Phase D — Codex Teams and cross-harness hardening

1. Generate bounded subagent assignments with explicit workdirs, security profile, dependencies, and evidence requirements.
2. Allow shared read views for research; require isolated Git worktrees for concurrent writers; review and reconcile before dependent work.
3. Make sequential fallback normative when capability, independence, or isolation checks fail.
4. Add Claude-only, Codex-only, combined-install, OpenCode-proof, leakage, idempotence, fault-injection, and 100-run lifecycle suites.
5. Update Makefile/release/versioning/documentation so all distributions validate before tagging.

## Risk Management

| Risk | Mitigation |
|---|---|
| Codex project config is ignored for untrusted repositories | Capability report marks project configuration inactive; init explains trust/restart requirements and refuses to claim an unenforced profile. |
| Plugin hook paths become stale after cache refresh | Bundle hooks in the Codex plugin and resolve through `PLUGIN_ROOT`; repo-local paths resolve from the Git root. |
| Existing `.claude`, `.codex`, or `AGENTS.md` content is overwritten | Use harness-specific roots, atomic merge operations, sentinel blocks, and combined-install fixtures. |
| State transfer crashes between copies | Two-phase transfer validates the worktree candidate before removing the main marker and preserves diagnostic evidence on every failure. |
| Autonomous recovery loops or oscillates | Persist finite attempt/deadline budgets and finding/remedy/artifact fingerprints; terminate before an equivalent cycle repeats. |
| Parallel agents overlap or inherit the wrong context | Dependency/file-contract analysis, explicit workdirs, inherited effective profile, isolated writer worktrees, orchestrator review, sequential fallback. |

## Complexity Tracking

No constitution violations. The multiple distribution descriptors and contracts reflect the feature's explicit multi-harness scope rather than architectural exceptions.
