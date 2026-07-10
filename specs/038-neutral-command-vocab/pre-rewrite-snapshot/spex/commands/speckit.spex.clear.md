---
description: "Clear spex state: dismiss status line, remove stale flow/ship artifacts"
---

# Clear - Reset Spex State

Remove spex runtime state when things get stuck or after an interrupted workflow.

## What Gets Cleared

1. **Flow/ship state file** (`.specify/.spex-state`) - dismisses the status line
2. **Stale lock files** (`.specify/.spex-lock`) - if present from a crashed run
3. **Ship state via `SHIP_STATE_FILE`** - if the env var points to a worktree copy

## Execution

```bash
# Primary state file
STATE_FILE=".specify/.spex-state"
LOCK_FILE=".specify/.spex-lock"
cleared=0

if [ -f "$STATE_FILE" ]; then
  rm -f "$STATE_FILE"
  cleared=$((cleared + 1))
fi

if [ -f "$LOCK_FILE" ]; then
  rm -f "$LOCK_FILE"
  cleared=$((cleared + 1))
fi

if [ -n "${SHIP_STATE_FILE:-}" ] && [ -f "$SHIP_STATE_FILE" ] && [ "$SHIP_STATE_FILE" != "$STATE_FILE" ]; then
  rm -f "$SHIP_STATE_FILE"
  cleared=$((cleared + 1))
fi
```

## Report

If `cleared > 0`:
```
Cleared spex state. Status line dismissed.
```

If `cleared == 0`:
```
No active spex state to clear.
```

## What This Does NOT Do

- Does not remove specs, plans, tasks, or any project artifacts
- Does not re-run initialization or reconfigure extensions
- Does not touch git branches or worktrees

For full project re-initialization, use `/spex:init`.
