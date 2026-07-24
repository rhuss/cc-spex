# Phase 0 Research: First-Class Codex Plugin Support

## R1 — Distribution architecture

**Decision**: Keep one canonical core under `spex/` and create thin Claude/Codex distribution descriptors. Build each distribution in a temporary staging directory with a deterministic materializer.

**Rationale**: The repository already centralizes extensions, scripts, setup, and adapter token maps. Native Codex plugins require `.codex-plugin/plugin.json`; Codex and ChatGPT share a plugin directory and support personal marketplaces. Staging prevents one harness transformation from modifying another or the canonical sources.

**Alternatives considered**: A single dual-purpose manifest cannot express collision-free harness ownership. A Codex fork duplicates methodology and drifts. Runtime symlinks are not portable marketplace artifacts.

## R2 — Native Codex surfaces

**Decision**: Package Codex skills and hooks in the plugin. Use `.codex/config.toml` for trusted repository configuration, `AGENTS.md` for concise durable guidance, and plugin-root-relative hooks via `PLUGIN_ROOT`.

**Rationale**: Current Codex documentation defines `.codex-plugin/plugin.json`, plugin-bundled hooks, trusted project `.codex/config.toml`, and repository guidance in `AGENTS.md`. Bundled skills appear after a new session; hooks require explicit trust review. The existing generated absolute hook paths are therefore unnecessary and fragile.

**Alternatives considered**: Project-local absolute hook paths stale after cache relocation. User-global configuration violates project scope. Replacing the full `AGENTS.md` destroys user guidance.

Official references: [Build plugins](https://developers.openai.com/plugins/build/plugins), [Codex configuration](https://developers.openai.com/codex/config-reference), [Codex hooks](https://developers.openai.com/codex/config-advanced#hooks).

## R3 — Initialization and security profiles

**Decision**: Persist a neutral `.specify/spex-profile.yml`, then atomically materialize the active harness configuration. Safe changes no host policy. Autonomous enables only enumerated non-destructive Spex operations. YOLO extends this to any non-destructive workspace operation. Network, external side effects, destructive operations, and out-of-workspace actions remain approval boundaries.

**Rationale**: A neutral profile records requested versus effective policy and survives adapter refresh. Codex exposes project `approval_policy`, `sandbox_mode`, workspace-write configuration, granular approvals, and custom permission profiles, but project trust or managed requirements can prevent enforcement. Capability probing must therefore validate effective behavior and offer only a confirmed safer fallback before writing.

**Alternatives considered**: The existing `standard|yolo|none` input is inconsistent with the spec. Treating PreToolUse hooks as the sandbox policy confuses workflow ordering with host authority. Silent downgrade violates user intent.

## R4 — Extension selection and repeatable refresh

**Decision**: Recommended defaults are gates, deep review, and worktrees; Teams, collaboration, and detach require explicit selection. Refresh reads the existing profile and installed extension state, presents them as defaults, validates dependencies, and applies an atomic delta.

**Rationale**: Current setup installs nearly everything and can lose enablement intent by remove/re-add. A profile makes initialization idempotent and supports security/profile changes without duplicating configuration.

**Alternatives considered**: `extensions=all` contradicts the accepted defaults. Inferring intent only from installed directories cannot distinguish selected, dependency-enabled, and stale extensions.

## R5 — Workflow-state authority

**Decision**: Use one versioned WorkflowState schema manipulated by the canonical Python helper. Persist canonical repository/worktree/spec/state paths, Git identity, stage/gates, recovery, and resume data. Resolve candidates through Git worktree metadata and accept exactly one state matching the existing worktree, branch, and spec.

**Rationale**: Current state lacks durable paths and relies on `SHIP_STATE_FILE`, CWD, newest spec mtime, and local state presence. Explicit identity makes commands and delegated work independent of host CWD resets. It implements the accepted conflict rule.

**Alternatives considered**: Timestamp/last-writer-wins is unsafe after crashes. A state file only under the Git common directory may be outside the writable project boundary. Environment-only recovery is retained only as an optimization.

## R6 — Transactional worktree transfer

**Decision**: Transfer state in two phases: create a candidate with a transfer ID in the worktree, read back and validate Git/spec/state identity, commit it as authoritative, then remove the main marker. Preserve both candidates and diagnostics if any step fails.

**Rationale**: Current shell capture/copy/removal can clear main state before validating the worktree copy. A machine-readable WorktreeIdentity contract allows downstream consumers to avoid rediscovery.

**Alternatives considered**: Unconditional move risks state loss. Copying without authority metadata creates two plausible states. Shell-held JSON is fragile.

## R7 — Continuous bounded recovery

**Decision**: Model recovery as a persisted episode with default `max_attempts=3` and `max_elapsed_seconds=1800`. Fingerprint findings, remedies, artifact inputs, and results; stop before equivalent repetition or A→B→A oscillation. Accepted revisions invalidate downstream artifacts/gates and rewind to the earliest affected stage.

**Rationale**: Current fixed retries pause and reset on resume, so they neither continue intelligently nor provide a true finite budget. Persisted UTC deadlines survive restart; monotonic duration is used within a process.

**Alternatives considered**: Unlimited retry breaks termination. An append-only event log provides richer replay but is excessive for the first implementation; bounded attempt history plus preserved diagnostics is sufficient.

## R8 — Progress presentation

**Decision**: State transitions emit a shared ProgressEvent. The Codex adapter maps events to native task progress when available and always emits concise transcript transitions. Claude retains its status-line specialization. Durable state remains authoritative.

**Rationale**: A semantic event contract separates workflow truth from harness UI capability and supports explicit degradation.

**Alternatives considered**: Installing the Claude status-line command in Codex is unsupported. Transcript-only state is not durable enough for resume.

## R9 — Subagents and Teams

**Decision**: Use bounded SubagentAssignment/Result contracts. Research agents may share a read view; concurrent writers require isolated Git worktrees. The orchestrator waits, reviews against the spec, reconciles accepted results, then releases dependents. Sequential fallback is a successful mode.

**Rationale**: Current Codex releases support subagents and inherit the parent sandbox/permission mode. Explicit workdirs and assignments prevent CWD/context drift. Teams remains experimental until isolation/reconciliation tests pass.

**Alternatives considered**: Prose token substitution alone does not create isolation or dependency enforcement. Sharing one writable worktree risks conflicts. Treating unavailable subagents as failure contradicts the spec.

Official reference: [Codex subagents](https://developers.openai.com/codex/subagents).

## R10 — Compatibility and release gates

**Decision**: Release independently materializes Claude and Codex, validates schemas and inventories, fails on unresolved harness tokens/foreign references, tests each install and combined coexistence, and runs an OpenCode adapter fixture. `make release` depends on all gates before tagging.

**Rationale**: Existing validation and marketplace tests are Claude-only; the adaptation script warns instead of failing on leftovers. Cross-harness defects are packaging failures and must block release.

**Alternatives considered**: Manual smoke tests are insufficient for cache/path collisions. Mutating canonical commands in place makes idempotence and reproducibility difficult.
