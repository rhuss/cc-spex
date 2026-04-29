---
description: "Create or update flow state for step-by-step SDD workflow tracking"
argument-hint: "[clarified|implemented]"
---

# Flow State Management

This command manages the `.specify/.spex-state` file with `"mode": "flow"` to enable the status line during step-by-step SDD workflow (as opposed to the autonomous ship pipeline).

## When Invoked

- **No arguments** (via `after_specify` hook): Creates initial flow state after specification.
- **`clarified`** (via `after_clarify` hook): Marks clarification as complete.
- **`implemented`** (via `after_implement` hook): Marks implementation as complete.

## Action: Create (no arguments)

1. Check if `.specify/.spex-state` already exists with `"mode": "ship"`. If so, do NOT overwrite (ship pipeline takes precedence).

2. Get the current branch and spec directory:

```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
SPEC_DIR="specs/$BRANCH"
```

3. Create the flow state file:

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

## Action: Update clarified

When invoked with argument `clarified`:

1. Check if `.specify/.spex-state` exists and has `"mode": "flow"`. If not, skip silently.

2. Update the `clarified` field to `true`:

```bash
STATE_FILE=".specify/.spex-state"
if [ -f "$STATE_FILE" ] && jq -e '.mode == "flow"' "$STATE_FILE" >/dev/null 2>&1; then
  jq '.clarified = true' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
fi
```

3. Do NOT output anything to the user. This runs silently as a hook.

## Action: Update implemented

When invoked with argument `implemented`:

1. Check if `.specify/.spex-state` exists and has `"mode": "flow"`. If not, skip silently.

2. Update the `implemented` field to `true`:

```bash
STATE_FILE=".specify/.spex-state"
if [ -f "$STATE_FILE" ] && jq -e '.mode == "flow"' "$STATE_FILE" >/dev/null 2>&1; then
  jq '.implemented = true' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
fi
```

3. Do NOT output anything to the user. This runs silently as a hook.
