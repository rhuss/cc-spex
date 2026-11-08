# Contract: Markers, Revision Notes, and the Converge Hand-off

Phase 1 output. This is the tool-facing and reader-facing contract of the flow-back workflow: the exact strings evolve writes and the guidance it passes to `/speckit-converge`. Implementation and tests reference these forms verbatim.

## 1. Spec-item markers

| Situation | Marker on the original line | Where the replacement goes |
|---|---|---|
| Live item with an ID is replaced | append ` **SUPERSEDED by <new-ID>**` | new item with the next unused ID of that kind |
| Live item without an ID is replaced (acceptance scenario, edge case) | append ` **SUPERSEDED**` | replacement directly after the old item |
| Live item is dropped | append ` **RETIRED**` | none |
| Wording clarification, meaning unchanged | none (edit in place) | n/a — listed in the revision note only |

Rules (FR-005–FR-007): original text is otherwise unchanged; IDs are never reused, renumbered, or deleted; an item already marked is never edited or revived. A superseding item can later be superseded in turn, gaining its own marker while earlier markers remain.

## 2. Revision note — spec.md (FR-008)

Appended under a `## Revision Notes` section at the end of `spec.md` (created if missing), one entry per session:

```markdown
### 2026-11-06: <short title>

- Superseded: FR-004 → FR-012
- Retired: SC-003
- Added: FR-012, SC-007
- Clarified: US1/AS2
- Rationale: <one line>
```

Omit a line when its kind is empty for the session.

## 3. Revision note — plan.md (FR-010)

Appended under a `## Revision Notes` section at the end of `plan.md`, one entry per session that edits the plan:

```markdown
### 2026-11-06: <short title>

**Change**: <old statement> → <new statement>
**Rationale**: <why>
**Requirements**: FR-012, SC-007
**Tasks** (optional): T031, T034   # completed task IDs whose stated targets the change replaces
```

Plan is left unchanged when no plan content (target, threshold, technology, design decision) is affected (FR-009, FR-011).

## 4. Converge hand-off guidance (FR-012)

After all spec and plan edits of the session, and only when `spec.md`, `plan.md`, and `tasks.md` all exist, at least one task is complete, no task is open, and at least one resolution routes to converge, evolve invokes converge once with guidance passed as `$ARGUMENTS`. The guidance conveys, in prose:

```text
Items marked "SUPERSEDED by <ID>", the ID-less "SUPERSEDED", or "RETIRED" in spec.md
are no longer intent; do not treat them as requirements and do not re-add tasks for
them. Completed tasks that
implemented those items are history, not obligations. The "## Revision Notes" sections
at the end of spec.md and plan.md explain what changed in this session and why. Append
only the work still missing against the live spec items.
```

## 5. Converge outcomes (FR-013, FR-014, FR-016, FR-018)

| Converge result | Evolve's behavior |
|---|---|
| Converged (nothing appended) | Report spec, plan, and code agree. Do NOT start implementation. `tasks.md` is byte-identical. |
| Tasks appended, normal run | Proceed to `/speckit-implement` inside an autonomous pipeline, or offer it interactively. Then run converge once more with the same guidance and report converged or the remaining gaps. Do not loop further. |
| Tasks appended, triggered by verify/finish | Verify does not pass; finish stops before squash/merge. Do NOT start implementation. Tell the user to implement the appended tasks and re-run (FR-016, precedence over FR-014). |
| Converge unavailable or errors | Keep the spec and plan edits. Report the missing command (with the `/spex:init --update` hint) or the error. Do NOT regenerate or edit `tasks.md` (FR-018). |

## 6. Pipeline containment (FR-017)

Inside an active ship pipeline (evolve triggered from the review-code stage), the converge → implement → confirming-converge sequence runs within that stage, counts against the stage's existing retry limit, and adds no pipeline stage. The `/speckit-implement` evolve invokes there runs in pipeline mode and skips its `after_implement` hooks (review-code, deep-review) so the stage is not re-entered.

## 7. Persistence-model line (FR-019, FR-028)

Recognized constitution line (lenient match — case-insensitive, hyphen ≡ space in the value, leading list marker/whitespace tolerated, anywhere, first match wins):

```text
Persistence model: flow-back
```

This project declares `flow-back`.

## 8. Downstream invalidation (FR-029, FR-030, FR-031)

When a session's spec revision note lists Superseded, Retired, or Added IDs, evolve runs both commands after the spec and plan edits and before the converge hand-off:

```bash
.specify/extensions/spex/scripts/spex-flow-state.sh invalidate
.specify/extensions/spex/scripts/spex-runbook-status.sh reset "$FEATURE_DIR" --reason "spec evolved 2026-11-08: FR-004 → FR-029"
```

| Command | Effect |
|---|---|
| `spex-flow-state.sh invalidate` | Flow mode: sets `clarified`, `review_spec_passed`, `review_plan_passed`, `review_code_passed` to `false` and prints `gates invalidated`. No state file or ship mode: no-op, exit 0. `implemented` and triage gates unchanged. |
| `spex-runbook-status.sh reset <spec-dir\|runbook> --reason <text>` | Runbook present: `status: stale`, all `step_results` `pending`, `tested_at`/`tested_fingerprint` cleared, `stale_reason` set (one line), draft stamps/mode/step count kept; prints the `show` JSON. No runbook: prints `{"reset": false, "why": "no-runbook", ...}`, exit 0. Unreadable runbook: exit 1. |

Runbook frontmatter while stale (`stale_reason` is an optional key, written only when set):

```yaml
status: stale
step_results: pending,pending,pending,pending,pending
tested_at:
tested_fingerprint:
stale_reason: spec evolved 2026-11-08: FR-004 → FR-029
```

Consumers: the status line renders `WT ⟳ 0/N`; finish and the walkthrough show `stale_reason` and offer refresh + rerun; `show` returns `"status": "stale"` and `"stale_reason"`. Recording any step result (`step`) or re-drafting (`init`) clears `stale` and `stale_reason`; `steps` keeps `stale` while every step is still pending.
