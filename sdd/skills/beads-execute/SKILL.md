---
name: beads-execute
description: Beads-driven task execution - bootstraps issues from tasks.md, uses bd ready for scheduling, bd backup for persistence
---

# Beads-Driven Task Execution

## Overview

This skill handles implementation execution through beads, providing persistent memory and dependency-aware task scheduling across sessions.

## Prerequisites

Check that the `bd` CLI is available and the database is initialized:

```bash
if ! command -v bd &>/dev/null; then
  echo "ERROR: beads CLI (bd) is not installed."
  echo ""
  echo "Install beads to use this feature:"
  echo "  See https://github.com/beads-project/beads for installation instructions"
  echo ""
  echo "Without beads, use /speckit.implement directly for standard task execution."
  exit 1
fi

# Initialize database if not present (safety net for cases where
# sdd-traits.sh enable was not run, e.g. manual trait config edits)
if ! bd list --json &>/dev/null; then
  bd init
  echo "Initialized beads database."
fi

# Restore database from backup files if available (e.g. after fresh clone)
bd backup restore 2>/dev/null || true
```

If `bd` is not available, report the error and stop. Do not fall back to non-beads execution within this skill.

## 1. Bootstrap Beads Issues from tasks.md

Use the sync script to programmatically create bd issues from tasks.md:

```bash
SPEC_DIR="specs/[feature-name]"

# Run forward sync to create issues, map dependencies, add bd markers
"<sdd-beads-sync-command>" "$SPEC_DIR/tasks.md"
```

This handles:
- Creating phase epics and child task issues
- Mapping sequential and inter-phase dependencies
- Marking already-completed tasks as closed
- Inserting `(bd-XXXX)` markers into tasks.md for traceability
- Idempotent re-runs (skips already-synced tasks)

## 2. Dependency-Aware Task Scheduling

Use `bd ready` to get the next unblocked task:

```bash
# Get next ready task (all dependencies resolved)
NEXT=$(bd ready --json 2>/dev/null | jq -r 'if type == "object" and .error then empty else .[0] // empty end' 2>/dev/null || true)

while [ -n "$NEXT" ]; do
  TASK_ID=$(echo "$NEXT" | jq -r '.id')
  TASK_TITLE=$(echo "$NEXT" | jq -r '.title')

  echo "Working on: $TASK_TITLE"

  # Execute the task (implementation work happens here)
  # ... task-specific implementation ...

  # Mark task complete (optionally add a reason with -r)
  bd close "$TASK_ID" -r "Completed: brief summary"
  # To add a detailed comment, use a separate command:
  # bd comments add "$TASK_ID" "Detailed notes here"

  # Persist state for git tracking
  bd backup

  # Get next ready task
  NEXT=$(bd ready --json 2>/dev/null | jq -r 'if type == "object" and .error then empty else .[0] // empty end' 2>/dev/null || true)
done
```

## 3. Git-Backed State Persistence

After completing each task (or group of parallel tasks), persist state:

```bash
bd backup
```

This ensures:
- Task completion state survives session restarts
- Other agents can see which tasks are done
- Progress is recoverable if a session is interrupted

## 4. Discovered Work Tracking

During implementation, new tasks may emerge. Create bd issues for them but do NOT edit tasks.md directly:

```bash
# When implementation reveals new work not in tasks.md
# Keep titles crisp (under 80 chars) and put details in a comment
bd create "DISCOVERED: [short summary]" --labels "discovered"
# Then add the detailed description as a comment:
bd comments add "$ISSUE_ID" "Full detailed description of the discovered work"
```

Discovered work should be:
- Clearly labeled as discovered (not in original tasks.md)
- Given appropriate dependencies
- Completed before the phase it belongs to is considered done

The reverse sync at completion will add discovered issues to tasks.md automatically.

## 5. Completion

When `bd ready --json` returns an empty list and all issues are done:

