# Data Model: First-Class Codex Plugin Support

## InitializationProfile

Project-owned declaration of the selected harness behavior.

| Field | Type | Rules |
|---|---|---|
| `schema_version` | string | Required semantic contract version. |
| `active_harness` | enum | `claude`, `codex`, or `opencode`. |
| `enabled_extensions` | set[string] | Always includes `spex`; dependency closure must validate. |
| `requested_security` | enum | `safe`, `autonomous`, `yolo`. |
| `effective_security` | enum | Must be equal to or safer than requested; change requires confirmation. |
| `capabilities` | map | Observed harness/version support with native/adapted/degraded/unavailable status. |
| `config_revision` | integer | Monotonically increases after successful atomic refresh. |
| `updated_at` | timestamp | UTC RFC 3339. |

Lifecycle: `absent → proposed → validated → persisted → refreshed`. A failed validation leaves the prior persisted revision unchanged.

## HarnessAdapter

Thin mapping from shared Spex semantics to a host.

Fields include stable ID/version, manifest/config roots, capability declarations and degradations, command token map, hooks/config installer, permission mappings, progress presenter, and subagent/isolation policy. Adapter output is valid only when every required shared capability is native, explicitly adapted, or explicitly degraded.

## PluginDistribution

A staged, installable harness package. Identity consists of harness, plugin name/version, marketplace identity, manifest path, materialization digest, and output inventory. Claude and Codex distributions must have disjoint manifests, caches, and project configuration targets.

Lifecycle: `source → staged → adapted → validated → packaged`. Validation failure deletes/rejects staging output and never modifies canonical sources.

## FeatureContext

Validated identity for all worktree-sensitive activity.

| Field | Type | Rules |
|---|---|---|
| `repository_root` | absolute realpath | Belongs to the Git common directory. |
| `git_common_dir` | absolute realpath | Stable across linked worktrees. |
| `active_worktree` | absolute realpath | Existing registered worktree. |
| `feature_branch` | string | Matches the worktree HEAD and spec directory. |
| `spec_dir` | absolute realpath | Existing feature directory owned by the branch. |
| `state_file` | absolute realpath | Canonical location inside the active feature context. |

## WorkflowState

Durable authority for a feature workflow. Contains schema/revision/workflow ID, FeatureContext, stage progress, completed gates, status, recovery episode, resume point, timestamps, and conflict/transfer diagnostics.

Status transitions:

```text
running ──authority boundary──> paused_authority ──resume──> running
running ──recoverable finding─> recovering ──accepted──> running
recovering ──budget exhausted─> failed_budget
recovering ──repeat/oscillate─> failed_nonconvergent
running/recovering ──invalid identity─> failed_validation
running ──final gate passed──> completed
```

Every mutation compares an expected revision and atomically writes the next revision. Terminal state remains available until explicit cleanup.

## StateCandidate and ConflictDiagnostic

A candidate is a discovered WorkflowState plus its filesystem and Git validation results. A conflict diagnostic preserves all candidates and rejection reasons. Resolution succeeds only when exactly one candidate matches the existing worktree, branch, and spec identity; timestamps never determine authority.

## WorktreeTransfer

Two-phase handoff identified by `transfer_id`.

```text
prepared_main → candidate_written → candidate_validated → committed_worktree → main_removed
                                  ↘ failed (preserve evidence, no mutation authority)
```

## RecoveryEpisode and RecoveryAttempt

An episode records objective, originating stage/finding fingerprint, budget, deadline, attempts, affected artifacts/gates, outcome, and resume point. Each attempt records remedy fingerprint, evidence, artifact hashes, result fingerprint, timestamps, and outcome. Defaults are three attempts and 1,800 elapsed seconds; configured values must remain finite.

## ProgressEvent

Ordered semantic event with workflow ID, revision/sequence, timestamp, stage, kind (`normal`, `delegated`, `recovery`, `pause`, `complete`), status, objective, and optional recovery attempt. Adapters may change presentation, never meaning or ordering.

## SubagentAssignment and SubagentResult

Assignment fields include ID, read/write kind, absolute workdir, spec/task scope, effective security, allowed files/contracts, dependencies, and required evidence. Write assignments require isolated worktrees when concurrent. A result includes status, summary, changed files, evidence, checks, and residual risks. Dependents remain blocked until the orchestrator reviews and accepts prerequisite results.

## CapabilityReport

Per harness/version declaration of native, adapted, degraded, or unavailable support for installation, interaction, hooks, permissions, progress, context lifecycle, worktrees, and subagents. Every degradation includes reason and fallback. InitializationProfile embeds the observed report; released adapters publish the declared report.
