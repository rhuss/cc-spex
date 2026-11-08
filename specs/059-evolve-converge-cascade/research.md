# Research: Evolve as Flow-Back via speckit-converge

Phase 0 output. Each item below resolves a decision needed before design. The spec is mature, so most "unknowns" are confirmations of upstream behavior and placement rules rather than open questions.

## R1. Supersede / retire marker vocabulary

- **Decision**: Use `**SUPERSEDED by <new-ID>**` for a replaced item with an ID, `**SUPERSEDED**` for ID-less items (acceptance scenarios, edge-case entries), and `**RETIRED**` for a dropped item. Markers are appended to the end of the original line; the original text is otherwise unchanged.
- **Rationale**: Matches the community reconcile extension and the upstream revise proposal, so evolved artifacts stay readable by those tools (Assumption in spec). Trailing bold markers are greppable and survive Markdown rendering.
- **Alternatives considered**: HTML comments (invisible, but not reader-facing per SC-005); a separate "superseded" appendix list (loses locality — the reader must cross-reference); strikethrough (ambiguous vs. a real deletion). Rejected in favor of in-line trailing markers.

## R2. `/speckit-converge` interpretation-guidance channel

- **Decision**: Evolve passes guidance to converge as free-text `$ARGUMENTS` on invocation. The guidance states that items marked `SUPERSEDED by`/`RETIRED` are not intent, that completed tasks implementing them are history (not obligations), and that the revision notes explain the changes.
- **Rationale**: Verified against the installed `/speckit-converge` command — it accepts `$ARGUMENTS` and states "MUST consider the user input." This is the supported, append-only channel; converge never rewrites or renumbers existing tasks and leaves `tasks.md` byte-identical when nothing is missing.
- **Alternatives considered**: A sidecar file converge would read (converge has no such contract); editing tasks.md directly to mark history (violates FR-003 append-only). Rejected.

## R3. Persistence-model detection

- **Decision**: Read the constitution for a line matching `Persistence model: <value>`. Match case-insensitively for the label and value; treat an internal hyphen and space as equivalent in the value (`living-spec` ≡ `living spec`); tolerate a leading Markdown list marker and surrounding whitespace; match anywhere in the file; first match wins. Recognized values: `flow-back`, `flow-forward`, `living-spec`. Anything else, or absent, counts as not declared → flow-back applies, stated once.
- **Rationale**: Encodes the 2026-11-06 spec clarifications (lenient matching) and the review-spec resolution (tolerate the spaced `living spec` form) so a naturally written line is not silently ignored.
- **Alternatives considered**: Strict exact-string match (brittle; a user writing a bulleted or spaced line falls through silently — the risk the review flagged). Rejected.

## R4. Live-vs-superseded assessment in review-code / verify / analyze

- **Decision**: Teach review-code and verify to build their compliance set from **live** spec items only — items with no `SUPERSEDED by`/`RETIRED` marker. Superseded/retired items never count as unmet (FR-022). No finding may rest solely on the wording of a completed task (FR-023). Live items the code does not satisfy are still reported (FR-024). Wherever spex tells the agent to run `/speckit-analyze`, add a note that findings about superseded/retired items or their completed tasks are expected and not actionable (FR-025).
- **Rationale**: Without this, the append-only model generates false drift that pushes agents back toward regeneration — the exact failure this feature removes.
- **Files carrying analyze guidance** (verified via `rg`): `spex/extensions/spex-gates/commands/speckit.spex-gates.review-spec.md`, `spex/extensions/spex/commands/speckit.spex.spec-kit.md`, `spex/extensions/spex/commands/speckit.spex.evolve.md`, `spex/docs/help.md`, `spex/extensions/spex/docs/help.md`.

## R5. Evolve inside an active ship pipeline (recursion safety)

- **Decision**: When evolve runs inside a ship pipeline (triggered from the review-code stage), its converge → implement → confirming-converge sequence runs **within** that stage and counts against the stage's existing retry limit; it adds no pipeline stage. The `/speckit-implement` evolve invokes there runs in pipeline mode and skips its `after_implement` hooks (review-code, deep-review), so the review-code stage is not re-entered recursively (2026-11-06 clarification, FR-017).
- **Rationale**: Verified against the ship skill: `speckit-implement` already skips all `after_implement` hooks in pipeline mode, and blockers pause at every oversight level. Reusing that behavior prevents an infinite review→evolve→implement loop and needs no new ship-state command.
- **Detection**: Pipeline context is the established spex signal — `.specify/.spex-state` present with `status: running`. Evolve already keys off this; no new mechanism.

## R6. Testing strategy for a prose-only feature

- **Decision**: Validate by (a) scenario walkthroughs — one per user story Independent Test, captured in `quickstart.md`; (b) `rg` structural checks (no remaining "regenerate tasks.md for completed features" directive → SC-007; converge referenced in evolve; marker strings documented in help/README); (c) the existing `make release` schema + integration test to confirm no command/hook/skill regressions from the edits.
- **Rationale**: The feature changes agent instructions, not executable code, so there is no unit-test seam. Acceptance criteria are inherently scenario-shaped.
- **Alternatives considered**: Adding an automated harness that drives a live agent through evolve (out of proportion for this change; not part of the repo's current test tooling). Deferred.

## R7. Documentation surface

- **Decision**: FR-027 requires README.md and `spex/docs/help.md` to describe the flow-back cascade (markers, revision notes, converge hand-off, append-only tasks.md, persistence-model handling). If `spex/extensions/spex/docs/help.md` is a distinct maintained copy, update it identically; confirm during implementation whether the two help files are synced or independent.
- **Rationale**: Documentation Maintenance principle and FR-027. Stale docs mislead users.
- **T001 finding (2026-11-06)**: The two help files are **independent copies** (content differs), so T021 and T025 must update both. `speckit.spex.help.md` resolves them in order `.specify/extensions/spex/docs/help.md` → `spex/extensions/spex/docs/help.md` (dev repo) → `spex/docs/help.md` (legacy). `rg 'speckit-analyze'` surface: `review-spec.md`, `spec-kit.md`, `evolve.md`, and both `help.md` copies.
