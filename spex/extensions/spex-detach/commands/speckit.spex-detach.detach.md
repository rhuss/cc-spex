---
description: "Create clean PR branch with spec artifacts stripped, or archive specs to project-specs repo"
argument-hint: "[archive|detach]"
---

# Spex Detach

Manage spec artifact separation for upstream contributions.

## Subcommands

- **detach** (default): Create a clean PR branch with spec artifacts stripped
- **archive**: Copy spec artifacts to the configured project-specs repo

## Step 0: Resolve Plugin Root

Extract the plugin root path from the `<plugin-root>` tag in the `<spex-context>` system reminder. All script references below use this path:

```bash
DETACH_SCRIPT="<PLUGIN_ROOT>/scripts/bash/spex-detach.sh"
```

Replace `<PLUGIN_ROOT>` with the actual path from the system reminder.

## Execution

Run the `spex-detach.sh` script:

```bash
DETACH_SCRIPT="<PLUGIN_ROOT>/scripts/bash/spex-detach.sh"
[ -x "$DETACH_SCRIPT" ] || { echo "ERROR: spex-detach.sh not found"; exit 1; }
```

### Subcommand: detach

Create a clean PR branch by filtering out spec artifacts from the feature branch.

```bash
RESULT=$("$DETACH_SCRIPT" detach)
EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ]; then
  PR_BRANCH=$(echo "$RESULT" | jq -r '.pr_branch')
  FILES=$(echo "$RESULT" | jq -r '.files_changed')
  echo "Clean PR branch created: $PR_BRANCH ($FILES files changed)"
elif [ "$EXIT_CODE" -eq 2 ]; then
  echo "WARNING: No code changes found. All changes are spec-only."
else
  echo "ERROR: Detach failed"
  echo "$RESULT"
fi
```

### Subcommand: archive

Read configuration from `.specify/extensions/spex-detach/spex-detach-config.yml` and archive spec artifacts.

```bash
CONFIG=".specify/extensions/spex-detach/spex-detach-config.yml"
ARCHIVE_PATH=$(yq -r '.archive.path // empty' "$CONFIG" 2>/dev/null)

if [ -z "$ARCHIVE_PATH" ]; then
  echo "Archive path not configured in $CONFIG"
  echo "Set archive.path to your project-specs repo path."
  exit 1
fi

RESULT=$("$DETACH_SCRIPT" archive --target "$ARCHIVE_PATH")
EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ]; then
  DEST=$(echo "$RESULT" | jq -r '.archive_path')
  FILES=$(echo "$RESULT" | jq -r '.files_copied')
  COMMITTED=$(echo "$RESULT" | jq -r '.committed')
  echo "Archived $FILES files to: $DEST"
  [ "$COMMITTED" = "true" ] && echo "Auto-committed to project-specs repo."
else
  echo "ERROR: Archive failed"
  echo "$RESULT"
fi
```

