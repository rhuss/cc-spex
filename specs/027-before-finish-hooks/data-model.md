# Data Model: Before/After Finish Hook Support

**Date**: 2026-06-19

## Entities

This feature modifies configuration and documentation files. No new data entities are introduced.

### Hook Entry (existing, in extensions.yml)

A hook entry under `hooks.before_finish` or `hooks.after_finish` in `.specify/extensions.yml`:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| extension | string | yes | Extension ID that owns this hook |
| command | string | yes | Dot-notation command name (e.g., `speckit.spex.smoke-test`) |
| enabled | boolean | no | Whether the hook is active (default: true) |
| optional | boolean | no | Whether user is prompted before execution (default: true) |
| prompt | string | no | Prompt text shown when optional is true |
| description | string | no | Human-readable description of what the hook does |
| condition | string | no | Condition expression (skipped by hook reader, deferred to HookExecutor) |

### Hook Registration (existing, in extension.yml)

A hook entry in an extension's `extension.yml` manifest under `hooks:`:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| command | string | yes | Dot-notation command to invoke |
| optional | boolean | no | Whether user is prompted (default: true) |
| prompt | string | no | Prompt text for optional hooks |
| description | string | no | Description of the hook |
