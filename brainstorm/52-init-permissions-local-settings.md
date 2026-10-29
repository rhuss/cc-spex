# Brainstorm: Init permissions in local settings

**Date:** 2026-10-29
**Status:** active
**Issue:** https://github.com/rhuss/cc-spex/issues/62

## Problem Framing

`/spex:init` writes the chosen permission block into `.claude/settings.json` (`spex/skills/init/SKILL.md:72-85`). That file is normally committed, so choosing YOLO (`defaultMode: "bypassPermissions"` plus `Bash(*)`, `Edit(*)`, `Write(*)`) puts one person's trust decision into every clone of the repo, and nobody else ever sees the question that explained it.

Related findings from the assessment:

- The statusline is already written to `.claude/settings.local.json` (`spex/scripts/spex-init.sh:174`), so the permission write is the odd one out.
- `.specify/spex.json` stores `"security": "yolo"`, and setup reuses the stored value when no explicit input is given. A teammate who re-runs init can inherit YOLO without being asked.
- Codex YOLO writes `sandbox_mode = "danger-full-access"` and `approval_policy = "never"` to the project `.codex/config.toml`, which has the same problem.
- The Standard rules `Bash(*spex-init.sh*)` and `Bash(*spex-ship-statusline.sh*)` match any command that contains the filename. The init script is invoked as a bare absolute path (`spex/scripts/hooks/context-hook.py:131,157`), not through `bash`, so the reporter's suggested `Bash(bash */spex-init.sh*)` would not match the real invocation.

## Approaches Considered

### A: Welcome the reporter's PR
- Pros: The reporter already offered a PR and understands the issue. The fix is small and well scoped.
- Cons: The `spex.json` and Codex angles may need follow-up beyond the PR.

### B: Fix it ourselves
- Pros: One coherent change across Claude, Codex and the stored declaration.
- Cons: Turns down a willing contributor.

### C: Split the work
- Pros: Reporter handles the settings move, we handle propagation and the wildcard rules.
- Cons: Two changes to coordinate for a small fix.

## Decision

A: reply on the issue, agree with the direction, point out the extra angles, and invite the PR.

## Key Requirements

- Personal permission choices (at least YOLO) go to `.claude/settings.local.json`.
- The option text says where the permissions are written.
- Standard rules are anchored so they do not match commands that only mention the script name.
- README.md and `spex/docs/help.md` reflect the new location.

## Open Questions

- Should Standard also move to `settings.local.json`, or stay in `settings.json` as project policy?
- Should a stored `"security": "yolo"` in `.specify/spex.json` require explicit confirmation before it is applied for another user?
- Should Codex YOLO move out of the project `.codex/config.toml`?
- Which anchored rule form matches the absolute-path invocation reliably (for example `Bash(/*/spex-init.sh*)`)?
