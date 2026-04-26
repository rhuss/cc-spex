# Code Review: spex-collab Extension

**Spec:** specs/018-collab-extension/spec.md
**Date:** 2026-04-26
**Reviewer:** Claude (speckit.spex-gates.review-code)

## Compliance Summary

**Overall Score: 100%**

- Functional Requirements: 14/14 (100%)
- Error Handling: N/A (Markdown commands, not compiled code)
- Edge Cases: 3/3 (100%) - ship mode, disabled extension, single phase fallback
- Non-Functional: 3/3 (100%) - zero ship mode overhead, vanilla behavior preserved, cross-session state

## Extra Features (Not in Spec)

### Session resume for phase-split
**Location:** phase-split.md:35-48
**Description:** When a phase plan already exists in .spex-state, the command asks whether to reuse it or create a new one.
**Assessment:** Helpful addition. Prevents accidental overwrite of a confirmed phase plan.
**Recommendation:** Add to spec as FR-015 if keeping.

---

## Code Review Guide (30 minutes)

This section guides a code reviewer through the implementation changes,
focusing on high-level questions that need human judgment.

**Changed files:** 6 new files, 4 modified files (extension commands, gate modifications, init script, test, README)

### Understanding the changes (8 min)

- Start with `spex/extensions/spex-collab/extension.yml`: This is the extension manifest that declares all commands, hooks, and dependencies. It tells you what the extension provides and where it integrates.
- Then `spex/extensions/spex-collab/commands/speckit.spex-collab.reviewers.md`: This is the core value proposition, generating REVIEWERS.md for spec PRs. Understanding this command's flow explains what reviewers will actually see.
- Question: Does the hook placement (`after_tasks` for reviewers, `before_implement` for phase-split) make sense for the workflow, or should the reviewers command fire at a different lifecycle point?

### Key decisions that need your eyes (12 min)

**Ship mode guard pattern** (`speckit.spex-collab.reviewers.md:12-19`, relates to [FR-006](spec.md))

All three commands check both `mode: "ship"` and `status: "running"` in .spex-state. This is a belt-and-suspenders approach matching existing spex-gates patterns.
- Question: Is checking both `mode` and `status` the right pattern, or should one be sufficient?

**REVIEWERS.md re-run boundary detection** (`speckit.spex-collab.reviewers.md:62-68`, relates to [FR-002](spec.md))

The re-run logic uses `## Phase [0-9]` regex to find the boundary between spec sections (regenerated) and code phase sections (preserved).
- Question: Is this heading pattern robust enough, or could a spec section accidentally match `## Phase` and cause content loss?

**Phase state persistence via jq** (`speckit.spex-collab.phase-split.md:129-139`, relates to [FR-013](spec.md))

The collab namespace in .spex-state stores phase_plan, completed_phases, and pr_base_branch. State updates use jq with tmp file swap.
- Question: Is the jq tmp-file pattern safe enough for concurrent access, or should we add file locking?

**Gate modification for console-only output** (`speckit.spex-gates.review-spec.md:254-263`, relates to [FR-014](spec.md))

When spex-collab is enabled, review-spec and review-plan suppress file output (no REVIEW-SPEC.md, no REVIEW-PLAN.md). The check uses extension.yml file existence.
- Question: Should the check use the extension registry instead of file existence, to handle cases where the extension exists but is disabled?

### Areas where I'm less certain (5 min)

- `speckit.spex-collab.reviewers.md:28-34` ([FR-007](spec.md)): The disabled extension guard checks for `extension.yml` file existence. This works when the extension directory is absent, but if someone disables the extension via `specify extension disable spex-collab` while the files remain on disk, this check would still find the file and proceed. A registry-based check would be more accurate.

- `speckit.spex-collab.phase-manager.md:76-90`: The code review gate invocation checks for REVIEW-CODE.md existence. In a phase-based workflow, the same REVIEW-CODE.md from a previous phase might exist, potentially leading the phase-manager to use stale review data for the current phase.

- `speckit.spex-collab.phase-split.md:113-120`: The config template path `.specify/extensions/spex-collab/collab-config.yml` is used for reading pr_base_branch, but the actual config location depends on how spec-kit installs extension configs. This path may not match the runtime location.

### Deviations and risks (5 min)

- No deviations from [plan.md](plan.md) were identified. The implementation follows the planned file structure, command patterns, and data model exactly.

- Risk: The phase-manager command relies on the user manually invoking it between phases. If the user forgets, phases accumulate without PR creation. The `before_implement` hook instructs the user, but there is no enforcement mechanism.

- Risk: The `auto_generate_reviewers` config flag in `config-template.yml` is declared but never checked in the reviewers command. This means disabling auto-generation via config has no effect.
