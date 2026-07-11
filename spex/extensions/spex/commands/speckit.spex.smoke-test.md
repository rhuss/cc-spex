---
description: "Focused interactive smoke test with curated scenarios from spec"
---

# Focused Interactive Smoke Test (speckit-spex-smoke-test)

## Overview

Walk through curated smoke test scenarios defined in the feature spec's `## Smoke Test` section. Claude automates all setup, execution, and evidence collection. The human only provides pass/fail judgment on each scenario. Results are persisted as SMOKE-TEST.md in the spec directory.

If the spec has no `## Smoke Test` section, the command skips automatically — no human interaction needed.

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

## Prerequisites

### Spec Resolution

Resolve the feature spec using the standard check-prerequisites script:

```bash
PREREQS=$(.specify/scripts/bash/check-prerequisites.sh --json --paths-only 2>/dev/null)
FEATURE_DIR=$(echo "$PREREQS" | jq -r '.FEATURE_DIR')
SPEC_FILE="$FEATURE_DIR/spec.md"
```

If the spec cannot be resolved, report the error and exit.

### Check for `## Smoke Test` Section

After resolving the spec, check for the `## Smoke Test` section:

```bash
HAS_SMOKE_TEST=$(grep -c '^## Smoke Test$' "$SPEC_FILE" 2>/dev/null || echo 0)
```

**If no `## Smoke Test` section exists** (`HAS_SMOKE_TEST` = 0):

Report to the user:
```
No smoke test scenarios defined in spec — skipping.
```

Exit without error. If in pipeline mode, return immediately so the pipeline can proceed.

**If the section exists**, proceed to Step 1.

## Step 1: Parse Smoke Test Scenarios

Read the spec file and extract scenarios from the `## Smoke Test` section.

**Parsing rules:**
1. Find the `## Smoke Test` heading in the spec
2. Extract the content between `## Smoke Test` and the next `##` heading (or end of file)
3. Within that content, find numbered list items (lines starting with `1.`, `2.`, `3.`, etc.)
4. Each numbered item is one scenario — the full text of the list item is the scenario instruction
5. Ignore HTML comments (`<!-- ... -->`) within the section
6. If the section exists but contains no numbered list items (empty or malformed), warn and skip:

```
## Smoke Test section found but contains no parseable scenarios — skipping.
```

Exit without error. If in pipeline mode, return immediately.

**If more than 5 scenarios are found**, display a warning but proceed:

```
Warning: Found N scenarios (recommended: 5 or fewer for a focused walkthrough).
Proceeding with all N scenarios.
```

**If scenarios are found**, report the count:
```
Found N smoke test scenarios.
```

## Step 2: Execute Scenarios Interactively

For each scenario, Claude performs all setup and execution, then presents evidence to the human for judgment. This runs in the current session — no subagent spawning.

### 2a. Scenario Execution Loop

For each scenario (in order):

1. **Announce the scenario**:
   ```
   ## Scenario N of TOTAL

   > <scenario instruction text>
   ```

2. **Determine setup needs**: Read the scenario instruction and determine what setup is required:
   - Does it need a running server? Start one (see App Startup below)
   - Does it need browser interaction? Use Playwright MCP if available (see Browser Interaction below)
   - Does it need a CLI command? Run it
   - Does it need test data? Create/seed it
   - Does it need file inspection? Read the files

3. **Execute the scenario**: Perform all the actions described in the scenario instruction. Collect evidence:
   - Command output (stdout/stderr)
   - Screenshots (if browser interaction)
   - File contents (if file inspection)
   - Any other relevant output

4. **Present evidence and recommendation to the human**:

   After executing the scenario, compare the actual output against the expected behavior from the spec. Then present a structured verdict with your reasoning:

   ```
   ### Evidence

   **Setup**: <what Claude did to prepare>
   **Execution**: <commands run, URLs navigated, actions taken>
   **Output**:
   ```
   <captured output, screenshot description, or file contents>
   ```

   **Expected** (from spec): <quote the specific expected behavior>
   **Actual**: <what actually happened, with concrete details>

   ### Recommendation: PASS | FAIL | SKIP

   **Why**: <1-2 sentences explaining the match/mismatch between expected and actual>

   **How to verify yourself** (if you want to double-check):
   1. <concrete command to run or file to inspect>
   2. <what to look for in the output>
   ```

   The recommendation MUST be specific and evidence-based:
   - PASS: state exactly which expected conditions were met and how (e.g., "File exists at X, contains field Y with value Z")
   - FAIL: state exactly what differs (e.g., "Expected field 'status' to be 'active', got 'pending'")
   - SKIP: state exactly why it cannot be tested (e.g., "Requires a running SMTP server not available in this session")

   **Never present a bare "pass/fail/skip?" without your recommendation and reasoning.** The human should be confirming or overriding your judgment, not making the judgment from scratch.

5. **Ask for verdict**: Present options using AskUserQuestion with your recommendation as the first option:
   - **Pass**: Scenario works as expected
   - **Fail**: Scenario does not match expected behavior
   - **Skip**: Cannot verify right now, will test later

6. **Record the verdict** with any notes the reviewer provides.

### 2b. App Startup

If a scenario requires a running app and no app is currently running:

**Stale process check**: Before starting a new app, check if a previous instance is still running on common dev ports (3000, 5173, 8080, 8000). If found, kill the stale process before starting fresh.

**Check for /run skill**: Check if the `/run` skill is available in the current session. If available, delegate to it.

**Auto-detect project type** (if `/run` is not available):
1. **Makefile** with `run` or `serve` target: `make run` or `make serve`
2. **package.json** with `start` script: `npm start`
3. **go.mod**: `go run .`
4. **Python** with `manage.py`, `app.py`, or `main.py`: appropriate python command
5. **Cargo.toml**: `cargo run`

