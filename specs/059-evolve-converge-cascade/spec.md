# Feature Specification: Evolve as Flow-Back via speckit-converge

**Feature Branch**: `059-evolve-converge-cascade`

**Created**: 2026-11-02

**Status**: Draft

**Input**: Brainstorm `brainstorm/53-evolve-converge-cascade.md` (decision as revised on 2026-11-02): "Make `/speckit-spex-evolve` spex's flow-back implementation: record accepted changes in spec.md and plan.md using community supersede conventions, then let `/speckit-converge` append any remaining work, so completed task history survives spec evolution."

## Background

`/speckit-spex-evolve` resolves spec/code mismatches, usually after implementation, when review-code, verify, or finish finds deviations. Today it tells the agent to regenerate plan.md and tasks.md with `/speckit-plan` and `/speckit-tasks` after every spec change, and forbids editing them by hand. For a feature with completed tasks, regeneration destroys the completion state that spec-kit keeps inside tasks.md. Agents notice the conflict and skip the cascade, leaving spec, plan, and tasks inconsistent.

Upstream spec-kit fixes the delivery loop (specify, plan, tasks, implement, converge, repeating implement and converge until done) and leaves post-delivery artifact maintenance to a team-chosen **persistence model**:

- **Flow-forward**: completed feature directories are immutable, and changes go into a new feature directory.
- **Living spec**: spec.md is the contract, and plan and tasks are regenerated from it.
- **Flow-back**: accepted discoveries are reconciled into whichever artifacts they affect.

Upstream deliberately provides no amend or reconcile command and points to extensions for that. Its rule is that accepting a discovery is a human decision that must be written into the intended contract before convergence. `/speckit-converge` never accepts code as a substitute for documented intent. It only appends traced tasks to tasks.md and never rewrites existing ones. The community reconcile extension and the upstream revise proposal mark replaced requirements `SUPERSEDED by <ID>` and dropped ones `RETIRED`, instead of rewriting them.

This feature makes evolve spex's flow-back implementation, following those conventions.

## Clarifications

### Session 2026-11-06

- Q: How is the constitution's `Persistence model:` line matched (case, location, list marker)? → A: Case-insensitive for both the label and the value, tolerant of a leading Markdown list marker and surrounding whitespace, matchable anywhere in the file; the first matching line wins.
- Q: Inside a ship run, does the `/speckit-implement` that evolve invokes for converge-appended tasks skip its `after_implement` review hooks? → A: Yes. It runs in pipeline mode with `after_implement` hooks (review-code, deep-review) skipped, so the review-code stage is not re-entered recursively.
- Q: What structure does the spec.md `## Revision Notes` entry use? → A: The same structure as plan.md (FR-010): a `### YYYY-MM-DD: <title>` subheading listing the superseded, retired, added, and clarified item IDs grouped by kind, with a one-line rationale.
- Q: Should the persistence-model matcher also accept the spaced value `living spec`, not only `living-spec`? → A: Yes. The value comparison treats an internal hyphen and a space as equivalent, so `living-spec` and `living spec` both match (FR-019).
- Q: Should a session whose only change is a semantics-preserving wording clarification still invoke `/speckit-converge`? → A: Yes. Converge runs as a cheap consistency confirmation; it reports converged and leaves tasks.md byte-identical (FR-004, Edge Cases).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Spec catches up to finished code, task history intact (Priority: P1)

A developer finishes a feature. Review-code finds that the code uses a different threshold than FR-004 states, and the developer accepts the code's value. Evolve marks FR-004 `SUPERSEDED by FR-012` and adds FR-012 with the new value. It updates the plan section that named the old threshold and adds a dated revision note to spec.md and plan.md. Then it runs `/speckit-converge`, telling it how to read the markers. Converge reports converged. tasks.md is byte-identical, and every completed task keeps its mark.

**Why this priority**: This is the case that triggered the feature. It is the most common evolve outcome after implementation, and today it either destroys task history or leaves artifacts inconsistent.

**Independent Test**: Take a feature with all tasks complete and a mismatch where the code is right. Run evolve and choose "update spec". Check that the old requirement carries the supersede marker and a new ID holds the new behavior. Check that plan.md states only the new value and both files gained a revision note. Check that tasks.md is byte-identical and that evolve reports a converged result.

**Acceptance Scenarios**:

