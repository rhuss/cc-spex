# Review Guide: First-Class Codex Plugin Support

**Generated**: 2026-07-24 | **Spec**: [spec.md](spec.md)

## Why This Change

Spex has partial Codex adaptations but remains packaged, initialized, and operated primarily as a Claude Code plugin. Codex setup currently leaves permission policy unenforced, carries fragile absolute hook paths and Claude-specific assumptions, and can lose feature-worktree authority after state transfer or delegation. The ship pipeline also stops after ordinary retry exhaustion instead of performing safe bounded recovery.

## What Changes

This feature adds a native Codex plugin and personal-marketplace installation path, repeatable interactive initialization with explicit extension and security choices, durable worktree/state recovery, continuous bounded ship recovery, Codex-native progress, and optional safe subagent Teams. Claude and Codex remain independently installable from one shared Spex core, with an adapter contract that also proves future OpenCode extensibility. Existing Claude workflows remain supported; legacy initialization inputs receive migration guidance.

## How It Works

Canonical workflows, extensions, and state scripts remain under `spex/`. Thin harness descriptors under `plugins/` feed a deterministic staging materializer that applies adapter mappings and rejects unresolved or foreign harness content. Initialization persists a neutral profile before atomically mapping its effective settings into the active trusted harness configuration. A versioned WorkflowState binds repository, worktree, branch, spec, stage, recovery, and resume identity; worktree transfer uses a validated two-phase protocol. Shared progress and subagent-assignment contracts carry semantics while adapters own host-native presentation and dispatch.

Implementation is divided into nine phases and 76 tasks: setup/foundation, six independently testable user stories, and cross-cutting release validation. Tests precede story implementation and cover contract validation, fault-injected transfer, 100 lifecycle runs, recovery convergence, progress, Teams isolation/fallback, and Claude/Codex/combined installation.

## When It Applies

**Applies when**:

- Spex is installed or initialized for Codex, including repositories that also contain Claude configuration.
- A Spex workflow creates, resumes, delegates from, or mutates a feature worktree.
- Autonomous or YOLO ship encounters correctable findings after normal retries.
- Codex progress or explicitly enabled experimental Teams behavior is requested.
- Maintainers materialize, validate, test, or release harness-specific plugin distributions.

**Does not apply when**:

- A production OpenCode plugin is requested; this feature provides only the reusable adapter contract and proof fixture.
- A workflow seeks authority for destructive, external, network, credentialed, or out-of-workspace activity; those boundaries remain host/user controlled.
- Historical feature specifications would need rewriting; they remain historical records.
- Teams is not explicitly enabled or safe independence/isolation cannot be established; execution remains sequential.

## Key Decisions

1. **One canonical core with thin distribution adapters.** A single dual-purpose manifest cannot express independent harness ownership, while a Codex fork would duplicate workflows and drift. Staged materialization preserves canonical sources and makes collision/leakage checks reproducible.
2. **Neutral project profile with adapter-owned enforcement.** Inferring intent from installed files or relying on PreToolUse hooks cannot represent requested versus effective security. The profile preserves intent and requires confirmed safer fallback when host capabilities are insufficient.
3. **Validated state identity instead of CWD, environment, or timestamps.** Resolver authority comes from the registered worktree, branch, and spec identity. Timestamp/last-writer-wins was rejected because crashes and clock skew can select the wrong checkout.
4. **Two-phase worktree state transfer.** The worktree candidate is written and read back before the main marker is removed. Failed transfers retain diagnostics rather than creating silent state loss.
5. **Finite recovery episodes.** Recovery defaults to three attempts and 30 minutes, fingerprints repeated/oscillating remedies, and rewinds affected downstream stages. Unlimited retry and fixed retry-then-prompt behavior were both rejected.
6. **Semantic progress and subagent contracts.** Codex receives native progress/transcript presentation and bounded assignments; Claude retains its status-line specialization. Parallel writers require isolated worktrees, while sequential fallback is a valid outcome.
7. **Cross-harness release gates.** Claude-only, Codex-only, combined, leakage, and OpenCode-proof validation must pass before release instead of relying on manual smoke tests.

## Areas Needing Attention

- Confirm the proposed `plugins/` distribution layout preserves existing Claude marketplace compatibility while giving Codex a stable `.codex-plugin/plugin.json` identity.
- Review whether project-local Codex configuration can faithfully enforce all three profiles under trust and managed-policy constraints; the design must fail safely rather than overstate enforcement.
- Scrutinize WorkflowState migration and two-phase transfer for crash windows, linked-worktree Git common-directory behavior, and writable-boundary failures.
- Check recovery fingerprints and downstream invalidation for false equivalence, missed oscillation, or unnecessary rewinds.
- Verify Teams isolation and reconciliation remain experimental and cannot silently share a writable worktree.
- The feature is intentionally broad but cohesive; phase boundaries should remain independently reviewable to keep PR size manageable.

## Open Questions

No open questions identified. Host-version capability differences are resolved at runtime through explicit capability reporting and safer fallback.

## Review Checklist

- [ ] Key decisions are justified
- [ ] Breaking changes are documented with migration guidance
- [ ] Scope matches the stated boundaries
- [ ] Success criteria are achievable
- [ ] No unstated assumptions
- [ ] Claude and Codex distribution identities, manifests, caches, hooks, and project configuration cannot collide
- [ ] Safe, Autonomous, and YOLO boundaries are observable, testable, and never exceed host/user authority
- [ ] State resolution and transfer fail closed without deleting diagnostic evidence
- [ ] Recovery budgets, non-convergence detection, cascade invalidation, and exact resume points are covered
- [ ] Codex progress and Teams degrade safely without Claude-only integrations
- [ ] Release gates validate both distributions alone and together before tagging

---

<!-- Code phase sections are appended below this line by the phase-manager command -->