```bash
# Verify all issues are resolved
bd list --status open
# Should return empty

# Reverse sync to update tasks.md with all status changes and discovered work
"<sdd-beads-sync-command>" "$SPEC_DIR/tasks.md" --reverse

# Final backup
bd backup
```

Report the beads execution summary:
- Total tasks executed
- Discovered work items
- Any blocked tasks remaining

## bd CLI Usage Rules

**IMPORTANT**: When querying beads JSON output, always use `jq` or the bd CLI's
built-in filtering flags. NEVER use inline Python one-liners to parse JSON, as
they cause escaping errors in shell contexts.

### Error handling

`bd` returns a JSON error object `{"error": "..."}` when it fails (e.g., stale
database). All jq filters MUST check for errors before processing results.
Also, NEVER use `2>&1` when piping bd output to jq. Stderr noise corrupts the
JSON stream. Use `2>/dev/null` to discard stderr.

**IMPORTANT:** `bd` may also output non-JSON text to stdout (e.g., connection
errors, server not running). The `2>/dev/null` on `bd` only suppresses stderr.
You MUST also add `2>/dev/null` to `jq` and provide a fallback with `||` to
handle non-JSON input gracefully. Without this, `jq` will crash with
"parse error: Invalid numeric literal".

**Error-safe wrapper** (use this pattern for all bd JSON queries):
```bash
# Guard: type == "object" and .error  (plain .error crashes on arrays)
# Note: 2>/dev/null on BOTH bd and jq, plus || fallback for non-JSON stdout
bd show "$ID" --json 2>/dev/null | jq 'if type == "object" and .error then error(.error) else .[0] | {id, title, status} end' 2>/dev/null || echo '{}'
bd list --json 2>/dev/null | jq 'if type == "object" and .error then error(.error) else . end' 2>/dev/null || echo '[]'
bd ready --json 2>/dev/null | jq 'if type == "object" and .error then error(.error) else . end' 2>/dev/null || echo '[]'
```

### Correct patterns

Note: `bd show` and `bd ready` return arrays, not bare objects. Use `.[0]` to
get the first element, or `.[]` to iterate.

```bash
# List open tasks (excluding epics)
bd list --type task --json 2>/dev/null | jq -r 'if type == "object" and .error then error(.error) else .[] | "\(.id): \(.title)" end' 2>/dev/null || true

# Get ready tasks
bd ready --json 2>/dev/null | jq -r 'if type == "object" and .error then error(.error) else .[] | "\(.id): \(.title)" end' 2>/dev/null || true

# Filter by label
bd list --label "phase:1" --json 2>/dev/null | jq -r 'if type == "object" and .error then error(.error) else .[] | .title end' 2>/dev/null || true

# Count open issues
bd list --json 2>/dev/null | jq 'if type == "object" and .error then error(.error) else length end' 2>/dev/null || echo 0

# Show specific fields (bd show returns an array, use .[0])
bd show "$ID" --json 2>/dev/null | jq 'if type == "object" and .error then error(.error) else .[0] | {id, title, status} end' 2>/dev/null || echo '{}'

# Bulk create issues from a markdown file (use -f or --file, NOT --from-file)
bd create -f tasks.md --dry-run
```

### NEVER do this

```bash
# WRONG - Python one-liners break on shell escaping
bd list --json | python3 -c "import json,sys; ..."

# WRONG - 2>&1 mixes stderr text into JSON, corrupting it for jq
bd show "$ID" --json 2>&1 | jq '.[0]'

# WRONG - no error check, crashes on {"error": "..."} response
bd show "$ID" --json | jq '.[0] | {id, title, status}'

# WRONG - bd show returns an array, not an object
bd show "$ID" --json | jq '{id, title, status}'
```

## Integration

**This skill is invoked by:**
- The beads trait overlay for `/speckit.implement`

**This skill requires:**
- `bd` CLI installed and available
- `jq` for JSON parsing (do NOT use inline Python)
- tasks.md with parseable task structure
