# Deep Review Findings

**Date:** 2026-07-15
**Branch:** 044-brainstorm-sync
**Rounds:** 1
**Gate Outcome:** PASS
**Invocation:** quality-gate

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 8 | 8 | 0 |
| Minor | 12 | 0 | 12 |
| Notable | 0 | 0 | 0 |
| **Total** | **20** | **8** | **12** |

**Agents completed:** 5/5 (+ 1 external tool)
**Agents failed:** none

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 88
- **File:** spex/extensions/spex/commands/speckit.spex.brainstorm.md:586-594
- **Category:** correctness
- **Source:** correctness-agent (also reported by: production-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
Step 8 (Update Overview) had no guard for the case where `brainstorm/00-overview.md` does not exist. Step 4 explicitly checks "If overview exists," but Step 8 assumed the file was present, which would fail mid-sync after files were already moved.

**Why this matters:**
Leaves the sync in a partially-completed state: files moved but no commit made.

**How it was resolved:**
Replaced selective removal strategy with full rebuild approach (reusing the existing "Updating the Overview" procedure). Added explicit guard for missing overview file.

### FINDING-2
- **Severity:** Important
- **Confidence:** 92
- **File:** spex/extensions/spex/commands/speckit.spex.brainstorm.md:204-208 vs 536-545
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
The sync process recognized five status values (`completed`, `resolved`, `decided`, `draft`, `idea`) that were never defined in the canonical "Status values" section. This was a silent contract expansion.

**Why this matters:**
Agents or humans writing brainstorm documents would consult the Status values section and have no idea these additional values were recognized.

**How it was resolved:**
Expanded the Status values section to define all recognized values, grouped into "Terminal states" and "Non-terminal states" categories.

### FINDING-3
- **Severity:** Important
- **Confidence:** 90
- **File:** spex/extensions/spex/commands/speckit.spex.brainstorm.md:428-458 vs 586-594
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
Two fundamentally different strategies for updating `00-overview.md`: the existing section uses "idempotent full rebuild," while Step 8 used "selective removal." These have different data-preservation semantics.

**Why this matters:**
A maintenance trap where curated content preserved by sync could be wiped by the next normal brainstorm session.

**How it was resolved:**
Changed Step 8 to reuse the existing full-rebuild procedure. Since attic'd files are no longer in `brainstorm/`, the rebuild naturally excludes them.

### FINDING-4
- **Severity:** Important
- **Confidence:** 75
- **File:** spex/extensions/spex/commands/speckit.spex.brainstorm.md:580
- **Category:** security
- **Source:** security-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
The `git mv` command template showed unquoted filenames. The sync process scans all `.md` files including manually-created ones, so filenames with shell metacharacters could cause command injection.

**Why this matters:**
A file with a malicious filename (e.g., containing `$(...)`) could execute arbitrary commands when the AI agent generates the unquoted `git mv` command.

**How it was resolved:**
Quoted filenames in the template: `git mv "brainstorm/<filename>" "brainstorm/attic/<filename>"`.

### FINDING-5
- **Severity:** Important
- **Confidence:** 92
- **File:** spex/extensions/spex/commands/speckit.spex.brainstorm.md:578-582
- **Category:** production-readiness
- **Source:** production-agent (also reported by: coderabbit)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
No error handling for partial `git mv` failure. If moves 1-3 succeed and move 4 fails, Step 8 would proceed to update the overview assuming all files moved, and Step 9 would commit a partially-moved state.

**Why this matters:**
With 40+ documents, the probability of a single failure in a batch increases. A partial move with inconsistent overview leaves the directory in a broken state.

**How it was resolved:**
Added stop-on-failure: if any `git mv` fails, stop processing, report which files were moved and which failed, and do NOT proceed to overview update or commit. User is told how to undo.

### FINDING-6
- **Severity:** Important
- **Confidence:** 95
- **File:** spex/extensions/spex/commands/speckit.spex.brainstorm.md:600-605
- **Category:** production-readiness
- **Source:** production-agent (also reported by: correctness-agent, coderabbit)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
Step 9 used `git add brainstorm/` which stages ALL changes under `brainstorm/`, not just sync-related files. Unrelated work-in-progress edits to other brainstorm documents would be silently swept into the sync commit.

**Why this matters:**
Corrupts git history by combining unrelated changes under a misleading commit message.

**How it was resolved:**
Replaced with targeted staging: `git add brainstorm/attic/` and `git add brainstorm/00-overview.md` (git mv already stages the file moves).

### FINDING-7
- **Severity:** Important
- **Confidence:** 88
- **File:** spex/extensions/spex/commands/speckit.spex.brainstorm.md:586-589
- **Category:** production-readiness
- **Source:** production-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
Step 8 used number-based row matching to remove Sessions table entries, but the real `00-overview.md` contains duplicate numbers (two #08 entries for different documents). Number-only matching is ambiguous.

**Why this matters:**
If only one #08 is attic'd, the other's row could be erroneously removed.

**How it was resolved:**
Replaced selective row removal with full overview rebuild, which eliminates the ambiguity entirely (rebuild only includes files still present in the directory).

### FINDING-8
- **Severity:** Important
- **Confidence:** 80
- **File:** spex/extensions/spex/commands/speckit.spex.brainstorm.md:504-514
- **Category:** correctness
- **Source:** correctness-agent (also reported by: coderabbit)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
Step 3 did not specify behavior when a brainstorm document matches multiple spec directories. No tie-breaking rule existed.

**Why this matters:**
Ambiguous matching means different runs could classify the same document differently.

**How it was resolved:**
Added tie-breaking rule: prefer the spec with the most shared tokens; if tied, prefer the highest number (most recent). Record only the best match.

### FINDING-9
- **Severity:** Minor
- **Confidence:** 82
- **File:** spex/extensions/spex/commands/speckit.spex.brainstorm.md:534-546
- **Category:** correctness
- **Source:** correctness-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, bundled with FINDING-2)

**What is wrong:**
Unknown status values (not in terminal or keep sets) had undefined behavior.

**How it was resolved:**
Added catch-all: unknown status values default to `keep` with a warning.

### FINDING-10
- **Severity:** Minor
- **Confidence:** 90
- **File:** spex/extensions/spex/commands/speckit.spex.brainstorm.md:27-28
- **Category:** correctness
- **Source:** correctness-agent
- **Round found:** 1
- **Resolution:** remaining (spec-impl text mismatch, not a behavior bug)

**What is wrong:**
The Argument Handling section says "skip steps 2-10" while FR-016 in the spec says "skip steps 2-7." The implementation behavior is correct (sync has its own overview/commit), but the text differs from the spec.

### FINDING-11
- **Severity:** Minor
- **Confidence:** 85
- **File:** spex/extensions/spex/commands/speckit.spex.brainstorm.md:476-609
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:**
The sync process section uses a different structural convention (### Step N sub-headings) than other sections (numbered steps under ## headings with **When:** preambles).

### FINDING-12
- **Severity:** Minor
- **Confidence:** 78
- **File:** spex/extensions/spex/commands/speckit.spex.brainstorm.md:497-498
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:**
Step 2 embeds a non-local skip-ahead instruction ("skip Steps 2, 3, and 4") that couples steps together.

### FINDING-13
- **Severity:** Minor
- **Confidence:** 72
- **File:** spex/extensions/spex/commands/speckit.spex.brainstorm.md:484-493
- **Category:** security
- **Source:** security-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:**
No filename validation in Step 1 to reject files with shell metacharacters. Defense-in-depth gap (mitigated by FINDING-4 fix of quoting filenames).

### FINDING-14
- **Severity:** Minor
- **Confidence:** 78
- **File:** spex/extensions/spex/commands/speckit.spex.brainstorm.md:590-592
- **Category:** production-readiness
- **Source:** production-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, addressed by FINDING-3/7 overview rebuild fix)

**What is wrong:**
Open Threads and Parked Ideas cleanup only matched by `(from #NN)` pattern, which doesn't work for unnumbered documents. Resolved by switching to full overview rebuild.

### FINDING-15
- **Severity:** Minor
- **Confidence:** 92
- **File:** specs/044-brainstorm-sync/spec.md:74-79
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** remaining (spec issue, not implementation bug)

**What is wrong:**
No acceptance scenario covers documents with unknown status values.

### FINDING-16
- **Severity:** Minor
- **Confidence:** 90
- **File:** specs/044-brainstorm-sync/spec.md:74-79
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** remaining (spec issue)

**What is wrong:**
No acceptance scenario covers numbered files without Status field + spec match (compound edge case).

### FINDING-17
- **Severity:** Minor
- **Confidence:** 88
- **File:** specs/044-brainstorm-sync/spec.md:119-124
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** remaining (spec issue)

**What is wrong:**
Smoke Test section has only 3 high-level steps with unspecific verification criteria.

### FINDING-18
- **Severity:** Minor
- **Confidence:** 85
- **File:** specs/044-brainstorm-sync/spec.md:74-79
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** remaining (spec issue)

**What is wrong:**
No acceptance scenario for duplicate brainstorm numbers in overview table.

### FINDING-19
- **Severity:** Minor
- **Confidence:** 82
- **File:** specs/044-brainstorm-sync/spec.md:10-23
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** remaining (spec issue)

**What is wrong:**
No acceptance scenario tests `completed`, `resolved`, or `decided` terminal states individually.

### FINDING-20
- **Severity:** Minor
- **Confidence:** 78
- **File:** specs/044-brainstorm-sync/spec.md:52-54
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** remaining (spec issue)

**What is wrong:**
No scenario verifies that attic'd documents are removed from the Parked Ideas section.

## Test Suite Results

No test command detected; post-fix test step was skipped.
