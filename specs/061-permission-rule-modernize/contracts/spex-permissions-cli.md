# Contract: `spex-permissions.sh`

```text
spex-permissions.sh migrate [--root DIR]
spex-permissions.sh apply [--root DIR] [--default-mode MODE] RULE...
```

- `--root`: project root (default: current directory). Paths in output are relative to it.
- `apply` always targets `.claude/settings.json`.
- `--default-mode`: value for `permissions.defaultMode` (for example `bypassPermissions`).
- `RULE`: one allow rule string per argument, passed verbatim (quote rules with spaces or `*`).

## Output (stderr only, stdout stays empty)

| Line | When |
|------|------|
| `Migrated: <file> permissions: <old> -> <new>[, ...]` | migrate changed a file |
| `Default mode set to <mode> in <file>` | apply changed `permissions.defaultMode` |
| `Permissions configured in <file> (<n> rules added)` | apply finished writing |
| `WARNING: <file> cannot be resolved safely; left unchanged` | an existing settings file (or, for apply, the target path) whose physical path cannot be determined exactly, for example a name ending in a newline; a dangling link or symlink loop counts as a missing file for migrate (silent, FR-011) |
| `WARNING: <file> resolves to the user-level Claude settings; left unchanged` | the project path is (or links to) `~/.claude/settings*.json` or the same files under `$CLAUDE_CONFIG_DIR` |
| `WARNING: jq is not installed; permission rules in <file> not migrated` | migrate without jq (exit 0) |
| `WARNING: <file> is not valid JSON; permission rules not migrated` | migrate, invalid JSON |
| `WARNING: <file> is not valid JSON; permissions not applied` | apply, invalid JSON |
| `WARNING: <file> has an unexpected structure; permissions not applied` | apply, wrong shape |
| `WARNING: could not write <file>; ...` | write failure |
| `ERROR: ...` + usage | unknown subcommand or option |

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | success, including no-op and every `WARNING:` case |
| 2 | usage error |
| 1 | `jq` not installed (apply only) |
