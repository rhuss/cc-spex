# Tasks: Deterministic closeout gate

**Input**: Design documents from `specs/034-closeout-gate/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: User Story 1+2 - Closeout gate script (Priority: P1) MVP

**Goal**: Create the closeout gate script that reads REVIEW-CODE.md and enforces pass/fail based on Critical/Important findings

**Independent Test**: Run `spex-closeout-gate.sh` against test REVIEW-CODE.md files and verify correct exit codes

- [x] T001 [US1] Create `spex/scripts/spex-closeout-gate.sh` with argument parsing, usage help, and REVIEW-CODE.md file resolution from the spec-dir argument. Follow the shebang, error handling, and output patterns from the existing `spex/scripts/spex-flow-state.sh`.
- [x] T002 [US1] Implement severity summary table parsing: grep for rows matching `| Critical` and `| Important`, extract the 4th pipe-delimited column (Remaining) with awk, store results in `CRITICAL_REMAINING` and `IMPORTANT_REMAINING` variables. Handle non-numeric values as 0. When grep matches no Critical/Important rows (table absent or only lower severities), set both variables to 0 (gate passes, per spec edge case).
- [x] T003 [US1] Implement exit code logic using `CRITICAL_REMAINING` and `IMPORTANT_REMAINING` from T002: exit 1 when either > 0, exit 0 when both are 0. Output machine-readable status on stdout (`CLOSEOUT_PASS`, `CLOSEOUT_FAIL critical=N important=M`) and human-readable details on stderr.
- [x] T004 [US2] Implement fail-open default: exit 0 when no REVIEW-CODE.md exists in the spec directory
- [x] T005 [US2] Implement fail-closed mode: exit 1 when `SPEX_CLOSEOUT_STRICT=1` is set and no REVIEW-CODE.md exists
- [x] T006 [US1] Make script executable and verify it works with bash 3.2 (no bash 4+ features, use `${arr[@]+"${arr[@]}"}` for empty arrays if needed)

**Checkpoint**: Script passes all acceptance scenarios from spec US1 and US2.

---

## Phase 2: User Story 3 - Wire into verify command (Priority: P2)

**Goal**: Add Step 0 closeout gate invocation to verify.md. Stamp delegates to verify, so it inherits the gate automatically.

- [x] T007 [US3] Add Step 0 to `spex/extensions/spex-gates/commands/speckit.spex-gates.verify.md`: before the existing "Step 0: Smoke Test Reminder", insert a new closeout gate step. Resolve the spec directory using the same `check-prerequisites.sh` logic already in the file, then run `$PLUGIN_ROOT/scripts/spex-closeout-gate.sh "$SPEC_DIR"`. If exit code is non-zero, stop and report "Closeout gate failed: N unresolved Critical/Important findings." Stamp (`speckit.spex-gates.stamp.md`) delegates to verify, so it inherits Step 0 without modification.

**Checkpoint**: Verify stops at Step 0 when unresolved Critical/Important findings exist. Stamp inherits the same behavior via delegation.

---

## Phase 3: Polish & Verification

**Purpose**: Final validation

- [x] T008 Run `make validate` to verify schema and extension integrity
- [x] T009 Run `make release` to run the full integration test

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1**: No dependencies. Tasks are sequential (T001 creates the file, T002-T006 add to it)
- **Phase 2**: Depends on Phase 1 (script must exist). Single task T007.
- **Phase 3**: Depends on all prior phases

### Parallel Opportunities

None. All tasks are sequential within their phases.

---

## Implementation Strategy

### MVP First

1. Complete Phase 1: Create closeout gate script (T001-T006)
2. **STOP and VALIDATE**: Test script against sample REVIEW-CODE.md files
3. Complete Phase 2: Wire into verify command (T007)
4. Complete Phase 3: Full verification with `make release` (T008-T009)

---

## Notes

- Script must work with bash 3.2 (macOS built-in)
- Use grep + awk for markdown table parsing, not jq
- Output format follows existing spex script patterns (machine-readable on stdout, human-readable on stderr)
- The script reads REVIEW-CODE.md, not review-findings.md (the issue mentions both, but the actual artifact is REVIEW-CODE.md)
