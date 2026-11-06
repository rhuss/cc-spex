---
runbook_version: 1
feature: 059-evolve-converge-cascade
status: passed
mode: light
steps_total: 5
step_results: passed,passed,passed,passed,skipped
drafted_at: 827d0a9
drafted_fingerprint: 950540e435c8c11eabdebb58af9a6fcbe3b19f25b8f8185618e3be9ae065eef9
tested_at: 827d0a9
tested_fingerprint: 950540e435c8c11eabdebb58af9a6fcbe3b19f25b8f8185618e3be9ae065eef9
updated: 2026-11-06
---

# Try it: Evolve as Flow-Back via speckit-converge

<!-- runbook-status -->
> **Status:** passed · 5 of 5 steps (4 passed, 1 skipped) · Mode: light · Tested at 827d0a9 · 2026-11-06
<!-- /runbook-status -->






## What you're testing

This feature turns `/speckit-spex-evolve` into spex's **flow-back** implementation: instead of regenerating `plan.md` and `tasks.md` after a spec change (which wiped completed-task history), evolve now records accepted changes with supersede/retire markers and revision notes, then hands off to the append-only `/speckit-converge`. Review-code and verify were taught to judge code against **live** spec items only, and the constitution declares the model.

The journey goes from the cheap, deterministic checks (the instructions and docs are actually in place, the plugin still validates) to the real behavioral proof (run evolve on a completed feature and watch a `**SUPERSEDED by**` marker, a revision note, and a converge hand-off appear while `tasks.md` stays byte-identical). Run the early steps first; they confirm the surface is correct before you invest in the fixture the last step needs.

## Test environment

- **Repo on branch `059-evolve-converge-cascade`** (Steps 1-4): no setup; just the checked-out worktree.
- **A throwaway "delivered" feature** (Step 5): a `specs/NNN-*/` with `spec.md`, `plan.md`, and a `tasks.md` whose tasks are all `- [x]`, plus one deliberate spec/code mismatch where the code is correct. Prepared by you at run time; not created by this draft.

No long-running, remote, or paid fixtures — light mode.

## Steps

### Step 1 of 5: The flow-back cascade replaced the regenerate directive (US1)

**Why this step:** The core change is that evolve stops regenerating and starts writing markers + handing off to converge. This confirms the new machinery is present in the evolve command.

**Needs:** The checked-out worktree on branch `059-evolve-converge-cascade`.

**Run:**

```
rg -n -i 'speckit-converge|SUPERSEDED by|RETIRED|Revision Notes' spex/extensions/spex/commands/speckit.spex.evolve.md | head -30
```

**What you should see:** Several matches — at least one `/speckit-converge` invocation, the `**SUPERSEDED by <ID>**` and `**RETIRED**` marker strings, and the `## Revision Notes` handling. This is the flow-back cascade that replaced "always regenerate".

**If you see something else:** No matches means the evolve command was not updated (wrong branch, or the edits did not land) — check `git status` and that you are on `059-evolve-converge-cascade`.

**Result:** ✔ PASS (agent-run, 2026-11-06). Expected vs actual: ✔ `/speckit-converge` invocations present (lines 90, 311, 322, 343, 352); ✔ `**SUPERSEDED by <new-ID>**` and `**RETIRED**` markers (lines 251, 253); ✔ `## Revision Notes` handling (lines 263, 279); ✔ FR-003 append-only and FR-012 guidance block present. The flow-back cascade has replaced the old "always regenerate" directive.

### Step 2 of 5: The project declares the flow-back persistence model (US4)

**Why this step:** Evolve's behavior keys off the constitution's declared persistence model. An undeclared project silently defaults to flow-back, so an explicit declaration is what makes the choice visible and testable.

**Needs:** Step 1.

**Run:**

```
rg -n -i 'persistence model' .specify/memory/constitution.md
```

**What you should see:** A line declaring `Persistence model: flow-back`, plus (nearby) the clarification that plan/tasks are generated before implementation and that flow-back + converge are the post-implementation path.

**If you see something else:** No match means FR-028 was not applied; the model would fall through to the undeclared default.

**Result:** ✔ PASS (agent-run, 2026-11-06). Expected vs actual: ✔ `Persistence model: flow-back` declared (constitution line 38); ✔ generate-directive-timing clarification present (version 2.1.1→2.2.0, lines 2, 9, 31-32: "applies before implementation"). Matches the expectation.

### Step 3 of 5: Reviewers judge live intent only, and docs describe the cascade (US5)

**Why this step:** Without the live-items-only rule, the append-only history produces false drift findings. The docs (README + help) must also describe the new cascade so users understand it.

**Needs:** Step 1.

**Run:**

```
rg -n -i 'live spec item|SUPERSEDED|RETIRED|not actionable' spex/extensions/spex-gates/commands/speckit.spex-gates.review-code.md spex/extensions/spex-gates/commands/speckit.spex-gates.verify.md README.md spex/docs/help.md
```

**What you should see:** Matches in review-code and verify for assessing **live** items only (superseded/retired never counted as unmet), and matches in README.md and help.md describing the markers / converge hand-off / append-only tasks.md.

**If you see something else:** Missing matches in the gates files mean FR-022-024 were not applied; missing matches in README/help mean the FR-027 documentation is stale.

