---
description: "Interactive spec-driven acceptance scenario walkthrough"
---

# Interactive Smoke Test (speckit-spex-smoke-test)

## Overview

Walk through the acceptance scenarios defined in the feature spec, executing each one interactively. For each scenario, the command explains what it will do, executes the action, shows the result, and waits for user confirmation before proceeding. This validates runtime behavior that unit tests cannot catch.

## Ship Pipeline Guard

If `.specify/.spex-state` exists and its `status` is `running`, this command is part of a ship pipeline. The smoke test is **always interactive** regardless of the `ask` level. It never runs autonomously. However, it should not output a completion summary or ask "Shall I proceed?" after finishing. Complete the walkthrough and return.

```bash
PIPELINE_MODE=false
if [ -f ".specify/.spex-state" ]; then
  STATUS=$(jq -r '.status // empty' .specify/.spex-state 2>/dev/null)
  if [ "$STATUS" = "running" ]; then
    PIPELINE_MODE=true
  fi
fi
```

## Context Freshness

**When NOT in pipeline mode**: If this command is invoked directly (not from the ship pipeline), display this recommendation before proceeding:

```
Tip: For best results, run /clear before the smoke test to remove
implementation context. A fresh context catches issues that familiarity
with the code masks.
```

This is informational only. Do not block or require confirmation.

**When in pipeline mode**: Skip this message (the ship pipeline handles context isolation via subagent).

## Prerequisites

### Spec Resolution

Resolve the feature spec using the standard check-prerequisites script:

```bash
PREREQS=$(.specify/scripts/bash/check-prerequisites.sh --json --paths-only 2>/dev/null)
FEATURE_DIR=$(echo "$PREREQS" | jq -r '.FEATURE_DIR')
SPEC_FILE="$FEATURE_DIR/spec.md"
```

If the spec cannot be resolved, report the error and exit.

## Step 1: Parse Acceptance Scenarios

Read the spec file and extract all acceptance scenarios from the "User Scenarios & Testing" section.

**Parsing rules:**
1. Scan only within the "User Scenarios & Testing" section (identified by `## User Scenarios` heading) and its subsections
2. **STOP scanning** when you reach the "Edge Cases" subsection (identified by `### Edge Cases` heading). Do NOT include edge cases as scenarios.
3. Within the scanned section, find numbered list items containing bold `**Given**`, `**When**`, `**Then**` keywords
4. Each numbered item is one scenario
5. Parse each scenario into a structured triple:
   - **given**: The precondition text (from `**Given**` clause)
   - **when**: The action text (from `**When**` clause)
   - **then**: The expected outcome text (from `**Then**` clause)
6. Track which user story each scenario belongs to (from the parent `### User Story N` heading)

**If no acceptance scenarios are found** (no Given/When/Then blocks in the User Scenarios section):

Report to the user:
```
No acceptance scenarios found in spec.md.
Add Given/When/Then scenarios to enable smoke testing.
```

Exit without error. If in pipeline mode, return immediately so the pipeline can proceed.

**If scenarios are found**, report the count:
```
Found N acceptance scenarios across M user stories.
```

## Step 2: Project Type Detection and App Startup

### Check for /run Skill

First, check if the `/run` skill is available in the current session. This is a runtime check, not a hard dependency:

```
Check if the /run skill is listed in the available skills.
```

### Auto-Detect Project Type

If `/run` is not available, auto-detect the project type and start command using this priority:

1. **Makefile** with `run` or `serve` target: `make run` or `make serve`
2. **package.json** with `start` script: `npm start`
3. **go.mod**: `go run .`
4. **Python** with `manage.py` (Django), `app.py`, or `main.py`: `python manage.py runserver` / `python app.py` / `python main.py`
5. **Cargo.toml**: `cargo run`

### Library Detection

If the project appears to be a library (no server, no CLI entry point, no start command detected, and the spec does not describe a runnable application):

Report:
```
This appears to be a library project (no runnable app detected).
Instead of starting an app, scenarios will be verified through function calls,
test invocations, or manual verification.
```

Ask the user how they would like to exercise the behavior, then proceed with manual scenario verification.

### Start the App

If a start command is detected (or `/run` skill is available):

1. If `/run` skill is available, delegate to it: invoke the `/run` skill to start the project
2. Otherwise, start the app as a background process using the detected command
3. Wait for the app to become ready (check for port availability or stdout markers)
4. Report the startup status

