# Brainstorm: First-Class Codex Plugin

**Date:** 2026-07-24
**Status:** active

## Problem Framing

Spex has begun adapting its commands and hooks for Codex, but it does not yet behave as a first-class Codex product. The current installation path, runtime assumptions, and autonomous pipeline still inherit Claude Code concepts that do not transfer directly.

The immediate failure is worktree continuity during `ship`: the state is moved out of the main checkout, while subsequent operations can continue from the main directory or retain an absolute state path pointing there. More broadly, the current Codex integration has several mismatches:

- initialization still contains Claude-hardcoded paths and behavior;
- Codex permission configuration is effectively a no-op;
- some installed commands retain Claude-specific wording or unresolved harness markers;
- shell `cd` and environment mutations are assumed to persist across tool calls;
- the custom Spex status-line command is a Claude Code facility, not a Codex facility;
- retry exhaustion can cause `ship` to stop even when it can safely continue with research, a feasibility spike, artifact revision, or another bounded recovery action;
- the Teams extension describes Claude Agent Teams semantics even though Codex exposes a different subagent model.

The goal is a first-class Codex plugin that users install from a Codex marketplace, followed by an interactive `spex:init` that initializes the repository, selects extensions, and configures a project-wide security posture. Claude and Codex support should coexist in this repository without duplicating the Spex methodology, and the architecture should admit an OpenCode adapter later.

