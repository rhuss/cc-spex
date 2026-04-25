# Review Plan: 017-workflow-integration-upgrade

**Reviewed**: 2026-04-18 (updated with task review)
**Verdict**: PASS

## Coverage Matrix (FR -> Plan Phase -> Tasks)

| Requirement | Plan Phase | Tasks | Status |
|------------|------------|-------|--------|
| FR-001 (Ship as workflow YAML) | Phase 4 | T024, T025 | Covered |
| FR-002 (Oversight levels) | Phase 4 | T026 | Covered |
| FR-003 (create_pr via wrapper) | Phase 4 | T029 | Covered |
| FR-004 (Teams auto-detection) | Phase 5 | T040 | Covered |
| FR-005 (Integration install) | Phase 2 | T011, T012 | Covered |
| FR-006 (Extension install) | Phase 2 | (existing) | Covered |
| FR-007 (Version gate >=0.7.4) | Phase 1+2 | T008 | Covered |
| FR-008 (Manifest version bump) | Phase 1 | T002-T006 | Covered |
| FR-009 (Plugin mapping file) | Phase 3 | T018 | Covered |
| FR-010 (Plugin detection) | Phase 3 | T019, T020 | Covered |
| FR-011 (Command plugin integration) | Phase 3 | T021-T023 | Covered |
| FR-012 (Marker hook suppression) | Phase 5 | T034-T038 | Covered |
| FR-013 (Marker lifecycle+PID) | Phase 4+5 | T027, T028, T013 | Covered |
| FR-014 (Remove legacy code) | Phase 1 | T007 | Covered |
| FR-015 (Ship as wrapper) | Phase 4 | T029 | Covered |
| FR-016 (Subagent forking) | Phase 5 | T040, T041 | Covered |
| FR-017 (Constitution amendment) | Phase 6 | T042, T043 | Covered |

**Coverage**: 17/17 requirements fully covered by 46 tasks.

## Prior Findings (All Resolved)

| Finding | Severity | Resolution |
|---------|----------|------------|
| RF-1: Subagent forking | Critical | Implement/review-code commands spawn subagents when workflow marker exists |
| RF-2: Teams as static input | Minor | Removed `use_teams` input, auto-detect at runtime |
| RF-3: Missing create-pr command | Minor | PR creation moved to ship wrapper |

## Task Quality Assessment

| Dimension | Status |
|-----------|--------|
| All tasks have IDs (T001-T046) | Pass |
| Checkbox format (`- [ ]`) | Pass |
| Story labels on story tasks | Pass |
| File paths in descriptions | Pass |
| [P] markers correct | Pass |
| Phase checkpoints present | Pass |
| Dependencies documented | Pass |
| Parallel opportunities identified | Pass |

## Minor Notes

1. T025-T028 (workflow YAML parts) are naturally done as one step despite being separate tasks. Acceptable granularity.
2. T017 (line count check) happens in Phase 3, before plugin detection (Phase 4) adds ~15-20 lines. The SC-002 target of 120 lines may need adjustment to ~140 after plugin detection is added, or move the check to Phase 7.
3. Phase ordering is correct: all dependency chains are satisfied.

## Recommendation

Plan and tasks are ready for `/speckit-implement`. Consider adjusting SC-002 from 120 to 140 lines to account for the `detect_plugins()` function added in Phase 4.
