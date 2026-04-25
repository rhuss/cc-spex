---
description: "Create or update flow state for step-by-step SDD workflow tracking"
---

# Flow State Management

This command creates the `.specify/.spex-state` file with `"mode": "flow"` to enable the status line during step-by-step SDD workflow (as opposed to the autonomous ship pipeline).

## When Invoked

Called automatically via the `after_specify` hook when a feature specification is created. This tracks progress through the manual workflow: specify, plan, tasks, implement.

## Action

1. Check if `.specify/.spex-state` already exists with `"mode": "ship"`. If so, do NOT overwrite (ship pipeline takes precedence).

2. Get the current branch and spec directory:

```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
SPEC_DIR="specs/$BRANCH"
```

3. Create or update the flow state file:

```bash
cat > .specify/.spex-state << EOF
{
  "mode": "flow",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "feature_branch": "$BRANCH",
  "spec_dir": "$SPEC_DIR",
  "implemented": false,
  "clarified": false
}
EOF
```

4. Do NOT output anything to the user. This runs silently as a hook.