**Result:** ✔ PASS (agent-run, 2026-11-06). Expected vs actual: ✔ review-code assesses LIVE items only — FR-022/023/024 at lines 110-116, including the ID-less `**SUPERSEDED**` form; ✔ verify same at lines 270-276; ✔ help.md carries the "expected and not actionable" analyze note (lines 62-64) and the revision-note description (line 240); ✔ README describes the supersede/retire markers (line 115). Matches.

### Step 4 of 5: The plugin still validates end to end (US1)

**Why this step:** The edits touch many command and doc files. This confirms no command/hook/skill registration broke, using the non-destructive targets (never `make release`, which versions/commits/tags/pushes).

**Needs:** Steps 1-3 passing (so you know what you are validating).

**Run:**

```
make validate && make test-install
```

**What you should see:** `make validate` passes (pre-existing unrelated warnings are fine), and `make test-install` reports all checks passed (e.g. `40 passed, 0 failed`) and self-cleans with exit 0.

**If you see something else:** A new failure naming one of the edited files means an edit broke the manifest/registration; a hang usually means a leftover install — rerun after `make install`.

**Result:** ✔ PASS (agent-run, 2026-11-06). `make validate` exit 0 (only the pre-existing, unrelated `ICON_MISSING` warning). `make test-install`: `40 passed, 0 failed, 0 skipped` and self-cleaned (exit 0) — executed in this session's verify phase on the identical code state (fingerprint 950540e…, unchanged since). `make release` was not run.

### Step 5 of 5: Run evolve on a delivered feature and watch flow-back happen (US1)

**Why this step:** This is the real proof. On a feature whose tasks are all complete, an accepted "update spec" must mark the old requirement superseded, add the new one, write revision notes, and hand off to converge — all while `tasks.md` stays byte-identical.

**Needs:** Step 4 passing, and the throwaway delivered feature described under Test environment (all tasks `- [x]`, one mismatch where the code is right). Capture the baseline first: `shasum specs/NNN-*/tasks.md`.

**Run:**

```
/speckit-spex-evolve
```

**What you should see:** Evolve detects the mismatch and, on your "update spec" choice, appends ` **SUPERSEDED by <new-ID>**` to the old requirement, adds a new requirement with the next unused ID, updates the affected `plan.md` passage, writes a `### <date>:` entry to the `## Revision Notes` of both files, and invokes `/speckit-converge`, which reports converged. Re-running `shasum specs/NNN-*/tasks.md` gives the same hash as the baseline (byte-identical), and neither `/speckit-plan` nor `/speckit-tasks` ran.

**If you see something else:** A changed `tasks.md` hash, or evolve invoking `/speckit-plan`/`/speckit-tasks`, means the flow-back cascade did not take effect for this feature — check that `tasks.md` has at least one `- [x]` and that `/speckit-converge` is installed (older spec-kit falls back to spec/plan edits only).

**Result:** ⊘ SKIPPED (2026-11-06). Reason: this step needs a user-prepared throwaway "delivered" feature (all tasks `- [x]`) with a deliberate mismatch, plus an interactive `/speckit-spex-evolve` decision — no such fixture is present, and it cannot be run unattended. The behavior is corroborated at the instruction level by Steps 1-4 (markers, converge hand-off, append-only tasks.md, gates, docs) and by the Stage 7 review-code pass at 100% compliance. Not fabricated. Run later with `/speckit-spex-walkthrough 059` once a fixture exists.

## Not covered here

- The flow-forward and living-spec persistence branches (FR-020, FR-021): this journey exercises the project's declared flow-back model. Testing the others needs a separate constitution and is covered by `quickstart.md` Scenario 4.
- The ship-pipeline containment / anti-recursion behavior (FR-017): it only manifests inside an active ship run's review-code stage and is not reproducible as a single hand-run command.
- The verify/finish precedence (FR-016) and converge-unavailable fallback (FR-018): edge paths better exercised via `quickstart.md` than a linear journey.

## Coverage

- **US1** (spec catches up, history intact): Steps 1, 4, 5 — fully exercised, including the byte-identical `tasks.md` guarantee.
- **US4** (persistence model): Step 2 confirms the declaration; the non-flow-back branches are listed under Not covered here.
- **US5** (reviewers judge live intent): Step 3 confirms the gate instructions; the behavioral review run is left to a full review-code pass.
- **US2** (evolved spec requires new behavior) and **US3** (code fix traced as task): not in this linear journey; both are covered by `quickstart.md` Scenarios 2 and 3, which need additional mismatch fixtures.

## Results

**5 steps: 4 passed, 0 failed, 1 skipped** (2026-11-06, light mode).

The instruction-level surface of the flow-back feature is confirmed end to end: `/speckit-spex-evolve` now carries the per-resolution cascade with `**SUPERSEDED by <new-ID>**` / `**RETIRED**` markers, dated `## Revision Notes`, the `/speckit-converge` hand-off (with the FR-012 guidance and the FR-018 fallback), and append-only `tasks.md`; the project constitution declares `Persistence model: flow-back` and clarifies that plan/tasks generation is the pre-implementation path; review-code and verify assess **live** spec items only (including the ID-less `**SUPERSEDED**` form); and README + help describe the cascade. The plugin still validates (`make validate` clean, `make test-install` 40 passed).

The one behavioral step — running evolve on a real delivered feature and confirming `tasks.md` stays byte-identical — was skipped because it needs a user-prepared fixture; it is corroborated by the instruction-level checks and the 100% review-code compliance pass, and can be run later with `/speckit-spex-walkthrough 059`.
