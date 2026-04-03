# Review Guide: Context Isolation for Workflow Transitions

**Spec:** [spec.md](spec.md) | **Plan:** [plan.md](plan.md) | **Tasks:** [tasks.md](tasks.md)
**Generated:** 2026-04-03

---

## What This Spec Does

Long-running Claude Code sessions degrade as context fills up. When a developer specs, plans, implements, and reviews in a single session, the reviewer carries the implementer's biases. This spec adds context isolation at two workflow transition points: informational `/clear` warnings in the manual workflow, automatic `context: fork` isolation in the ship pipeline, and branch-based spec resolution so review skills work cleanly after a context clear.

**In scope:** Context clear warnings in overlays, branch-based spec resolution for 4 spex skills, forked subagent execution for ship pipeline stages 6-7.

**Out of scope:** Automatic context clearing (users decide), context size monitoring, compaction-based approaches, changes to spec-kit internals.

## Bigger Picture

This follows from the [Anthropic engineering article on harness design for long-running agents](https://www.anthropic.com/engineering/harness-design-long-running-apps), which identifies context degradation and self-evaluation bias as primary failure modes. The cc-spex plugin already has file-based handoffs (spec.md, plan.md, tasks.md) and separate generator/evaluator roles (implement vs. deep-review), but until now nothing encouraged actual context separation between these phases.

This is the first spec to use Claude Code's `context: fork` mechanism for pipeline stage isolation. If the ship pipeline forking works well (US3), the pattern could extend to other heavy stages (specify, plan) in future iterations.

The commands-to-skills migration (completed in v3.0.1) is a prerequisite: `context: fork` only works in skill frontmatter, not the old command format.

---

## Spec Review Guide (30 minutes)

> Focus your time on the parts that most need human judgment. Each section points to specific locations and frames the review as questions.

### Understanding the approach (8 min)

Read [User Story 1](spec.md#user-story-1---context-clear-warnings-in-manual-workflow-priority-p1) and [User Story 2](spec.md#user-story-2---branch-based-spec-resolution-for-spex-skills-priority-p1) together. They form a pair: US1 creates the need for `/clear`, US2 removes the friction from using it.

- Is the `/clear` recommendation the right intervention? Or would `/compact` with a targeted preservation hint be better in practice, even though the spec explicitly rejects it?
- Are both transition points (post-plan-review, post-implementation) equally valuable, or is one more impactful than the other?
- The warnings are always shown regardless of context size. Is that right, or would conditional display (e.g., only after context exceeds 50%) reduce noise for small features?

### Key decisions that need your eyes (12 min)

**Branch resolution via check-prerequisites.sh** ([FR-007](spec.md#functional-requirements))

The spec reuses spec-kit's existing `check-prerequisites.sh --json --paths-only` for branch-to-spec resolution in spex skills. This creates a dependency on spec-kit's internal script interface.
- Question: Is this coupling acceptable? If spec-kit changes `check-prerequisites.sh` output format, four spex skills break simultaneously. Should we wrap it in a spex-owned script instead?

**Agent tool for ship forking vs. frontmatter `context: fork`** ([plan.md Phase 3](plan.md#phase-3-forked-subagent-stages-in-ship-us3))

The plan chose the Agent tool approach over `context: fork` in frontmatter because plugin skills have limitations (hooks, mcpServers, permissionMode are ignored for plugin subagents).
- Question: Has anyone validated that the Agent tool achieves the same context isolation as `context: fork`? The research.md notes this as a decision but doesn't cite evidence.

**Warning placement in overlays** ([FR-001](spec.md#functional-requirements), [FR-002](spec.md#functional-requirements))

Warnings go in the superpowers overlays for `speckit.plan` and `speckit.implement`. This means they only appear when the superpowers trait is enabled.
- Question: Should context clear warnings be visible even without superpowers? If not, users of the basic workflow never see them.

### Areas where I'm less certain (5 min)

- [Assumptions](spec.md#assumptions): The spec assumes `context: fork` works for plugin skills. The Claude Code docs say plugin subagents have restrictions (no hooks, no mcpServers, no permissionMode). The plan accounts for this by using the Agent tool instead, but this is untested. If the Agent tool doesn't provide true context isolation, US3 fails.

- [FR-007](spec.md#functional-requirements): Adding `review-spec` to the branch resolution list was a late addition (from the spec review). The review-spec skill is typically run before implementation, when the user is likely still on the same branch with full context. Is branch resolution useful here, or just noise?

- [Plan Phase 3](plan.md#phase-3-forked-subagent-stages-in-ship-us3): The plan says "prototype before committing to the approach." This is good advice, but the tasks (T008-T011) are written as if the approach is settled. If the prototype fails, what's the fallback?

### Risks and open questions (5 min)

- The pretool-gate hook has a bug where the skill-pending marker isn't cleared when skills are loaded via the new unified system (we hit this during brainstorming). Does this need to be fixed before or alongside this feature? It affects the developer experience of using `/spex:review-code` after `/clear`.

- If a forked subagent for the implement stage ([FR-011](spec.md#functional-requirements)) runs into issues, how does the ship pipeline handle retry? The current oversight decision logic assumes inline execution. Does forked execution change the retry semantics?

- The spec puts US1 and US2 at equal priority (both P1) and the tasks combine them into a single phase. Is there value in being able to ship US1 (warnings) without US2 (branch resolution)?

---
*Full context in linked [spec](spec.md) and [plan](plan.md).*
