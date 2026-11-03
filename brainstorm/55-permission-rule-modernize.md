# Brainstorm: Modernize generated permission rules

**Date:** 2026-11-03
**Status:** active

## Problem Framing

Current Claude Code releases (seen on 2.1.317) warn about the allow rules that spex writes for the YOLO level:

```
⚠ Allow rule "Read(*)" adds nothing to Read's default, which already runs without asking in the working directories. "Read" alone allows every path.
⚠ Allow rule "Edit(*)" lets Edit run without asking only in the working directories. "Edit" alone allows every path.
⚠ Allow rule "Write(*)" lets Write run without asking only in the working directories. "Write" alone allows every path.
```

The harness has changed what `Tool(*)` means for the file tools: it now scopes to the working directories instead of meaning "every path". Older releases treat `Read(*)` as `Read`. The bare form (`Read`, `Edit`, `Write`) means "every path" in both old and new releases, so switching to it needs no version gating.

Two places generate the legacy strings:

- Interactive init: `spex/skills/init/SKILL.md:80` (YOLO allow array)
- Workflow init: `spex/setup.yml:513` (`claude-permissions` step, YOLO `ALLOW`)

`/spex:init --refresh` skips permissions entirely ("Permissions are unchanged"), so every existing project keeps the legacy rules and the warnings until someone edits settings by hand. This repo's own `.claude/settings.json` shows the problem.

`Bash(*)` triggers no warning today, but it follows the same pattern and may get the same treatment in a later release. Bare `Bash` has always meant every command.

## Approaches Considered

### A: Auto-rewrite on refresh, with a report line
- Pros: Existing projects get fixed by the command users already run after upgrading. Only exact legacy spex strings are touched, so user-added rules are safe. Idempotent.
- Cons: Silently changes a possibly committed file (mitigated by the `Migrated:` report line).

### B: Detect and ask on refresh
- Pros: The user explicitly approves every settings change.
- Cons: Adds a prompt to every refresh until accepted. The rewrite is semantics-preserving on older harnesses, so the question adds little.

### C: Fix only the generators (full init)
- Pros: Smallest change. Refresh stays permission-free.
- Cons: Existing projects keep warning until a full re-init, which most users never do.

## Decision

A: auto-rewrite on refresh and report it. New init generates the bare forms. `Bash(*)` is normalized to `Bash` in the same pass.

This stays separate from #52 / [#62](https://github.com/rhuss/cc-spex/issues/62) (moving YOLO to `settings.local.json`), which remains open for the reporter's PR.

## Key Requirements

- New init (both `SKILL.md` and `setup.yml` paths) writes bare `Bash`, `Read`, `Edit`, `Write` instead of `Bash(*)`, `Read(*)`, `Edit(*)`, `Write(*)`.
- `init --refresh` rewrites exactly those four legacy strings in `.claude/settings.json` and `.claude/settings.local.json` when present. No other rule is added, removed, or reordered beyond deduplication.
- After the rewrite, the allow array is deduplicated (for example, when a bare `Read` already exists next to `Read(*)`).
- The migration is idempotent: a second refresh changes nothing and prints nothing.
- Refresh prints a `Migrated:` line naming the file and the rules that changed, and the Step 4 report relays it.
- A missing settings file, missing `permissions.allow`, or invalid JSON is left untouched (invalid JSON produces a warning, never a rewrite).
- Other settings keys (hooks, statusLine, `defaultMode`) are preserved byte-for-byte in meaning.
- README.md and `spex/docs/help.md` show the new rule form wherever the YOLO rules are documented.

## Out of Scope

- Moving YOLO permissions to `settings.local.json` (#52 / [#62](https://github.com/rhuss/cc-spex/issues/62)).
- Anchoring `Bash(*spex-init.sh*)` and `Bash(*spex-ship-statusline.sh*)` (also tracked in #52).
- Codex and OpenCode permission formats.
- Deny/ask rules: spex never writes them.

## Open Questions

- Where should the migration live: in `spex-init.sh` (refresh path) or as a dedicated helper script that #62 could reuse later?
- Should the migration also rewrite legacy rules in the user-level `~/.claude/settings.json`, or stay strictly project-scoped? (Leaning project-scoped.)
- Should `Read` stay in the YOLO list at all, given that the harness says it adds nothing inside the working directories? (It still matters for paths outside them, such as sibling worktrees.)
