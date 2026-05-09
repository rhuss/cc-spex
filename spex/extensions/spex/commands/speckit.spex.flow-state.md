---
description: "Create or update flow state for step-by-step SDD workflow tracking"
argument-hint: "[running <phase>|clarified|implemented|gate <name>]"
---

# Flow State Management

This command manages the `.specify/.spex-state` file with `"mode": "flow"` to enable the status line during step-by-step SDD workflow (as opposed to the autonomous ship pipeline).

## Execution

Locate and run the `spex-flow-state.sh` script, passing through all arguments:

```bash
FLOW_STATE="$(find ~/.claude -name 'spex-flow-state.sh' 2>/dev/null | head -1)"
[ -x "$FLOW_STATE" ] || { echo "ERROR: spex-flow-state.sh not found"; exit 1; }
"$FLOW_STATE" "$@"
```

If invoked with no arguments (from the `after_specify` hook), pass `create`:

```bash
"$FLOW_STATE" create
```

If invoked with `--spec-dir` context available (e.g., the spec directory is known), pass it:

```bash
"$FLOW_STATE" create --spec-dir "specs/034-unified-setup-command"
```

## Available Commands

| Command | Hook | What it does |
|---------|------|-------------|
| `create [--spec-dir <dir>]` | `after_specify` | Create or update flow state (preserves gate fields if already exists) |
| `running <phase>` | `before_*` | Set active phase shown as `▶` in status line |
| `running done` | `after_*` | Clear active phase indicator |
| `clarified` | `after_clarify` | Mark clarification complete |
| `implemented` | `after_implement` | Mark implementation complete |
| `gate <name>` | spex-gates hooks | Mark quality gate passed (review-spec, review-plan, review-code) |
| `cleanup` | (manual) | Remove state file |

All commands are silent (no output) unless an error occurs. Ship mode state files are never overwritten.
