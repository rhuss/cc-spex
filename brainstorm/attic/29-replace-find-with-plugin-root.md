# Brainstorm: Replace find calls with plugin root references

**Date:** 2026-07-02
**Status:** active

## Problem Framing

14 extension command files use `find ~/.claude -name 'script.sh' 2>/dev/null | head -1` to locate helper scripts at runtime. This pattern is slow (traverses the filesystem), fragile (breaks on non-Claude harnesses), and unnecessary: the context hook already injects the plugin root path as `<plugin-root>` in the `<spex-context>` system reminder on every prompt.

Two commands (phase-manager, triage) and parts of ship already use the `<PLUGIN_ROOT>` pattern correctly. The remaining 14 instances are older commands that predate this convention.

## Decision

Replace all `find ~/.claude` patterns with direct `<PLUGIN_ROOT>` references, following the pattern already established in the collab extension commands. This is a mechanical consistency fix with no design decisions.

The pattern is:

```markdown
Extract the plugin root path from the `<plugin-root>` tag in the `<spex-context>` system reminder.

SCRIPT="<PLUGIN_ROOT>/scripts/script-name.sh"

Replace `<PLUGIN_ROOT>` with the actual path from the system reminder.
```

## Scope

16 replacements across 11 files:

| File | Script | Count |
|------|--------|-------|
| spex.ship | spex-ship-state.sh, spex-worktree-cwd.sh | 2+1 |
| spex.finish | spex-ship-state.sh, spex-finish-context.sh | 2 |
| spex.submit | spex-ship-state.sh, spex-finish-context.sh, spex-detach.sh | 3 |
| spex.smoke-test | spex-ship-state.sh | 1 |
| spex.flow-state | spex-flow-state.sh | 1 |
| spex.brainstorm | spex-detach.sh | 1 |
| spex-gates.review-code | spex-flow-state.sh | 2 |
| spex-gates.review-plan | spex-flow-state.sh | 1 |
| spex-gates.review-spec | spex-flow-state.sh | 1 |
| spex-deep-review.run | spex-flow-state.sh | 1 |
| spex-detach.detach | spex-detach.sh | 1 |

## Key Requirements

- Replace `find ~/.claude -name 'X' 2>/dev/null | head -1` with `<PLUGIN_ROOT>/scripts/X`
- Add the standard preamble (extract plugin root from system reminder) where not already present
- No behavioral change for Claude Code users (same scripts get called, just via direct path)
- Faster execution (no filesystem traversal)
- Prerequisite for harness-agnostic operation (removes `~/.claude` assumption)

## Open Questions

None. This is a mechanical refactor following an established pattern.
