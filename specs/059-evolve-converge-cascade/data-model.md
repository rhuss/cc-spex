# Data Model: Evolve as Flow-Back via speckit-converge

Phase 1 output. These are conceptual entities expressed as text structures inside Markdown artifacts, not database records. Each maps to the spec's Key Entities and to the functional requirements that govern it.

## Entity: Spec item

A functional requirement, success criterion, acceptance scenario, or edge-case entry in `spec.md`.

- **Identity**: For FRs and SCs, a stable ID (`FR-012`, `SC-007`). Acceptance scenarios and edge-case entries have no ID and are referenced by position (`US1/AS2` = User Story 1, Acceptance Scenario 2).
- **State**: one of `live`, `SUPERSEDED by <ID>`, `RETIRED`.
  - `live` → `SUPERSEDED by <new-ID>`: a resolution changes what the item requires; the old line keeps its text plus the trailing marker, and a new item with the next unused ID holds the accepted behavior (FR-005).
  - `live` → `RETIRED`: a resolution drops the item; the line stays with a trailing `**RETIRED**` marker (FR-006).
  - A `live` item may be edited in place with no marker only for a wording clarification that does not change what an implementation must do (FR-007).
- **Invariants**:
  - IDs are never reused, renumbered, or deleted (FR-007).
  - An item already `SUPERSEDED by`/`RETIRED` is never edited or revived; changes go to the live item (FR-007).
  - A superseding item can itself later be superseded; the newer line gets its own marker and earlier markers stay, forming a followable chain (Edge Cases).
- **Consumers**: review-code, verify, and `/speckit-analyze` guidance treat only `live` items as intent (FR-022, FR-024, FR-025).

## Entity: Revision note

A dated entry in a `## Revision Notes` section at the end of `spec.md` or `plan.md`, created if missing. One entry per evolve session per file.

- **spec.md entry (FR-008)**: a `### YYYY-MM-DD: <title>` subheading (the same dated-subheading convention as plan.md; bodies differ) listing the superseded, retired, added, and clarified item IDs grouped by kind, with a one-line rationale.
- **plan.md entry (FR-010)**: a `### YYYY-MM-DD: <title>` subheading followed by **Change** (old → new), **Rationale**, and **Requirements** (affected spec item IDs). MAY include **Tasks** listing completed task IDs whose stated targets the change replaces.
- **Invariant**: a single entry per file per session, even when the session resolved several mismatches (Edge Cases).
- **Purpose**: SC-005 — a reader can identify, from `spec.md` alone and without git history, every item replaced or dropped after implementation, what replaced it, and the date.

## Entity: Convergence phase

A `## Phase N: Convergence` section that `/speckit-converge` appends to `tasks.md`. Evolve never writes it directly (FR-003).

- **Fields**: traced tasks of the form `- [ ] T0NN ... per FR-003 (missing)`, each tagged with a gap type.
- **Gap types**: `missing`, `partial`, `contradicts`, `unrequested` (verified against the installed converge command).
- **Invariants**: append-only — every pre-existing line of `tasks.md` is unchanged; when nothing is missing, `tasks.md` is byte-identical (SC-001, SC-002).
- **Special handling**: `unrequested` tasks (code the spec never asked for) are presented to the user before implementation; inside an autonomous ship run they pause the pipeline at every oversight level (FR-015).

## Entity: Persistence model

The project's declared post-delivery artifact convention, recorded in the constitution.

- **Values**: `flow-back`, `flow-forward`, `living-spec`.
- **Source line**: `Persistence model: <value>`, matched leniently — case-insensitive label and value, hyphen ≡ space within the value, leading list marker and surrounding whitespace tolerated, anywhere in the file, first match wins (FR-019).
- **Default**: not declared → `flow-back`, stated once (FR-019).
- **Effect on behavior**:
  - `flow-forward`: on a **delivered** feature (all tasks complete), evolve changes no file in that feature directory and recommends a new feature directory. Before delivery, flow-back cascade applies (FR-020).
  - `living-spec`: evolve MAY regenerate `plan.md`/`tasks.md` only when no task is complete; otherwise flow-back cascade applies (FR-021).
  - `flow-back` (this project, FR-028): the cascade in FR-002 always applies after at least one task is complete.

## Derived definitions (from spec)

- **Completed task**: a `tasks.md` line starting with `- [x]` or `- [X]`.
- **Open task**: a line starting with `- [ ]`.
- **Delivered feature**: one whose tasks are all complete (FR-020).
