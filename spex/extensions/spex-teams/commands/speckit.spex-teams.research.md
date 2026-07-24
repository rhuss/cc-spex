---
description: "Parallel codebase research for planning via parallel agent teams"
---

# Teams Research: Parallel Codebase Exploration for Planning

Research parallelism is read-only. It may share a repository view because it
does not reconcile code, but it still requires explicit bounded assignments.

## Prerequisites and Fallback

Verify `{harness:agent-teams}` is available and that the validated feature
worktree can be exposed read-only to subagents. If the capability, repository
identity, or read-only restriction cannot be established, research every topic
sequentially in the lead session. Never turn a research assignment into a
writer merely to preserve parallelism.

## Identify Independent Topics

Read the relevant spec sections and identify focused questions about existing
code, patterns, integration points, tests, and constraints. Add dependencies
between topics when one requires another's answer.

- With fewer than 2 independent topics, research sequentially.
- With 2+ independent topics, dispatch at most four read assignments.
- Merge related or overlapping questions rather than duplicating broad scans.

## Shared Read View

All research agents may use the **same shared read view** and the same explicit
absolute `workdir`: the validated active feature worktree at its recorded HEAD.
Set `kind: read`; do not create isolated writer branches or worktrees for
research. Sharing is permitted only because every assignment prohibits file,
index, branch, configuration, lockfile, and external mutations.

Each assignment receives only:

- a unique assignment ID and one focused objective;
- the relevant spec context, not the complete unrelated specification;
- its topic/task IDs and dependencies;
- the absolute shared read-view workdir;
- the inherited effective security profile without escalation; and
- required evidence: files examined, patterns, integration points,
  constraints, and recommendations.

Before dispatch, record the shared HEAD and worktree status. After all agents
return, verify that HEAD, index, and tracked/untracked status are unchanged. If
any research agent mutated the shared view, reject that result, preserve the
diagnostic evidence, restore no files automatically, and continue through the
safe sequential fallback after the user-owned change is resolved.

## Dispatch and Consolidation

{harness:agent-teams-research-dispatch}
Dispatch the independent read assignments against the explicit shared workdir.
If the harness cannot guarantee read-only behavior, use sequential research.
{/harness:agent-teams-research-dispatch}

Wait for every research result. Consolidate only evidence relevant to the
plan, resolve contradictions against repository sources, call out remaining
unknowns, and cite concrete files/functions. The lead owns the resulting plan;
research agents do not edit planning artifacts.

## Key Invariants

- Research shares a read view; concurrent implementation never does.
- Every path is explicit and absolute.
- Parallelism requires at least two genuinely independent topics.
- Capability or safety uncertainty produces sequential fallback, not weaker
  isolation.