1. **Given** a feature with all tasks complete and a mismatch resolved as "update spec" that changes a requirement's meaning, **When** evolve finishes, **Then** the old requirement line is unchanged except for an appended `SUPERSEDED by <new-ID>` marker, and a new requirement with the next unused ID states the accepted behavior.
2. **Given** the accepted change contradicts what plan.md states, **When** evolve finishes, **Then** the affected plan.md passage states the new intent, and plan.md ends with a dated revision note naming the change, the rationale, and the affected IDs.
3. **Given** the accepted change touches nothing that plan.md states, **When** evolve finishes, **Then** plan.md is unchanged.
4. **Given** the spec and plan edits are done and the code already satisfies the new requirement, **When** evolve runs converge, **Then** converge reports converged, tasks.md is byte-identical to before, and evolve does not start implementation.
5. **Given** any evolve run on a feature with at least one completed task, **When** evolve finishes, **Then** neither `/speckit-plan` nor `/speckit-tasks` was invoked.

---

### User Story 2 - Evolved spec requires new behavior (Priority: P2)

During review the developer decides the spec should require something the code does not do yet. Evolve adds the new requirement (or supersedes an existing one), updates the plan if a design decision changes, and runs converge. Converge appends a Convergence phase with tasks traced to the new requirement. Evolve proceeds to (or offers) `/speckit-implement`, then runs converge once more to confirm. Earlier phases stay untouched.

**Why this priority**: This is the second evolve direction. It needs the same append-only guarantee and must end in working code, not only updated documents.

**Independent Test**: Take a completed feature and evolve the spec to add a requirement the code lacks. Check that every pre-existing tasks.md line is unchanged, that a new Convergence phase traced to the new ID is appended, that implementation runs or is offered, and that the confirming converge run reports converged.

**Acceptance Scenarios**:

1. **Given** a new or superseding requirement that the code does not satisfy, **When** evolve runs converge, **Then** tasks.md gains a Convergence phase at the end, and every pre-existing line of tasks.md is unchanged.
2. **Given** converge appended tasks, **When** evolve continues, **Then** it proceeds to `/speckit-implement` inside an autonomous pipeline, or offers it interactively.
3. **Given** the appended tasks were implemented, **When** evolve runs its single confirming converge, **Then** converge reports converged, or the remaining gaps are reported to the user.

---

### User Story 3 - Code fix traced as a task (Priority: P2)

Review finds code that contradicts a correct requirement in a non-trivial way. Evolve chooses "fix code". Instead of patching silently, evolve runs converge, which appends a task traced to the requirement with gap type `contradicts`. Implementation then fixes it. A trivial deviation (naming, formatting) is still fixed directly.

**Why this priority**: It keeps tasks.md an honest record of all post-implementation work. It occurs less often than spec updates.

**Independent Test**: In a completed feature, introduce a deviation of severity Minor or higher. Run evolve with "fix code". Check that a traced `contradicts` task is appended and that spec.md and plan.md are unchanged. Repeat with a Trivial deviation and check that it is fixed directly with no artifact change.

**Acceptance Scenarios**:

1. **Given** a fix-code resolution of severity Minor, Major, or Critical, **When** evolve handles it, **Then** spec.md and plan.md are unchanged and converge appends a task traced to the affected requirement.
2. **Given** a session whose only resolutions are Trivial fix-code ones, **When** evolve handles them, **Then** the code is fixed directly, converge does not run, and spec.md, plan.md, and tasks.md are unchanged.

---

### User Story 4 - Persistence model respected (Priority: P3)

A project's constitution declares that completed feature directories are immutable (flow-forward). The developer runs evolve on a delivered feature. Evolve writes nothing to that feature's artifacts. It explains that this project records changes in a new feature directory and recommends starting one. A project that declares nothing gets flow-back behavior, and evolve mentions once that a model can be declared.

**Why this priority**: Upstream asks teams to choose a persistence model. Evolve must not silently impose flow-back on a team that chose otherwise, but most spex projects will run on the default.

**Independent Test**: Declare flow-forward in a test project's constitution, run evolve on a delivered feature, and check that no file in the feature directory changed and that a new feature directory is recommended. Remove the declaration and check that flow-back behavior applies.

**Acceptance Scenarios**:

1. **Given** a constitution declaring flow-forward, **When** evolve resolves a mismatch on a delivered feature, **Then** no file in that feature directory changes, and evolve recommends a new feature directory for the change.
2. **Given** a constitution declaring living spec and a feature with no completed task, **When** evolve changes the spec, **Then** evolve may regenerate plan.md and tasks.md.
3. **Given** a constitution declaring living spec and a feature with at least one completed task, **When** evolve changes the spec, **Then** evolve applies the flow-back cascade and does not regenerate.
4. **Given** a constitution declaring no model, **When** evolve runs, **Then** it applies flow-back and states once that the project can declare a persistence model.

