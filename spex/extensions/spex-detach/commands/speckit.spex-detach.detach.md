---
description: "Enable stealth mode (exclude spec files from git) or archive specs to sibling repo"
argument-hint: "[enable|archive]"
---

# Spex Detach

Manage spec artifact visibility for upstream contributions. Stealth mode uses .git/info/exclude to hide spec files from git without modifying any committed files.

## Subcommands

- **enable** (default): Write .git/info/exclude entries to hide spec artifacts from git
- **archive**: Copy spec artifacts to the configured project-specs sibling repo
- **is-enabled**: Check if the detach extension is active (exit 0 = yes, exit 1 = no)

## Execution

Run the `spex-detach.sh` script:

```bash
DETACH_SCRIPT=".specify/extensions/spex-detach/scripts/spex-detach.sh"
[ -x "$DETACH_SCRIPT" ] || { echo "ERROR: spex-detach.sh not found"; exit 1; }
```

### Subcommand: enable

Write configured exclude paths to .git/info/exclude. Idempotent, preserves existing entries, warns if spec files are already tracked.

```bash
RESULT=$("$DETACH_SCRIPT" enable)
EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ]; then
  ADDED=$(echo "$RESULT" | jq -r '.paths_added | length')
  ALREADY=$(echo "$RESULT" | jq -r '.already_present')
  if [ "$ADDED" -gt 0 ]; then
    echo "Stealth mode enabled: $ADDED paths added to .git/info/exclude"
  else
    echo "Stealth mode already configured ($ALREADY paths present)"
  fi
  # Check for tracked file warnings
  TRACKED=$(echo "$RESULT" | jq -r '.tracked_warning // [] | join(", ")')
  if [ -n "$TRACKED" ]; then
    echo "WARNING: These paths are tracked by git and must be removed from history separately: $TRACKED"
  fi
else
  echo "ERROR: Enable failed"
  echo "$RESULT"
fi
```

### Subcommand: archive

Read configuration from `.specify/extensions/spex-detach/spex-detach-config.yml` and archive spec artifacts to the sibling specs repo.

```bash
RESULT=$("$DETACH_SCRIPT" archive)
EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ]; then
  SKIPPED=$(echo "$RESULT" | jq -r '.skipped // false')
  if [ "$SKIPPED" = "true" ]; then
    REASON=$(echo "$RESULT" | jq -r '.reason')
    echo "Archive skipped: $REASON"
  else
    DEST=$(echo "$RESULT" | jq -r '.archive_path')
    FILES=$(echo "$RESULT" | jq -r '.files_copied')
    COMMITTED=$(echo "$RESULT" | jq -r '.committed')
    echo "Archived $FILES files to: $DEST"
    [ "$COMMITTED" = "true" ] && echo "Auto-committed to project-specs repo."
  fi
else
  echo "ERROR: Archive failed"
  echo "$RESULT"
fi
```