If the app starts successfully, keep it running for subsequent scenarios. Immediately capture the process ID (`APP_PID=$!`) for cleanup in Step 4.

If the app **cannot be started**:
```
Cannot auto-detect how to start this project.
Please start the app manually and confirm when ready.
```
Wait for user confirmation before continuing.

### 2c. Browser Interaction (Playwright MCP)

When a scenario requires browser interaction:

**If Playwright MCP is available**: Use it to navigate URLs, interact with the page (clicks, form fills, navigation), and take screenshots. Present screenshots as evidence.

**If Playwright MCP is NOT available** (graceful degradation): Provide step-by-step manual instructions instead:

```
### Browser Interaction Required (Playwright unavailable)

This scenario requires browser interaction. Please perform these steps manually:

1. Open <URL> in your browser
2. <action to perform>
3. <what to look for>

After performing these steps, provide your verdict below.
```

### 2d. Failure Handling and Retry

When a scenario verdict is **fail**:

1. **Offer to investigate**:
   ```
   Scenario failed. Would you like me to investigate the cause?
   (yes / no / skip to next scenario)
   ```

2. **If yes**: Analyze the evidence, compare expected vs actual behavior, examine relevant source code, logs, or configuration. Suggest possible causes and fixes.

3. **Offer to fix**: If the cause is identified, offer to make the fix:
   ```
   I identified the issue: <description>
   
   Suggested fix: <what to change>
   
   Would you like me to apply this fix? (yes / no)
   ```

4. **Offer to retry**: After a fix is applied:
   ```
   Fix applied. Would you like to retry this scenario? (yes / no)
   ```
   - If yes: re-execute the scenario from scratch, collect fresh evidence, and ask for verdict again
   - Record both the initial failure and the retry result
   - Maximum 2 retries per scenario. After 2 unsuccessful retries, suggest moving on:
     ```
     This scenario has failed twice after fixes. Would you like to try once more, or move to the next scenario?
     ```

5. **Move on**: If the user declines investigation, fix, or retry, proceed to the next scenario.

### 2e. App Crash Detection

Before each scenario, verify the app process is still running (if one was started):

```bash
kill -0 $APP_PID 2>/dev/null || echo "APP_CRASHED"
```

If the process is no longer running:

1. Report: "The app appears to have crashed. This may affect remaining scenarios."
3. Show any available crash output or error logs
4. Offer to restart the app before continuing

## Step 3: Write SMOKE-TEST.md

After all scenarios are reviewed, generate `SMOKE-TEST.md` in the spec directory.

### Report Structure

```markdown
# Smoke Test Report

**Feature**: <feature name from spec title>
**Date**: <YYYY-MM-DD>
**Spec**: <relative path to spec.md>
**Result**: N passed, M skipped, K failed (out of TOTAL)

---

## Scenario 1: <instruction text>

### Evidence

**Setup**: <what Claude did to prepare>
**Execution**: <commands run, URLs navigated, screenshots taken>
**Output**:
```
<captured output or screenshot description>
```

### Verdict: PASS | FAIL | SKIP

<reviewer notes if any>

---

## Scenario 2: <instruction text>

...
```

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

## Step 4: Cleanup

### Stop the App Process

If the smoke test started the app process (tracked in Step 2b):

1. Attempt graceful shutdown with SIGTERM
2. Wait up to 5 seconds for the process to exit
3. If still running after 5 seconds, send SIGKILL
4. Report cleanup status:
   - "App process stopped gracefully."
   - "App process force-killed after timeout."
   - "App process had already exited."

If the smoke test did NOT start the app (user started it manually), do NOT attempt to stop it.

### Results Report (MANDATORY)

<HARD-GATE>
You MUST output the full results report to the console on EVERY exit path, including pipeline mode. A smoke test that runs without showing its results to a human is worthless. The human must read what was tested and what passed.
</HARD-GATE>

After cleanup, ALWAYS display the full results report. This is not optional. This applies in both manual and pipeline mode.

```
═══════════════════════════════════════════════════════
SMOKE TEST RESULTS
═══════════════════════════════════════════════════════

Feature: <feature name>
Date: <YYYY-MM-DD>
Status: <COMPLETE | INCOMPLETE (exited early)>

Scenarios:

  1. <verdict emoji> <scenario instruction>
     <evidence summary — what was done and observed>

  2. <verdict emoji> <scenario instruction>
     <evidence summary>

  3. <verdict emoji> <scenario instruction>
     <evidence summary>

Summary: N passed, M skipped, K failed (out of TOTAL)
Full report: <path to SMOKE-TEST.md>

═══════════════════════════════════════════════════════
```

**Verdict emojis:**
- Pass: checkmark
- Fail: cross mark
- Skip: skip arrow

**For each scenario in the report, include:**
- The scenario instruction text
- The verdict (PASS / FAIL / SKIP)
- A one-line evidence summary (what was done and observed)
- For FAIL: expected vs. actual outcome (one line each)
- For SKIP: the skip reason and a one-line manual test instruction
- For retried scenarios: note "(after retry)" next to the verdict

**In pipeline mode**: Still suppress "Shall I proceed?" and next-step suggestions. But NEVER suppress the results report. The report is the whole point.

## Integration

**This command is invoked by:**
- Users directly via `/speckit-spex-smoke-test`
- The ship pipeline (Stage 8) via `/speckit-spex-ship`

**This command invokes:**
- `.specify/scripts/bash/check-prerequisites.sh` (spec resolution)
- Optionally: `/run` skill (app startup delegation)
- Optionally: Playwright MCP tools (browser interaction)
