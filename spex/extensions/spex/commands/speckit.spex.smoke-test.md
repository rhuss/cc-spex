---
description: "Interactive spec-driven acceptance scenario walkthrough"
---

# Interactive Smoke Test (speckit-spex-smoke-test)

## Overview

Walk through the acceptance scenarios defined in the feature spec using a two-phase architecture. Phase 1 spawns a fresh-context subagent (no implementation memory) to execute scenarios and collect evidence. Phase 2 presents the evidence interactively in the main session for human judgement. Results are persisted as SMOKE-TEST.md in the spec directory.

<HARD-GATE>
## No Simulated Tests

You MUST NOT simulate, fake, or manually reproduce what the system under test would do. Every scenario must exercise the actual system (run the real command, call the real API, invoke the real skill). If a scenario cannot be properly tested in the current session (e.g., requires a separate run, external infrastructure, or state that cannot be set up), you MUST:

1. Mark it as **skip** immediately
2. State clearly why it cannot be tested (e.g., "Requires two independent distillation runs")
3. Provide concrete manual test instructions the user can follow later (exact commands, expected output, what to verify)

A simulated test that manually edits files to mimic system output is worse than no test. It creates false confidence.
</HARD-GATE>

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

## Step 2: App Lifecycle (Main Session)

The main session owns app startup and shutdown. The subagent (Phase 1) assumes the app is already running if needed.

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
Scenarios will be verified through function calls, test invocations,
or manual verification.
```

Set `APP_RUNNING=false` and proceed to Step 3. The subagent will categorize scenarios accordingly.

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

Wait for user confirmation before proceeding to Step 3.

Track whether the smoke test started the app process (for cleanup in Step 7). Store the process ID if applicable. Set `APP_RUNNING=true` once the app is confirmed running, `APP_RUNNING=false` otherwise.

## Step 3: Execute via Subagent (Phase 1)

Spawn a subagent via the Agent tool to execute scenarios with fresh context. The subagent has no memory of the implementation session, removing self-testing bias.

### Subagent Prompt

Use the Agent tool to spawn a subagent with the following prompt. Substitute the actual values for `SPEC_FILE`, `PROJECT_ROOT`, and `APP_RUNNING`:

```
You are a smoke test execution agent. Your job is to exercise acceptance
scenarios from a feature spec and collect evidence. You have NO context
about how this code was implemented. Approach each scenario with fresh eyes.

IMPORTANT RULES:
- You MUST NOT simulate, fake, or manually reproduce expected output.
  Every scenario must exercise the actual system. If you cannot exercise
  a scenario, mark it as "skip" with a reason and manual instructions.
- You MUST NOT read plan.md, tasks.md, or any implementation artifacts.
  Only read the spec file for scenario definitions.
- Return your findings as structured text (format below).

Spec file: <SPEC_FILE>
Project root: <PROJECT_ROOT>
App running: <APP_RUNNING> (true/false)

INSTRUCTIONS:

1. Read the spec file at <SPEC_FILE>.
2. Extract all acceptance scenarios from the "User Scenarios & Testing"
   section. Stop at "Edge Cases". Each numbered item with Given/When/Then
   is one scenario. Track which User Story each belongs to.
3. For each scenario, categorize it:
   - **automated**: You can run a command to exercise it (curl, CLI tool,
     make test, script invocation, etc.)
   - **manual**: Requires human action (UI interaction, visual inspection,
     browser check) but you can prepare step-by-step instructions
   - **skip**: Cannot be exercised in this session (requires prior separate
     run, external infrastructure, state from another session). Provide
     a clear reason and manual test instructions for later.
4. For automated scenarios: run the actual command, capture the full output.
5. For manual scenarios: prepare precise step-by-step instructions including
   exact commands, URLs, and what to look for.
6. For skip scenarios: explain why and provide manual test instructions.

RETURN FORMAT (one block per scenario, separated by ---):

## Scenario N of TOTAL (User Story: <story title>)
**Type**: automated | manual | skip
**Given** <precondition text from spec>
**When** <action text from spec>
**Then** <expected outcome text from spec>
**Why it matters**: <one sentence explaining what risk this scenario catches>

### Evidence
<for automated>
**Command**: <exact command run>
**Output**:
```
<full command output>
```
**Observation**: <your factual observation about what the output shows>

<for manual>
**Instructions**:
1. <step 1>
2. <step 2>
...
**What to verify**: <what the human should look for>

<for skip>
**Skip reason**: <why this cannot be exercised>
**Manual test instructions**:
1. <step 1>
2. <step 2>
...