This brainstorm consolidates and advances the Codex-facing parts of earlier work on harness-agnostic Spex (#28), worktree CWD persistence (#27, attic), workflow-based setup (#34, attic), the Codex hook contract (#36, attic), plugin discovery (#31), and autonomous ship behavior (#05, attic).

## Approaches Considered

### A: Codex-Native Plugin with Shared Spex Core

Maintain one canonical Spex core for workflows, extensions, state semantics, and shared scripts. Package thin, first-class adapters for Claude Code and Codex in separate plugin roots within this repository. Each adapter owns only its harness-specific manifest, installation layout, interaction mechanisms, hooks, permissions, subagent dispatch, progress presentation, and worktree behavior. Add OpenCode later as a third adapter.

- Pros: First-class Codex experience; one source of truth for the methodology; both plugins can coexist; clear extension point for OpenCode; harness differences remain explicit and testable.
- Cons: Requires a disciplined source/materialization boundary; adapter and cross-install tests become mandatory; not every harness can offer identical enforcement.

### B: Harness-Neutral Workflow Bundle

Use a `specify workflow` bundle as the universal installation and runtime layer, with minimal harness-specific integration.

- Pros: Portable distribution model; declarative setup; less plugin-specific packaging.
- Cons: Weaker Codex-native installation and interaction experience; less control over permissions, subagents, and progress; interactive extension selection varies by harness.

### C: Separate Codex Fork

Maintain an independently specialized Codex version of Spex.

- Pros: Fast freedom to optimize exclusively for Codex; minimal abstraction work initially.
- Cons: Workflow duplication and drift; fixes must be ported repeatedly; OpenCode would likely create a third fork.

## Decision

Choose **Approach A: Codex-native plugin with a shared Spex core**.

The repository will host separate Claude and Codex plugin distributions over one canonical workflow and extension core. Harness adapters specialize behavior where capabilities differ; they do not pretend that Claude Agent Teams, Claude status lines, Codex subagents, or Codex permission policies are interchangeable. A future OpenCode plugin follows the same adapter contract and degrades capabilities explicitly when OpenCode cannot provide equivalent enforcement.

## Key Requirements

### Plugin and initialization experience

- Publish Spex as a personal Codex marketplace plugin.
- Provide a Codex-visible `spex:init` entry point.
- `spex:init` initializes or refreshes the current repository, detects Codex, and writes only Codex-specific project configuration.
- Ask which extensions to enable. Preselect `spex-gates`, `spex-deep-review`, and `spex-worktrees`; offer `spex-teams`, `spex-collab`, and `spex-detach` as optional choices.
- Keep `spex-teams` optional and label its Codex implementation experimental until parallel write isolation and reconciliation are proven reliable.
- Support installing the Claude and Codex plugins from the same repository without manifests, caches, generated commands, hooks, or project configuration overwriting one another.

### Project-wide security levels

- `spex:init` asks for one project-wide security level:
  - **Safe**: normal approvals and conservative sandbox behavior.
  - **Autonomous**: reduce routine approvals for in-workspace Spex work while preserving approval boundaries for destructive or external actions.
  - **YOLO**: bypass routine approvals broadly so autonomous pipelines can run unattended, while still blocking destructive actions outside the workspace and other actions requiring new authority.
- Apply the selected level consistently to normal commands, `ship`, reviews, implementation, and spawned Codex subagents.
- Explain the effective trust boundary before persisting Autonomous or YOLO.

### Reliable worktree and state continuity

- Never rely on `cd`, exported variables, or other shell-process state persisting into later Codex tool calls.
- Represent the active feature worktree, repository root, feature branch, spec directory, and state-file location as explicit durable state.
- Pass the resolved absolute worktree directory to every subsequent command and subagent operation.
- When the worktree-management hook creates a worktree, consume its machine-readable result rather than rediscovering the branch from the main checkout.
- Retarget ship state to the worktree before removing the main-checkout copy.
- Make resume and recovery deterministic from either the main checkout or feature worktree.
- Ensure spec discovery, extension configuration, hook execution, and state mutation all resolve against the active worktree.

### Ship continuity and autonomous recovery

- `ship` is a continuous pipeline. Stage completion, subagent return, context compression, retry exhaustion, or a recoverable review finding must not become an implicit stopping point.
- After normal fix retries are exhausted, continue with bounded autonomous recovery: focused research, feasibility spikes, artifact revision, alternative implementation attempts, or decomposition of the finding.
- Feed recovery results back into the appropriate spec, plan, tasks, or implementation stage and rerun affected gates.
- Pause only when progress requires new user authority, an irreversible external action, credentials or infrastructure the agent cannot obtain, or a material product decision unsupported by existing requirements.
- A recommendation such as “run a focused feasibility spike” must be executed automatically when it is safe and within scope; it must not be turned into “Should I proceed?” in Autonomous or YOLO operation.
- Persist enough state to resume the exact stage and recovery activity after interruption.
- Add loop limits and an explicit terminal failure report so “continue autonomously” cannot become an infinite cycle.

### Codex-native progress

- Do not attempt to install the Claude custom status-line command for Codex.
- Use Codex-native task progress plus concise stage-transition and recovery messages.
- Keep the durable state file as the source of truth for recovery, not as a UI integration dependency.

### Codex subagents and optional Teams

- Use Codex subagents for isolated reviews and other bounded parallel work.
- For Teams, split only genuinely independent task groups.
- Read-only research agents may share the repository view; parallel code-writing agents require separate Git worktrees and explicit working directories.
- Subagents inherit the selected project security posture and receive the minimum necessary spec/task context.
- The orchestrator waits for all assigned work, reviews each result against the spec, reconciles accepted changes, and replaces or falls back from failed agents without pausing unnecessarily.
- Fall back to sequential execution when tasks overlap, isolation cannot be established, or Codex subagents are unavailable.

### Harness architecture and compatibility hardening

- Maintain canonical neutral workflow sources where behavior is truly shared.
- Keep Claude-, Codex-, and future OpenCode-specific behavior in thin, explicit adapters or presets.
- Materialized plugin artifacts must contain no unresolved harness markers and no instructions naming unavailable tools or commands.
- Audit all Spex commands for assumptions about interactive-choice tools, hooks, permissions, context reset, status lines, shell persistence, paths, subagents, and worktrees.
- Add installation and behavioral tests for Claude alone, Codex alone, and both plugins installed together.
- Add static checks preventing Claude-only instructions from leaking into Codex artifacts and vice versa.
- Define a harness capability/degradation report so missing parity is visible rather than silently ignored.

## Open Questions

- What is the canonical shared-source layout that allows both marketplace manifests to reference or package the same core without duplicating generated artifacts?
- Which Codex project configuration provides the clearest durable mapping for Safe, Autonomous, and bounded-YOLO modes across supported Codex versions?
- What finite recovery budget should `ship` use before declaring a genuine terminal failure rather than continuing another autonomous cycle?
- Should recovery spikes remain inside the current feature worktree or use disposable nested worktrees when they may produce conflicting experiments?
- Which parts of the existing harness-marker adaptation should remain generation-time transforms, and which should become explicit adapter-owned files?
- What minimum evidence is required before Codex Teams can graduate from experimental to recommended?

