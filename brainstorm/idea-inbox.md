# Idea Inbox

Ideas captured from code reviews for future brainstorming.

### flow-state-unconditional-update

- **Source**: deep-review
- **Date**: 2026-07-02
- **Reference**: 033-plugin-root-refs
- **Summary**: The `&&` chain in flow state update commands prevents `implemented` from running when `gate review-code` fails, contradicting the "MANDATORY: regardless of gate outcome" instruction.

> The `FLOW_STATE gate review-code && FLOW_STATE implemented` pattern in deep-review.run.md and review-code.md gates the `implemented` call on the success of `gate review-code`. If the gate fails, the status line never shows `R checkmark`. Restructuring to `{ gate review-code || true; implemented; }` would ensure the terminal state update always fires. This affects 2 files and should be a standalone fix.
