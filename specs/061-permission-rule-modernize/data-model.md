# Data Model: Modernize Generated Permission Rules

## Settings file

Path: `.claude/settings.json` or `.claude/settings.local.json` (project root relative).

```json
{
  "permissions": {
    "defaultMode": "bypassPermissions",
    "allow": ["Bash", "Read", "Edit", "Write", "Skill", "Bash(npm test)"],
    "deny": [],
    "ask": []
  },
  "hooks": {},
  "statusLine": {}
}
```

Only `permissions.allow` is changed by `migrate`. `apply` additionally appends rules and may set `permissions.defaultMode`. All other keys pass through unchanged.

### Shape guard (migrate is a no-op otherwise)

| Condition | Behavior |
|-----------|----------|
| File missing | skip, silent |
| Not valid JSON | skip, `WARNING:` |
| Top level not object | skip, silent |
| `permissions` missing or not object | skip, silent |
| `permissions.allow` missing or not array | skip, silent |

## Rewrite map

| Legacy (exact string) | Bare |
|-----------------------|------|
| `Bash(*)` | `Bash` |
| `Read(*)` | `Read` |
| `Edit(*)` | `Edit` |
| `Write(*)` | `Write` |

Rules:

1. Map each string entry through the table; non-matching and non-string entries pass through.
2. `pairs` = legacy strings found, in first-occurrence order, each once.
3. `pairs` empty: no change, no write, no output.
4. `pairs` non-empty: drop later occurrences of `Bash`, `Read`, `Edit`, `Write`; keep the first at its position; keep all other entries (including duplicates) in place.

### Example

Before: `["Skill", "Read(*)", "Bash(npm test)", "Read", "Edit(*)", "Skill"]`

After: `["Skill", "Read", "Bash(npm test)", "Edit", "Skill"]`

Output: `Migrated: .claude/settings.json permissions: Read(*) -> Read, Edit(*) -> Edit`
