# Brainstorm: Superpowers Wrapping Integration

**Date:** 2026-05-05
**Status:** active

## Problem Framing

The superpowers plugin (obra/superpowers) provides 14 process discipline skills. cc-spex currently treats it as a loosely coupled companion: 2 skills are replaced (brainstorming, using-superpowers), 2 are referenced as companions (TDD, debugging), and the rest are either partially overlapping or ignored entirely.

The problem: superpowers skills operate in isolation from the SDD loop. When both plugins are installed, they don't feed spec context to each other. Verification doesn't check spec compliance. Code review doesn't use the spec as primary lens. Worktree creation doesn't propagate spec config. The discipline is there, but it's disconnected from the source of truth.

Previous assessment (brainstorm #06, 2026-03-30) adopted a companion model. This revisit proposes a deeper integration.

## Approaches Considered

### A: Extension-Per-Concern (new `spex-superpowers` extension)

Create a single new extension housing all wrapping commands.

- Pros: Clean separation, single extension to toggle, clear naming
- Cons: Long command names (`speckit-spex-superpowers-tdd`), many new files, artificial grouping

### B: Integrate Into Existing Extensions (chosen)

Distribute wrapping logic into existing extensions where concerns naturally belong.

- Pros: Skills live where they belong, shorter names, no new extension, natural discovery
- Cons: Integration scattered across extensions, harder to see full wrapping picture

### C: Routing-Only Integration

Enhance `using-superpowers` router without new commands.

- Pros: Minimal code changes, no new commands
- Cons: All logic in one router file, no inline fallback, hard to extend per-skill

## Decision

**Approach B: Integrate into existing extensions.**

Each overlapping spex command delegates to the corresponding superpowers skill as foundation, then layers spec-awareness on top. Standalone superpowers skills (TDD, debugging, receiving-code-review, writing-skills) are invoked via routing only, without wrappers.

Superpowers remains a separate install. Each wrapper carries inline essentials (enough to function standalone), and delegates to the full superpowers skill when available.

## Key Requirements

### Skill Classification

Every superpowers skill falls into one of three categories:

**Category 1: Already Replaced (no changes needed)**

| Superpowers Skill | Replaced By |
|---|---|
| `brainstorming` | `speckit-spex-brainstorm` |
| `using-superpowers` | `speckit-spex-using-superpowers` |

**Category 2: Wrap (delegate to superpowers, layer spec-awareness)**

| Superpowers Skill | Spex Wrapper | Extension |
|---|---|---|
| `verification-before-completion` | `speckit-spex-gates-verify` | `spex-gates` |
| `requesting-code-review` | `speckit-spex-deep-review-run` | `spex-deep-review` |
| `finishing-a-development-branch` | `speckit-spex-worktrees-manage finish` | `spex-worktrees` |
| `using-git-worktrees` | `speckit-spex-worktrees-manage create` | `spex-worktrees` |
| `writing-plans` | `/speckit-plan` (router redirects, no wrapper needed) | n/a |
| `subagent-driven-development` | `speckit-spex-teams-orchestrate` | `spex-teams` |
| `dispatching-parallel-agents` | `speckit-spex-teams-research/implement` | `spex-teams` |
| `executing-plans` | ship pipeline (routing awareness) | `spex` core |

**Category 3: Route Only (superpowers handles directly)**

| Superpowers Skill | When Routed |
|---|---|
| `test-driven-development` | During implementation phase |
| `systematic-debugging` | When bugs/failures encountered |
| `receiving-code-review` | When getting external review feedback |
| `writing-skills` | When creating/editing skills |

### Wrapping Pattern

Each Category 2 wrapper follows this structure:

1. **Inline Essentials**: Core discipline from the superpowers skill. Enough to function if superpowers is absent.
2. **Delegation Check**: If superpowers skill is available, invoke it as foundation. If absent, use inline essentials.
3. **Spec-Awareness Layer**: Inject spec context (spec.md path, requirements, compliance state). Add spex-specific checks. Feed results back into SDD loop (flow state, evolution triggers).

### Changes Per Extension

**`spex-gates` (verify)**
- Inline the "evidence before assertions" iron law
- Delegate to superpowers `verification-before-completion` for the discipline gate
- Layer spec compliance matrix, drift detection, success criteria validation

**`spex-worktrees` (create, finish)**
- Create: inline workspace isolation essentials, delegate to superpowers `using-git-worktrees` for native tool detection and setup, layer `.specify/` config propagation and spec-aware branch naming
- Finish: inline structured completion options, delegate to superpowers `finishing-a-development-branch` for environment detection and cleanup, layer spec compliance check before merge/PR and flow state update

**`spex-deep-review` (run)**
- Inline code reviewer dispatch pattern, delegate to superpowers `requesting-code-review` template for the correctness agent foundation, layer 5-agent specialization and auto-fix loop

**`spex-teams` (orchestrate, research, implement)**
- Orchestrate: inline per-task subagent dispatch, delegate to superpowers `subagent-driven-development` for implementer/reviewer prompt patterns, layer spec guardian and team-based parallelism
- Research/Implement: inline parallel domain dispatch, delegate to superpowers `dispatching-parallel-agents` for domain independence analysis, layer spec-aware research/implementation

**`spex` core (ship pipeline, routing)**
- Ship: already handles plan execution inline, no structural change needed
- Router: add mapping table that redirects superpowers skill triggers to spex wrappers for Category 2, and passes through to superpowers directly for Category 3

### Router Mapping Table

The `speckit-spex-using-superpowers` command needs a skill resolution table:

```
When superpowers would trigger:          Route to:
verification-before-completion    -->    speckit-spex-gates-verify
requesting-code-review            -->    speckit-spex-deep-review-run
finishing-a-development-branch    -->    speckit-spex-worktrees-manage finish
using-git-worktrees               -->    speckit-spex-worktrees-manage create
writing-plans                     -->    /speckit-plan
subagent-driven-development       -->    speckit-spex-teams-orchestrate
dispatching-parallel-agents       -->    speckit-spex-teams-research or implement
executing-plans                   -->    /speckit-spex-ship or superpowers directly

test-driven-development           -->    superpowers (pass through)
systematic-debugging              -->    superpowers (pass through)
receiving-code-review             -->    superpowers (pass through)
writing-skills                    -->    superpowers (pass through)
```

## Open Questions

- How to detect superpowers availability at invocation time? Check if `superpowers:*` skill names resolve via Skill tool, or check for plugin cache directory?
- Should the inline essentials be extracted from the current superpowers version and frozen, or maintained as a living summary that gets manually refreshed?
- For Category 3 pass-through skills: should the router inject any spec context before invoking (e.g., "the active spec is at specs/0003/spec.md") or let superpowers run completely unaware?