---
```

### Handling Subagent Failure

If the subagent fails or times out:

1. Report the failure to the user
2. Offer to retry (spawn a new subagent)
3. If the user declines retry, offer to skip the smoke test entirely

If the subagent returns but its output cannot be parsed (no recognizable scenario blocks):

1. Show the raw output to the user
2. Ask whether to proceed with manual review of each scenario or abort

## Step 4: Interactive Review (Phase 2)

Parse the subagent's return text and present each scenario to the user one at a time for human judgement. The user makes the final pass/fail/skip decision for every scenario.

### 4a. Parse Evidence

Parse the subagent's return text into individual scenario blocks. Each block is delimited by `---` and starts with `## Scenario N of TOTAL`. Extract:
- Scenario number and total
- User story title
- Type (automated/manual/skip)
- Given/When/Then text
- Why it matters
- Evidence section (command+output, instructions, or skip reason)

### 4b. Present Each Scenario

For each parsed scenario, display:

```
## Scenario N of TOTAL (User Story: <story title>)

**Given** <precondition>
**When** <action>
**Then** <expected outcome>

**Why it matters**: <explanation>
```

Then present the evidence based on type:

**For automated scenarios:**
```
### Evidence (automated)

**Command**: `<command>`
**Output**:
```
<output>
```

**Subagent observation**: <observation>
```

Ask: "Does this scenario pass? (pass / fail / skip)"

**For manual scenarios:**
```
### Evidence (manual - requires your action)

**Instructions**:
1. <step>
2. <step>
...

**What to verify**: <criteria>
```

Ask: "Please perform the steps above and report: pass / fail / skip"

**For skip scenarios:**
```
### Evidence (skip)

**Reason**: <skip reason>

**Manual test instructions** (for later):
1. <step>
2. <step>
...
```

Ask: "Confirm skip, or would you like to attempt manual verification? (skip / try)"

If the user chooses "try" for a skip scenario, present the manual test instructions and wait for their pass/fail verdict.

### 4c. Record Verdicts

For each scenario, record:
- Scenario number
- Verdict: pass, fail, or skip
- Any notes from the reviewer
- Retry result (if the scenario was retried after a fix)

### 4d. Debugging Loop (on failure)

When a scenario is marked "fail":

1. **Ask what went wrong**: "What went wrong? (describe the issue, or press enter for automatic analysis)"
2. **Analyze the evidence**: Compare expected outcome (from Then clause) with actual output. Suggest possible causes based on the discrepancy.
3. **Offer to inspect**: Suggest relevant files, logs, or configuration to investigate. Offer to read and analyze them.
4. **Offer to fix**: If the cause is identified, offer to make the fix (edit code, adjust configuration, etc.)
5. **Offer to retry**: After a fix is applied, ask: "Would you like to retry this scenario? (yes / no / skip)"
   - If yes: re-run the command (for automated scenarios) or re-present instructions (for manual)
   - Record both the initial failure and the retry result
6. **Move on**: If the user declines retry or retry also fails, proceed to the next scenario

### 4e. App Crash Detection

If the main session started the app (Step 2) and the app process crashes during the review phase:

1. Detect the crash (check if the background process is still running)
2. Report: "The app appears to have crashed. This may affect remaining scenarios."
3. Show any available crash output or error logs
4. Offer to restart the app before continuing

## Step 5: Write SMOKE-TEST.md

After all scenarios are reviewed, generate `SMOKE-TEST.md` in the spec directory.

### Report Structure

```markdown
# Smoke Test Report

**Feature**: <feature name from spec title>
**Date**: <YYYY-MM-DD>
**Spec**: <relative path to spec.md>
**Result**: N passed, M skipped, K failed (out of TOTAL)

## Scenario 1 of TOTAL (User Story: <story title>)

**Given** <precondition>
**When** <action>
**Then** <expected outcome>

**Why it matters**: <explanation>

### Evidence

**Command**: `<exact command>`
**Output**:
```
<full output>
```
**Observation**: <subagent's factual observation about the output>

### Verdict: PASS

<reviewer notes if any>

---

## Scenario 2 of TOTAL (User Story: <story title>)

...
```

### Evidence Variants

**For automated scenarios**: Show Command + Output + Observation.

**For manual scenarios**: Show Instructions + What to verify.

**For skip scenarios**: Show Skip reason + Manual test instructions for later.

### Retry Documentation

If a scenario failed and was debugged/retried, include both results:

```markdown
### Verdict: PASS (after retry)

**Initial result**: FAIL
**Issue**: <description of the failure>
**Fix applied**: <what was changed>
**Retry result**: PASS

<any additional notes>
```

### Write the File

Write the report to `$FEATURE_DIR/SMOKE-TEST.md`. If a previous report exists, overwrite it (each run is a fresh validation).

Announce:
```
Smoke test report written to <relative path to SMOKE-TEST.md>.
```

## Step 6: Record Results

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

## Step 7: Cleanup

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
Report: <path to SMOKE-TEST.md>
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
- Agent tool (subagent for Phase 1 execution)
- `spex-ship-state.sh smoke-test-record` (state recording)
- Optionally: `/run` skill (app startup delegation)