If the app **cannot be started** (no detectable start command, requires cloud infrastructure, or the start command fails):

Report:
```
Cannot auto-detect how to start this project.
Please start the app manually and confirm when ready.
```

Wait for user confirmation before proceeding to scenario execution.

Track whether the smoke test started the app process (for cleanup later). Store the process ID if applicable.

## Step 3: Interactive Scenario Walkthrough

For each parsed scenario, execute the following loop:

### 3a. Present the Scenario

Display the scenario with full context:

```
## Scenario N of TOTAL (User Story: <story title>)

**Given** <precondition>
**When** <action>
**Then** <expected outcome>
```

### 3b. Explain the Execution Plan

Before executing, explain what command or action will be performed to test this scenario. For example:
- For HTTP endpoints: "I will run `curl -X POST http://localhost:8080/api/endpoint` with the following payload..."
- For CLI commands: "I will run `./my-tool --flag value` and check the output..."
- For UI interactions: "I will navigate to the page and check for the expected element..."

If the action is unclear from the scenario text, ask the user for guidance on how to exercise this specific behavior.

### 3c. Execute the Action

Execute the planned command or action. Show the full output to the user.

### 3d. Display Results

Present the result alongside the expected outcome:

```
### Result

<actual output or observation>

### Expected (from spec)

**Then** <expected outcome from scenario>
```

### 3e. Ask for Confirmation

Ask the user to confirm the scenario result. Accept one of:
- **pass** (or "yes", "y", "ok", "confirmed"): Scenario passed. Move to the next scenario.
- **fail** (or "no", "n", "failed"): Scenario failed. Enter debugging mode (see 3f).
- **skip**: Skip this scenario. Mark as skipped and move to the next scenario.

### 3f. Interactive Debugging (on failure)

When a scenario fails:

1. **Suggest potential causes** based on the expected vs actual output
2. **Offer to inspect** logs, code, or configuration related to the failure
3. **Help the user fix the issue**: edit code, adjust configuration, etc.
4. **After fixing**, offer to **retry the scenario** or **move on** to the next one

### 3g. App Crash Detection

If the app process crashes during scenario execution (process exits unexpectedly):

1. Detect the crash (check if background process is still running)
2. Report: "The app appears to have crashed during this scenario."
3. Show any available crash output or error logs
4. Offer to restart the app before retrying the scenario

## Step 4: Record Results

After all scenarios are processed (or the user exits early), record the results.

### Locate the State Script

```bash
SHIP_STATE="$(find ~/.claude -name 'spex-ship-state.sh' 2>/dev/null | head -1)"
```

### Record Smoke Test Results

Invoke the state script to record results:

```bash
"$SHIP_STATE" smoke-test-record \
  --completed <true|false> \
  --scenarios <count_completed> \
  --total <total_count> \
  --skipped <skipped_count>
```

Where:
- `completed` is `true` if all scenarios were processed (passed or skipped), `false` if the user exited early
- `scenarios` is the number of scenarios that were completed (passed + skipped)
- `total` is the total number of scenarios found in the spec
- `skipped` is the number of scenarios the user explicitly skipped

## Step 5: Cleanup

### Stop the App Process

If the smoke test started the app process (tracked in Step 2):

1. Attempt graceful shutdown with SIGTERM
2. Wait up to 5 seconds for the process to exit
3. If still running after 5 seconds, send SIGKILL
4. Report cleanup status:
   - "App process stopped gracefully."
   - "App process force-killed after timeout."
   - "App process had already exited."

If the smoke test did NOT start the app (user started it manually), do NOT attempt to stop it.

### Report Summary

Display a brief summary:

```
## Smoke Test Summary

Scenarios: N passed, M skipped, K failed (out of TOTAL)
Status: <COMPLETE | INCOMPLETE (exited early)>
```

If in pipeline mode (`PIPELINE_MODE=true`):
- Do NOT output a detailed completion summary
- Do NOT ask "Shall I proceed?"
- Return immediately so the pipeline can advance

## Integration

**This command is invoked by:**
- Users directly via `/speckit-spex-smoke-test`
- The ship pipeline (Stage 8) via `/speckit-spex-ship`

**This command invokes:**
- `.specify/scripts/bash/check-prerequisites.sh` (spec resolution)
- `spex-ship-state.sh smoke-test-record` (state recording)
- Optionally: `/run` skill (app startup delegation)
