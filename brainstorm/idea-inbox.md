# Idea Inbox

Ideas captured from code reviews for future brainstorming.

### flow-state-unconditional-update

- **Source**: deep-review
- **Date**: 2026-07-02
- **Reference**: 033-plugin-root-refs
- **Summary**: The `&&` chain in flow state update commands prevents `implemented` from running when `gate review-code` fails, contradicting the "MANDATORY: regardless of gate outcome" instruction.

> The `FLOW_STATE gate review-code && FLOW_STATE implemented` pattern in deep-review.run.md and review-code.md gates the `implemented` call on the success of `gate review-code`. If the gate fails, the status line never shows `R checkmark`. Restructuring to `{ gate review-code || true; implemented; }` would ensure the terminal state update always fires. This affects 2 files and should be a standalone fix.

### github-issue-brainstorm-flow

- **Source**: conversation
- **Date**: 2026-07-08
- **Reference**: v6.0.0 planning
- **Summary**: Add a full GitHub-based flow where a GitHub issue triggers brainstorm document creation through interactive dialogues, connecting issue tracking to the SDD pipeline entry point.

> Instead of starting brainstorming locally, allow the workflow to begin from a GitHub issue. The issue would serve as the seed, and an interactive dialogue (possibly via issue comments or a dedicated command) would refine the idea into a structured brainstorm document. This bridges the gap between project management (issues) and the spec-driven development pipeline (brainstorm -> specify -> plan -> implement).

### detach-stale-script-sync

- **Source**: triage
- **Date**: 2026-07-15
- **Reference**: PR #38 (042-detach-hardening)
- **Summary**: The stale spex-detach.py copy at spex/extensions/spex/scripts/ diverges from the canonical copy at spex/extensions/spex-detach/scripts/. The make sync-scripts pipeline needs to handle cross-extension script references, and the deep-review.run.md harness marker needs to be split outside the bash block to avoid syntax errors on adapter substitution.

> CodeRabbit flagged a stale spex-detach.py at spex/extensions/spex/scripts/ missing the verify command, archive move/brainstorm support, and hardened failure cleanup. Separately, the {harness:codex-review-tool} marker in deep-review.run.md is inside an active bash block, causing syntax errors when adapters substitute descriptive text. Both are cross-extension maintenance issues.
