# Deep Review Findings

**Date:** 2026-07-09
**Branch:** 038-neutral-command-vocab
**Rounds:** 1
**Gate Outcome:** PASS
**Invocation:** quality-gate

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 2 | 2 | 0 |
| Minor | 7 | 4 | 3 |
| Notable | 2 | - | 2 |
| **Total** | **11** | **6** | **5** |

**Agents completed:** 5/5 (+ 1 external tool)
**Agents failed:** none

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 95
- **File:** spex/scripts/spex-adapt-commands.sh:88-92
- **Category:** correctness
- **Source:** correctness-agent (also reported by: architecture-agent, production-agent, coderabbit)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
The inline substitution awk loop used `while (idx = index($0, old[i]))` which restarts from the beginning of the line after each replacement. If a replacement string contains the search string as a substring, the loop never terminates.

**Why this matters:**
The spec says adding a new harness requires only a mapping table file (SC-003). A mapping table author has no reason to suspect this constraint exists. An infinite loop during setup would hang the terminal.

**How it was resolved:**
Replaced with a position-tracking approach that advances past each replacement, preventing re-scanning of inserted text.

### FINDING-2
- **Severity:** Important
- **Confidence:** 90
- **File:** spex/scripts/spex-adapt-commands.sh:104-117
- **Category:** correctness
- **Source:** correctness-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
If a capability marker's closing tag is missing from a command file, the awk `in_block` flag stays set for the rest of the file, silently dropping all subsequent content.

**Why this matters:**
A missing closing tag (typo, copy-paste error) would silently drop half a file with no warning, then overwrite the original.

**How it was resolved:**
Added an `END` block to the awk script that checks for unclosed markers and exits with an error message to stderr.

### FINDING-3
- **Severity:** Minor
- **Confidence:** 85
- **File:** spex/scripts/adapters/claude/command-map.json
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
Three section entries (`interactive-choice`, `subagent-dispatch`, `harness-settings`) had no matching capability markers in any command file.

**How it was resolved:**
Removed the unused section entries from Claude and Codex mapping tables.

### FINDING-4
- **Severity:** Minor
- **Confidence:** 85
- **File:** spex/scripts/adapters/claude/command-map.json
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
The `agent-teams-dispatch` and `agent-teams-research-dispatch` sections contained instructions for Codex and OpenCode users inside the Claude mapping table.

**How it was resolved:**
Replaced cross-harness content with Claude-only instructions plus a generic fallback line.

### FINDING-5
- **Severity:** Minor
- **Confidence:** 85
- **File:** spex/scripts/spex-adapt-commands.sh:88-93
- **Category:** correctness
- **Source:** correctness-agent (also reported by: architecture-agent)
- **Round found:** 1
- **Resolution:** no change needed

**What is wrong:**
Inline entry `"the agent's subagent mechanism"` is a substring of `"Use the agent's subagent mechanism with"`, making the longer entry effectively dead.

**Why no change:** The shorter pattern fires first and produces correct output. The longer entry is dead code but harmless. Removing it would be a minor cleanup.

### FINDING-6
- **Severity:** Minor
- **Confidence:** 80
- **File:** spex/scripts/spex-adapt-commands.sh:160
- **Category:** correctness
- **Source:** correctness-agent (also reported by: production-agent, coderabbit)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
Comment said "Atomic swap" but the copy-back loop is not atomic.

**How it was resolved:**
Updated comment to accurately describe the best-effort copy behavior.

### FINDING-7
- **Severity:** Minor
- **Confidence:** 75
- **File:** spex/setup.yml:341
- **Category:** correctness
- **Source:** correctness-agent (also reported by: production-agent)
- **Round found:** 1
- **Resolution:** no change needed

**What is wrong:**
The check `[ ! -x "$ADAPT_SCRIPT" ]` conflates "not found" with "not executable" and the error message says "not found."

**Why no change:** Low practical impact since git preserves execute bits and the primary install path is from the repo.

### FINDING-8
- **Severity:** Minor
- **Confidence:** 70
- **File:** spex/scripts/spex-adapt-commands.sh:119
- **Category:** correctness
- **Source:** correctness-agent
- **Round found:** 1
- **Resolution:** no change needed

**What is wrong:**
The sed replacement `sed "s/{harness}/$HARNESS_ID/g"` is vulnerable to sed injection if harness ID contains metacharacters.

**Why no change:** Current harness IDs are controlled strings ("claude", "codex", "opencode"). The variable comes from a developer-committed JSON file.

### FINDING-9
- **Severity:** Minor
- **Confidence:** 85
- **File:** spex/scripts/spex-adapt-commands.sh:104-135
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
The awk block for marker replacement was copy-pasted between the "has replacement" and "fallback" paths.

**How it was resolved:**
Consolidated into a single awk invocation by computing the replacement file path before the call.

## Notable Observations

### NOTABLE-1
- **File:** (project-wide)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Description:** No automated tests exist for the adaptation script or mapping tables
- **Rationale:** The adaptation script contains non-trivial awk logic for text processing and marker replacement. A basic integration test that creates synthetic inputs, runs the script, and asserts expected output would catch regressions. The project uses `make release` for validation but this target does not exercise the adapt-commands step.

### NOTABLE-2
- **File:** spex/scripts/adapters/opencode/command-map.json
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** OpenCode mapping table is an empty stub indistinguishable from a missing file
- **Rationale:** The script already handles missing mapping tables gracefully (exit 0). The empty stub serves as a template for future OpenCode support, per the spec's out-of-scope section.

## Test Suite Results

No test command detected; post-fix test step was skipped.