---

### User Story 5 - Reviewers judge code against live intent only (Priority: P3)

After an evolve, completed tasks still mention the old threshold. When review-code or verify assesses the feature, it judges the code against the live spec items only. It does not report the superseded requirement or the old task wording as drift, and it still reports real gaps against the new requirement.

**Why this priority**: Without this, the append-only model produces false findings that push agents back toward regeneration.

**Independent Test**: After a Story 1 evolve, run review-code and verify. Check that neither reports a finding whose only evidence is a superseded or retired item or a completed task's wording. Check that an unmet live requirement is still reported.

**Acceptance Scenarios**:

1. **Given** a requirement marked `SUPERSEDED by` or `RETIRED`, **When** review-code or verify assesses compliance, **Then** that requirement is not counted as unmet.
2. **Given** a completed task whose wording differs from the current spec, **When** review-code or verify assesses the feature, **Then** no finding is raised based only on that task's wording.
3. **Given** a live requirement the code does not satisfy, **When** review-code or verify assesses the feature, **Then** the gap is reported.

---

### Edge Cases

- **Evolve before any task is complete**: nothing would be lost, so evolve MAY regenerate plan and tasks via `/speckit-plan` and `/speckit-tasks`, as it does today. The flow-back cascade applies once at least one task is complete.
- **No plan.md or tasks.md yet**: evolve edits the spec only and does not run converge.
- **Some tasks complete, some still open** (evolve during implementation): evolve applies the spec and plan edits but does not run converge, because converge duplicates work when tasks are still open. It lists the open tasks that relate to superseded or retired items so the user can review them before implementing, and reports that converge runs after the open tasks are done.
- **Wording clarification that keeps the meaning**: edited in place with no supersede marker. It is still listed in the spec revision note. A session whose only change is such a clarification still routes through `/speckit-converge` per FR-002 and FR-004; converge confirms consistency and leaves tasks.md byte-identical.
- **A superseding requirement is itself replaced later**: the newer line gets its own `SUPERSEDED by` marker. Earlier markers stay as they are, so the chain can be followed.
- **A requirement already marked `SUPERSEDED by` or `RETIRED`**: evolve never edits or revives it. Changes always go to the live item.
- **Several mismatches in one evolve session**: all spec and plan edits are applied first, then converge runs once for the whole session, with a single revision note entry per file.
- **Converge appends `unrequested` tasks** (code the spec never asked for): evolve presents them to the user before implementation. Inside an autonomous ship run they pause the pipeline at every oversight level, because removing code is a judgment call.
- **Evolve triggered by verify or finish, and converge appends tasks**: verify does not pass, and finish stops before squash or merge. Evolve does not start implementation in this case. The user implements the appended tasks and re-runs verify or finish.
- **Evolve inside an active ship pipeline** (triggered from review-code, the pipeline's last stage): the converge, implement, and confirming-converge loop runs within that stage and counts against the stage's existing retry limit. No pipeline stage is added.
- **`/speckit-converge` unavailable or stops with an error**: evolve keeps the spec and plan edits, reports the missing command (with the `/spex:init --update` hint) or the error, and neither regenerates nor edits tasks.md.

## Requirements *(mandatory)*

### Functional Requirements

In this spec, a **completed task** is a tasks.md line starting with `- [x]` or `- [X]`, and an **open task** is one starting with `- [ ]`. A **spec item** is a functional requirement, success criterion, acceptance scenario, or edge case entry.

**Cascade**

- **FR-001**: Evolve MUST NOT invoke `/speckit-plan` or `/speckit-tasks` for a feature whose tasks.md contains at least one completed task.
- **FR-002**: Evolve MUST replace its current "never manually edit plan.md or tasks.md, always regenerate" instruction with this per-resolution cascade:

  | Resolution | Cascade |
  |---|---|
  | Update or clarify spec | Spec edits (FR-005 to FR-008), plan edits if plan content is affected (FR-009 to FR-011), then converge |
  | Fix code, severity Minor, Major, or Critical | Converge only, with spec and plan unchanged |
  | Fix code, severity Trivial | Direct code fix, with no artifact change |

- **FR-003**: Evolve MUST NOT edit tasks.md. After implementation, tasks MUST be added only by `/speckit-converge`.
- **FR-004**: After all spec and plan edits of a session, evolve MUST invoke `/speckit-converge` once before any implementation. It does so only when spec.md, plan.md, and tasks.md all exist, at least one task is complete, no task is open, and at least one resolution in the session routes to converge per FR-002. When open tasks remain, evolve MUST NOT invoke converge. It MUST instead list the open tasks related to superseded or retired items and report that converge runs after the open tasks are done.

**Spec edits**

- **FR-005**: When a resolution changes what a live spec item requires, evolve MUST leave the old item's text unchanged and append the trailing marker `**SUPERSEDED by <new-ID>**` to it. It MUST add the replacement as a new item with the next unused ID of that kind (for example FR-012 or SC-007). For items without IDs (acceptance scenarios, edge case entries), the marker is `**SUPERSEDED**` and the replacement goes directly after the old item. Revision notes refer to such items by position, for example `US1/AS2` for User Story 1, Acceptance Scenario 2.
- **FR-006**: When a resolution drops a live spec item, evolve MUST append the trailing marker `**RETIRED**` to it and keep the line.
- **FR-007**: Evolve MUST NOT reuse, renumber, or delete any spec item ID, and MUST NOT edit or revive an item already marked `SUPERSEDED by` or `RETIRED`. A wording clarification that does not change what an implementation must do MAY be edited in place without a marker.
- **FR-008**: Evolve MUST append one entry per session to a `## Revision Notes` section at the end of spec.md, creating the section if missing. Each entry uses a `### YYYY-MM-DD: <title>` subheading (the same dated-subheading convention as plan.md per FR-010; the entry bodies legitimately differ) and lists the superseded, retired, added, and clarified item IDs grouped by kind, with a one-line rationale.

**Plan edits**

- **FR-009**: When an accepted change contradicts something plan.md states (a target, threshold, technology, or design decision), evolve MUST edit that passage in place so plan.md states only current intent.
- **FR-010**: Each session that edits plan.md MUST append one entry to a `## Revision Notes` section at the end of plan.md. The entry uses a `### YYYY-MM-DD: <title>` heading followed by **Change** (old, then new), **Rationale**, and **Requirements** (affected spec item IDs). It MAY add **Tasks** listing completed task IDs whose stated targets the change replaces.
- **FR-011**: Evolve MUST leave plan.md unchanged when no plan content is affected. It MUST change research.md, data-model.md, quickstart.md, or contracts/ only where the accepted change contradicts what they state.

**Converge hand-off**

- **FR-012**: Evolve MUST pass guidance to `/speckit-converge` through its arguments. The guidance states that items marked `SUPERSEDED by` or `RETIRED` are not intent, that completed tasks implementing them are history and not obligations, and that the revision notes explain spec and plan changes.
- **FR-013**: When converge reports converged, evolve MUST report that spec, plan, and code agree, and MUST NOT start implementation.
- **FR-014**: When converge appends tasks, evolve MUST proceed to `/speckit-implement` inside an autonomous pipeline and offer it interactively otherwise. After implementation, it MUST run converge once more with the same guidance, then report a converged result or the remaining gaps. It MUST NOT loop further on its own.
- **FR-015**: Evolve MUST present appended tasks of gap type `unrequested` to the user before implementation acts on them. Inside an autonomous ship run, they MUST pause the pipeline at every oversight level.
- **FR-016**: When evolve is triggered by verify or finish and converge appends tasks, verify MUST NOT pass, finish MUST stop before squash or merge, and evolve MUST NOT start implementation (this takes precedence over FR-014). The user is told to implement the appended tasks and re-run.
- **FR-017**: Inside an active ship pipeline, the converge, implement, and confirming-converge sequence MUST run within the review-code stage, MUST count against that stage's existing retry limit, and MUST NOT add a pipeline stage. The `/speckit-implement` that evolve invokes here MUST run in pipeline mode and skip its `after_implement` hooks (review-code, deep-review), so the review-code stage is not re-entered recursively.
- **FR-018**: When `/speckit-converge` is unavailable or stops with an error, evolve MUST keep the spec and plan edits, report the missing command (with an upgrade hint) or the error, and MUST NOT regenerate or edit tasks.md.

**Persistence model**

- **FR-019**: Evolve MUST determine the project's persistence model from a line in the constitution of the form `Persistence model: flow-back`, `Persistence model: flow-forward`, or `Persistence model: living-spec`. Matching is case-insensitive for both the `Persistence model:` label and its value, treats an internal hyphen and a space as equivalent within the value (so `living-spec` and `living spec` both match), tolerates a leading Markdown list marker and surrounding whitespace, and may match anywhere in the constitution; the first matching line wins. When no such line exists, or its value is not one of the three, the model counts as not declared. Flow-back then applies, and evolve states once that a model can be declared.
- **FR-020**: Under a declared flow-forward model, evolve MUST NOT change any file in a delivered feature's directory, and MUST recommend a new feature directory for the change. A feature counts as delivered when all of its tasks are complete. Before that, discoveries are part of delivery and the flow-back cascade applies.
- **FR-021**: Under a declared living-spec model, evolve MAY regenerate plan.md and tasks.md only when no task is complete. Otherwise it MUST apply the flow-back cascade.

**Downstream consumers**

- **FR-022**: Review-code and verify MUST assess compliance against live spec items only. Items marked `SUPERSEDED by` or `RETIRED` MUST NOT count as unmet.
- **FR-023**: Review-code and verify MUST NOT raise a finding whose only evidence is the wording of a completed task.
- **FR-024**: Review-code and verify MUST continue to report live spec items the code does not satisfy.
- **FR-025**: Wherever spex tells the agent to run `/speckit-analyze`, the guidance MUST state that findings about superseded or retired items, or about completed tasks for them, are expected and not actionable.

**Scope and documentation**

- **FR-026**: All behavior changes MUST live in spex extension files. Files under `.specify/` that come from upstream spec-kit (templates, scripts, generated commands) MUST NOT be modified. The project constitution (`.specify/memory/constitution.md`) is project content, not an upstream file, and is changed only as FR-028 requires.
- **FR-027**: README.md and spex/docs/help.md MUST describe evolve's flow-back cascade: supersede markers, revision notes, the converge hand-off, append-only tasks.md, and persistence model handling.
- **FR-028**: The project constitution MUST declare this project's persistence model with the line `Persistence model: flow-back`. It MUST also clarify that "plan and tasks SHOULD be generated by `/speckit-plan` and `/speckit-tasks`" applies before implementation, and that after implementation, flow-back edits and converge-appended tasks are the expected path.

### Key Entities

- **Spec item**: a functional requirement, success criterion, acceptance scenario, or edge case entry in spec.md. It is either live, `SUPERSEDED by <ID>`, or `RETIRED`. Its ID is never reused.
- **Revision note**: a dated entry in the `## Revision Notes` section at the end of spec.md or plan.md. It records what an evolve session changed and why, and which IDs it affected.
- **Convergence phase**: a `## Phase N: Convergence` section that `/speckit-converge` appends to tasks.md. Its tasks are traced to spec item IDs and tagged `missing`, `partial`, `contradicts`, or `unrequested`.
- **Persistence model**: the project's declared post-delivery artifact convention (flow-back, flow-forward, or living spec), recorded in the constitution.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In 100% of evolve runs on features with at least one completed task, every pre-existing line of tasks.md is unchanged afterwards.
- **SC-002**: In 100% of evolve runs where the spec catches up to correct code, tasks.md is byte-identical before and after, and evolve reports a converged result.
- **SC-003**: In 100% of evolve runs where the spec requires new behavior, the missing work appears as appended tasks traced to the new spec item IDs, and the confirming converge run after implementation reports converged or lists the remaining gaps.
- **SC-004**: After an evolve, review-code and verify report zero findings whose only evidence is a superseded or retired item or a completed task's wording.
- **SC-005**: A reader can identify, from spec.md alone and without git history, every spec item that was replaced or dropped after implementation, what replaced it, and the date of the change.
- **SC-006**: Under a declared flow-forward model, 100% of evolve runs on delivered features leave the feature directory unchanged.
- **SC-007**: Evolve's instructions contain no remaining directive to regenerate plan.md or tasks.md for features with completed tasks.

## Assumptions

- `/speckit-converge` ships with the spec-kit version spex requires. Projects on older versions get the FR-018 fallback.
- Evolve's existing severity scale (Critical, Major, Minor, Trivial) decides fix-code routing. Only Trivial bypasses converge.
- The supersede marker vocabulary matches the community reconcile extension and the upstream revise proposal, so artifacts stay readable by those tools. Evolve does not detect, call, or defer to an installed reconcile extension.
- spex-collab `revise` (pre-merge spec PR revisions) is out of scope. It keeps its regenerate-and-reconcile model.
- Evolve's existing mismatch detection, analysis, and recommendation stay as they are. Only what happens after a resolution is decided changes.
- Accepting a discovery is a human decision, as upstream requires. Evolve's existing auto-update setting therefore applies only to Trivial changes and wording clarifications. A `SUPERSEDED by` or `RETIRED` marking always needs the user's decision, or, inside a ship run, a decision under that run's oversight level.
- Upstream converge's user-input handling ("MUST consider the user input") is the supported channel for the FR-012 guidance.
- No new ship state commands are needed, because the sequence runs inside an existing stage.
