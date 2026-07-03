# Feature Specification: Deterministic closeout gate for unresolved findings

**Feature Branch**: `034-closeout-gate`  
**Created**: 2026-07-03  
**Status**: Draft  
**Input**: Brainstorm 30 - Deterministic closeout gate
**Issue**: [#9](https://github.com/rhuss/cc-spex/issues/9)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Gate blocks completion when Critical/Important findings remain (Priority: P1)

When a developer runs the verify or stamp gate after a deep review that found Critical or Important issues, the closeout gate script reads the review report, detects the unresolved findings, and exits with a non-zero code. The verify/stamp command reports the blocking findings and refuses to mark the feature as complete.

**Why this priority**: This is the core safety mechanism. Without it, the autonomous pipeline can claim completion despite unresolved Critical findings.

**Independent Test**: Create a REVIEW-CODE.md with Critical findings (Remaining > 0), run the closeout gate script, and verify it exits with code 1 and lists the blocking findings.

**Acceptance Scenarios**:

1. **Given** a REVIEW-CODE.md with a severity summary table showing "Critical | 2 | 0 | 2", **When** the closeout gate script runs, **Then** it exits with code 1 and outputs the count of unresolved Critical findings.
2. **Given** a REVIEW-CODE.md with "Important | 1 | 0 | 1", **When** the closeout gate script runs, **Then** it exits with code 1 and outputs the count of unresolved Important findings.
3. **Given** a REVIEW-CODE.md with "Critical | 1 | 1 | 0" and "Important | 2 | 2 | 0" (all fixed), **When** the closeout gate script runs, **Then** it exits with code 0.

---

### User Story 2 - Gate passes when no review report exists (fail-open) (Priority: P1)

When a developer runs verify/stamp on a feature that did not go through deep review (no REVIEW-CODE.md exists), the closeout gate passes by default. This ensures the gate does not force deep review on projects or features that choose not to use it.

**Why this priority**: Fail-open is essential for adoption. The gate should catch unresolved findings when a review was done, not mandate that a review must be done.

**Independent Test**: Run the closeout gate script in a spec directory with no REVIEW-CODE.md and verify it exits with code 0.

**Acceptance Scenarios**:

1. **Given** a feature spec directory with no REVIEW-CODE.md, **When** the closeout gate script runs, **Then** it exits with code 0 (pass).
2. **Given** the environment variable `SPEX_CLOSEOUT_STRICT=1` is set and no REVIEW-CODE.md exists, **When** the closeout gate script runs, **Then** it exits with code 1 (fail-closed mode).

---

### User Story 3 - Gate is wired into verify and stamp commands (Priority: P2)

The verify and stamp gate commands run the closeout gate as their first step (Step 0), before any other verification. If the gate fails, the command stops and reports the unresolved findings. The developer must fix the findings and re-run the review before the gate passes.

**Why this priority**: The gate is only useful if it runs automatically at the right checkpoints. Wiring it into verify/stamp ensures it cannot be bypassed.

**Independent Test**: Run `/speckit-spex-gates-verify` on a feature with unresolved Critical findings and verify it stops at Step 0 with the gate failure message.

**Acceptance Scenarios**:

1. **Given** a feature with unresolved Critical findings in REVIEW-CODE.md, **When** `/speckit-spex-gates-verify` is invoked, **Then** it stops at Step 0 and reports "Closeout gate failed: N unresolved Critical/Important findings."
2. **Given** a feature with all findings resolved (or no review report), **When** `/speckit-spex-gates-verify` is invoked, **Then** Step 0 passes and the command proceeds to its normal verification flow.

---

### Edge Cases

- What if REVIEW-CODE.md exists but has no severity summary table? The script MUST treat this as "no findings data" and pass (fail-open), since the table format may vary.
- What if the severity summary table has Minor or Notable findings but no Critical/Important? The gate MUST pass, since only Critical and Important block completion.
- What if the Remaining column contains non-numeric values? The script MUST treat unparseable values as 0 (fail-open for robustness).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A closeout gate script MUST read the REVIEW-CODE.md file from the feature's spec directory and parse the severity summary table.
- **FR-002**: The script MUST exit with code 1 when the Remaining count for Critical or Important severity is greater than 0.
- **FR-003**: The script MUST exit with code 0 when all Critical and Important findings have Remaining count of 0.
- **FR-004**: The script MUST exit with code 0 (pass) when no REVIEW-CODE.md exists, unless `SPEX_CLOSEOUT_STRICT=1` is set.
- **FR-005**: When `SPEX_CLOSEOUT_STRICT=1` is set and no REVIEW-CODE.md exists, the script MUST exit with code 1 (fail-closed).
- **FR-006**: The verify and stamp gate commands MUST invoke the closeout gate script as their first step before any other verification.
- **FR-007**: When the closeout gate fails, the verify/stamp command MUST stop and report the specific findings that block completion.
- **FR-008**: The script MUST output a human-readable summary of blocking findings on failure, including severity and count.

### Key Entities

- **Closeout Gate Script**: A shell script that reads a review report and enforces a pass/fail decision based on finding severity.
- **Review Report** (REVIEW-CODE.md): A markdown document produced by the deep review stage, containing a severity summary table with Found, Fixed, and Remaining columns.
- **Severity Summary Table**: A markdown table in the review report with rows for Critical, Important, Minor, Notable, and other severity levels.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Zero autonomous pipeline runs can complete with unresolved Critical or Important findings when the closeout gate is active.
- **SC-002**: The gate adds less than 1 second of overhead to the verify/stamp command execution.
- **SC-003**: The gate does not block features that did not use deep review (fail-open by default).
- **SC-004**: The gate can be configured to require deep review via a single environment variable.

## Out of Scope

- **Review staleness detection**: The gate does not check whether the REVIEW-CODE.md is outdated relative to code changes. It trusts the report as-is.
- **Re-running the deep review**: The gate only reads the existing report. Triggering a new review is the developer's responsibility.
- **Blocking on Minor/Notable severity**: Only Critical and Important findings block completion. Lower severities are informational.

## Assumptions

- The REVIEW-CODE.md format follows the established deep review report template with a severity summary table using the `| Severity | Found | Fixed | Remaining |` header.
- The closeout gate script follows the same coding patterns as existing spex scripts (bash + jq, POSIX-compatible where possible).
- The verify and stamp commands are part of the spex-gates extension and can be modified to add a Step 0.
- The closeout gate does not re-run the deep review. It only reads the existing report.
