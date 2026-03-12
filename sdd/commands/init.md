---
name: sdd:init
description: Initialize or update the project using the `specify` CLI (--refresh for templates, --update to upgrade CLI). Do NOT search for speckit or spec-kit binaries.
argument-hint: "[--refresh | --update]"
---

You MUST complete ALL steps below. Do not stop after Step 1.

## Step 1: Run init script

Run the command from `<sdd-init-command>` in the `<sdd-context>` system reminder. This is your first and only Bash call. Do not run anything else before it.

- If output contains `NEED_INSTALL`: show output, STOP.
- If output contains `ERROR`: show error, STOP.
- If output contains `BEADS_MIGRATION_NEEDED`: go to Step 1b.
- If output contains `READY` or `RESTART_REQUIRED`: **do not summarize yet**, go to Step 2.

## Step 1b: Beads Migration (only if BEADS_MIGRATION_NEEDED)

The beads trait has been removed from SDD. Show the user this message and ask for confirmation:

Use `AskUserQuestion` (`multiSelect: false`, header: "Beads Migration"):

**Message**: "The beads trait has been removed from SDD. Task state is now tracked directly in tasks.md checkboxes, which is simpler and equally persistent via git. The beads integration added unnecessary complexity (Dolt database, bidirectional sync, fragile bd CLI piping) without meaningful benefit."

**Options**:
- "Migrate (recommended)": "Sync closed bd issues to tasks.md checkboxes, strip (bd-xxx) markers, disable beads trait"
- "Skip": "Leave tasks.md as-is (bd markers will remain but beads trait becomes inactive)"

If "Migrate": run the beads migration via Bash:
```bash
# Source the init script to get the migration function
INIT_SCRIPT="<value from sdd-init-command>"
SCRIPT_DIR=$(dirname "$INIT_SCRIPT")
bash -c "source '$INIT_SCRIPT' && do_beads_migration"
```

Then continue to Step 2.

## Step 2: Ask about traits and permissions

You MUST ask the user these two questions using AskUserQuestion before doing anything else:

1. (`multiSelect: true`, header: "Traits"): "Which SDD traits do you want to enable?"
   - "superpowers": "Quality gates on speckit commands (review-spec, review-code, verification)"
   - "teams": "Parallel implementation with spec guardian review via Claude Code Agent Teams (experimental, requires: superpowers)"

2. (`multiSelect: false`, header: "Permissions"): "How should SDD commands handle permission prompts?"
   - "Standard (Recommended)": "Auto-approve SDD plugin scripts (sdd-init.sh, sdd-traits.sh)"
   - "YOLO": "Auto-approve everything: Bash, Read, Edit, Write, MCP, specify CLI"
   - "None": "Confirm every SDD command before execution"

Then apply using `<sdd-traits-command>` from `<sdd-context>`:

```bash
"<value from sdd-traits-command>" init --enable "<selected-traits-as-csv e.g. superpowers>"
"<value from sdd-traits-command>" permissions <none|standard|yolo>
```

If no traits selected, run `init` without `--enable`.

## Step 3: Report

Summarize: traits enabled, permission level. If Step 1 said RESTART_REQUIRED or Step 2 permissions said CHANGED, tell user to restart Claude Code.
