# Research: Backpressure Loops

## R1: Where does the implement command live?

**Decision**: The `/speckit-implement` skill is a core speckit command in the upstream plugin, not in cc-spex. We cannot modify it directly from this repo.

**Approach**: For the ship pipeline, modify the implement subagent prompt in `speckit.spex.ship.md` to include per-task test checkpoint instructions. For standalone `/speckit-implement` usage outside ship, this would require an upstream speckit change (out of scope for this feature).

**Alternatives considered**:
- Adding a `before_task`/`after_task` lifecycle hook: speckit doesn't support task-level hooks yet
- Creating a wrapper command: would confuse users with two implement commands

## R2: How does the watch loop persist across polling intervals?

**Decision**: Use Claude Code's `ScheduleWakeup` (dynamic `/loop` mode) for polling persistence. The finish command's watch mode schedules a wakeup after each poll interval, reads state from the state file, and decides whether to continue or exit.

**Rationale**: ScheduleWakeup is the native mechanism for recurring work within a Claude Code session. It survives between turns, doesn't require external schedulers, and the delay is configurable.

**Alternatives considered**:
- CronCreate: Too heavyweight, designed for cross-session persistence
- Manual re-invocation: Requires user action, defeats the purpose
- Background task: Claude Code doesn't support long-running background shells with interactive logic

## R3: Test command auto-detection

**Decision**: Reuse the existing test detection logic from the verify command (`speckit.spex-gates.verify.md`). The pattern checks for: Makefile (`make test`), package.json (`npm test`), go.mod (`go test ./...`), pytest, cargo, etc.

**Rationale**: Consistency with existing spex behavior. No need to build a second detection mechanism.

## R4: State file structure for watch mode

**Decision**: Extend the existing `.specify/.spex-state` JSON with watch-specific fields rather than creating a separate state file. The `mode` field distinguishes `"ship"`, `"flow"`, and `"watch"` states.

**Watch-specific fields**:
```json
{
  "mode": "watch",
  "pr_number": 42,
  "pr_url": "https://github.com/...",
  "watch_started_at": "2026-06-11T10:30:00Z",
  "watch_timeout_minutes": 30,
  "watch_poll_interval_seconds": 60,
  "last_ci_status": "pending|passing|failing",
  "last_ci_check_at": "2026-06-11T10:31:00Z",
  "ci_fix_attempts": 0,
  "last_triage_at": null,
  "triage_count": 0
}
```

**Rationale**: Single state file keeps the statusline script simple (already reads `.spex-state`). The `mode` field is already used by the statusline for ship vs flow rendering.

## R5: Collab triage integration architecture

**Decision**: The watch loop invokes `/speckit-spex-collab-triage --pr <number>` directly when collab is enabled. No extraction or refactoring of the triage command is needed; it already accepts a `--pr` flag and handles the full workflow.

**The integration point**: Before invoking triage, check for new comments since `last_triage_at` via:
```bash
gh api repos/{owner}/{repo}/pulls/{pr}/comments --jq '[.[] | select(.created_at > "LAST_TRIAGE_AT")] | length'
```

**Rationale**: The triage command is already self-contained and handles bot/human comment partitioning, fix application, reply posting, and state tracking. Invoking it as-is is simpler and more maintainable than extracting a subset of its logic.
