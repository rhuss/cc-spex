
<!-- SDD-TRAIT:beads -->
## STOP: Beads Pre-flight Check (MANDATORY)

Before executing ANY task, you MUST verify beads issues are synced.
Run this check FIRST, before any implementation work:

```bash
ISSUE_COUNT=$(bd list --json 2>/dev/null | jq 'if type == "object" and .error then 0 else length end')
```

- If `bd` is not installed: **STOP.** Report error. Do not fall back to non-beads execution.
- If issue count is 0 but tasks.md has tasks: **STOP.** Run `"<sdd-beads-sync-command>" "$SPEC_DIR/tasks.md"` first to create beads issues, then re-check.
- If issues exist: proceed to beads-execute.

## Beads Task Execution (MANDATORY)

Do NOT execute tasks using the standard implementation loop in this command.
Instead, you MUST use {Skill: sdd:beads-execute} for ALL task execution.

This skill handles:
1. Dependency-aware scheduling via `bd ready --json`
2. Marking tasks complete via `bd close <id> -r "reason"` (NOT by editing tasks.md)
3. Git-backed state persistence via `bd backup` after each task
4. Discovered work tracking via `bd create`
5. Reverse sync at completion to update tasks.md

**Rules:**
- Do NOT update tasks.md checkboxes during implementation. Task state lives in bd.
- Do NOT use `--comment` with `bd close` (it does not exist). Use `-r "reason"` instead.
- Use `bd comments add <id> "text"` for detailed notes.
- Always use `jq` to parse bd JSON output. NEVER use inline Python one-liners.
- NEVER use `2>&1` when piping to jq (stderr corrupts JSON). Use `2>/dev/null`.
- Always guard jq filters: `if type == "object" and .error then error(.error) else ... end`
