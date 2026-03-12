---
name: sdd:init
description: Initialize or update the project using the `specify` CLI (--refresh for templates, --update to upgrade CLI). Do NOT search for speckit or spec-kit binaries.
argument-hint: "[--refresh | --update]"
---

You MUST complete ALL THREE steps below. Do not stop after Step 1.

## Step 1: Run init script

Run the command from `<sdd-init-command>` in the `<sdd-context>` system reminder. This is your first and only Bash call. Do not run anything else before it.

- If output contains `NEED_INSTALL`: show output, STOP.
- If output contains `ERROR`: show error, STOP.
- If output contains `READY` or `RESTART_REQUIRED`: **do not summarize yet**, go to Step 2.

## Step 2: Ask about traits and permissions

You MUST ask the user these two questions using AskUserQuestion before doing anything else:

1. (`multiSelect: true`, header: "Traits"): "Which SDD traits do you want to enable?"
   - "superpowers": "Quality gates on speckit commands (review-spec, review-code, verification)"
   - "beads": "Beads memory integration for persistent task execution across sessions"
   - "teams": "Parallel implementation with spec guardian review via Claude Code Agent Teams (experimental, requires: superpowers, beads)"

2. (`multiSelect: false`, header: "Permissions"): "How should SDD commands handle permission prompts?"
   - "Standard (Recommended)": "Auto-approve SDD plugin scripts (sdd-init.sh, sdd-traits.sh)"
   - "YOLO": "Auto-approve everything: Bash, Read, Edit, Write, MCP, specify CLI"
   - "None": "Confirm every SDD command before execution"

Then apply using `<sdd-traits-command>` from `<sdd-context>`:

```bash
"<value from sdd-traits-command>" init --enable "<selected-traits-as-csv e.g. superpowers,beads>"
"<value from sdd-traits-command>" permissions <none|standard|yolo>
```

If no traits selected, run `init` without `--enable`.

## Step 3: Report

Summarize: traits enabled, permission level. If Step 1 said RESTART_REQUIRED or Step 2 permissions said CHANGED, tell user to restart Claude Code.
