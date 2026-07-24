# Quickstart Validation: First-Class Codex Plugin Support

This guide validates the design end to end after implementation. It intentionally references the contracts rather than prescribing implementation bodies.

## Prerequisites

- macOS or Linux with `git`, `jq`, `yq`, Python 3, and `specify` CLI >= 0.12.16
- Current Codex CLI with personal plugin marketplace, hooks, trusted project config, and subagent support
- Claude CLI for regression and coexistence scenarios
- A clean temporary `CODEX_HOME`, Claude plugin home, and disposable Git repositories

## 1. Static and contract validation

```bash
make sync-scripts-check
make validate-contracts
make test-unit
```

Expected: all JSON contracts parse and fixtures validate; canonical/extension scripts match; adapter, state, hook, and profile unit tests pass.

## 2. Materialize each distribution independently

```bash
CLAUDE_OUT=$(mktemp -d)
CODEX_OUT=$(mktemp -d)
make materialize HARNESS=claude OUT="$CLAUDE_OUT"
make materialize HARNESS=codex OUT="$CODEX_OUT"
make validate-materialized CLAUDE_OUT="$CLAUDE_OUT" CODEX_OUT="$CODEX_OUT"
```

Expected:

- Codex output contains `.codex-plugin/plugin.json`; Claude output retains its Claude manifest.
- Both contain the same canonical workflow version and distinct harness identities.
- No unresolved `{harness:*}` tokens, unavailable tool names, foreign status-line instructions, or absolute development/cache paths remain.
- Repeating materialization produces byte-identical inventories and digests.

## 3. Initialize and refresh a Codex repository

In a disposable trusted repository, install the local Codex marketplace plugin and invoke `spex:init`.

Validate:

1. Recommended extensions are gates, deep review, and worktrees.
2. Teams, collaboration, and detach are optional; Teams is labeled experimental.
3. Safe creates no host-policy bypass.
4. Autonomous grants only the enumerated Spex workflow operations.
5. YOLO additionally grants non-destructive workspace-scoped project operations.
6. Network, external side effects, destructive actions, and outside-workspace activity retain approval boundaries.
7. Re-running init preserves selections and unrelated `.codex/config.toml` and `AGENTS.md` content.
8. An unsupported requested profile offers a confirmed safer fallback or leaves configuration byte-identical.

Validate the persisted file against [initialization-profile.schema.json](contracts/initialization-profile.schema.json).

## 4. Verify worktree and state continuity

```bash
make test-worktree-lifecycle RUNS=100
```

The suite must cover transfer interruption at every phase, resume from main and feature worktree, CWD reset after delegation, moved/deleted worktrees, and competing state files.

Expected: zero wrong-checkout mutations. A conflict resolves only when exactly one candidate matches the registered worktree, branch, and spec; otherwise mutation is refused and diagnostics remain. Machine-readable identity validates against [worktree-identity.schema.json](contracts/worktree-identity.schema.json), and state validates against [workflow-state.schema.json](contracts/workflow-state.schema.json).

## 5. Verify bounded ship recovery

Run fixtures for resolvable findings, infeasible requirements, repeated findings, A→B→A oscillation, elapsed deadline, and downstream artifact invalidation.

Expected:

- Default recovery stops at three attempts or 30 elapsed minutes.
- Safe in-scope research/feasibility work proceeds without a routine continuation prompt in Autonomous/YOLO.
- Equivalent or oscillating attempts stop before another cycle.
- Accepted earlier-artifact changes rewind and revalidate affected downstream stages.
- Terminal output contains evidence, attempts, residual risk, affected artifacts, and an exact resume action.

## 6. Verify Codex progress and Teams fallback

Validate emitted events against [progress-event.schema.json](contracts/progress-event.schema.json). Interrupt after a visible transition and confirm durable state agrees on resume.

For Teams, dispatch two independent writers and one dependent assignment using [subagent-assignment.schema.json](contracts/subagent-assignment.schema.json).

Expected: writers use distinct worktrees; the dependent waits for reviewed results. Disable subagents and repeat; the same required work completes sequentially.

## 7. Install distributions alone and together

```bash
make test-install-claude
make test-install-codex
make test-install-combined
```

Expected: manifests, caches, hooks, generated artifacts, and project configuration do not overwrite or misidentify one another. Claude acceptance workflows retain their baseline pass rate.

## 8. Release gate

```bash
make test
make release
```

Expected: release refuses to tag or publish unless script sync, contract validation, both materializations, leakage checks, lifecycle/recovery tests, and all three installation suites pass.
