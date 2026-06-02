# Research: Collab Triage Lifecycle

## R1: Flow State Gate Pattern

**Decision**: Extend the existing `do_gate()` case statement in `spex-flow-state.sh` with two new entries: `triage-spec` mapping to `triage_spec_passed` and `triage-impl` mapping to `triage_impl_passed`.

**Rationale**: The existing gate pattern (`review-spec` -> `review_spec_passed`, `review-plan` -> `review_plan_passed`, `review-code` -> `review_code_passed`) is well-established and works reliably. Adding two more entries follows the exact same pattern with zero new abstractions.

**Alternatives considered**:
- Separate triage state script: Rejected because it would violate the single-source pattern for flow state.
- Collab-specific state namespace: Rejected because the status line already reads flow state fields, adding a second source would complicate rendering.

## R2: Status Line T Badge Rendering

**Decision**: Add a `T` badge to the `render_flow()` function in `spex-ship-statusline.sh`. The badge reads `triage_spec_passed` and `triage_impl_passed` from the state JSON. It only renders when the spex-collab extension is enabled (checked via `.specify/extensions/.registry`).

**Rationale**: The existing gate badges (`C`, `S`, `P`, `R`) follow a consistent pattern: read a boolean from state JSON, render with color based on passed/running/pending. The `T` badge uses the same pattern. Collab-conditional rendering prevents confusion in projects without the collab extension.

**Alternatives considered**:
- Two separate badges (`Ts` and `Ti`): Rejected as too noisy. One `T` badge that reflects either triage phase is simpler. The badge shows `✓` only when both are passed (or when only the applicable one is passed based on workflow stage).

## R3: Suggest-with-Delay Message Pattern

**Decision**: The suggest-with-delay message is output by the phase-manager and the finish/reviewers commands at the point where PRs are created or implementation is pushed. The message reads `triage.loop_interval` from `collab-config.yml` with a shell fallback default.

**Rationale**: The message is a simple print statement at a specific workflow point. No new infrastructure needed. The `${VAR:-default}` shell pattern handles missing config gracefully (same pattern used for deep-review config).

**Alternatives considered**:
- Dedicated suggestion script: Rejected as over-engineering for a printf.
- Hook-based suggestion: Rejected because hooks fire at command boundaries, not at the specific PR-creation moment within a command.

## R4: Gate Check Comment Count Logic

**Decision**: The phase-manager reads `.specify/.pr-triage-state.json`, counts all entries (each entry represents one handled comment), and compares against `triage.split_threshold`. The count includes both bot and human comments since the total review surface is what degrades the GitHub UI.

**Rationale**: The triage state file has one entry per handled comment with the comment's database ID as key. Counting entries with `jq 'length'` (after filtering by the current PR) gives the total. Both bot and human comments contribute to UI degradation, so counting all is appropriate.

**Alternatives considered**:
- Count only bot comments: Rejected because human comments also contribute to PR size and review difficulty.
- Count from GitHub API directly: Rejected because the triage state file is already available locally and avoids an API call.

## R5: Config Template Structure

**Decision**: Add `triage` section to the existing `collab-config.yml` template with `split_threshold` (default 100) and `loop_interval` (default "5m").

**Rationale**: The config template already has structured sections (`labels`, `triage` for bot profiles). Adding a triage section with two keys is a natural extension. Defaults are chosen based on real-world experience: GitHub UI degrades around 100 comments, and 5 minutes gives bots enough time to post while keeping the loop responsive.

**Alternatives considered**:
- Separate triage config file: Rejected because collab-config already has a triage section (for bot profiles).
- No config, hardcoded values: Rejected per brainstorm decision (user requested configurability).
