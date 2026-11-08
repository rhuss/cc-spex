---
description: "Try the feature: a testability check, a tutorial-style RUNBOOK.md, and a co-pilot session that runs it with you"
argument-hint: "[<feature>] [--draft] [--force [what to try]] [--no-git]"
---

# Walkthrough - Try the Feature with a Runbook

## Overview

The point of this command is **trust through trying the feature**. It writes a
tutorial-style `RUNBOOK.md`: one end-to-end journey a person can follow to see
the feature actually work, where every step says why it matters, the exact
command to run, and what you should see before you run it. Then it runs that
runbook with you as a co-pilot: for each step you either run the command
yourself (it lands on your clipboard) or let the agent run it with full
transparency (the exact command, the real output, and an expected-versus-actual
comparison).

If nothing can be tried by hand, this command says so in one line and writes no
files. It never fabricates output, never presents a command you cannot copy and
run, and never hard-blocks `finish` or `ship`.

### Deterministic helpers (Constitution VII)

All state, freshness, structure checks, fixture lifecycle, and clipboard access
live in scripts. This command delegates to them and never re-implements their
logic inline. Resolve each from the extension's installed `scripts/` directory,
falling back to the canonical repo path:

```bash
STATUS=".specify/extensions/spex/scripts/spex-runbook-status.sh"
CHECK=".specify/extensions/spex/scripts/spex-runbook-check.sh"
FIXTURE=".specify/extensions/spex/scripts/spex-runbook-fixture.sh"
CLIP=".specify/extensions/spex/scripts/spex-runbook-clip.sh"
[ -f "$STATUS" ]  || STATUS="spex/scripts/spex-runbook-status.sh"
[ -f "$CHECK" ]   || CHECK="spex/scripts/spex-runbook-check.sh"
[ -f "$FIXTURE" ] || FIXTURE="spex/scripts/spex-runbook-fixture.sh"
[ -f "$CLIP" ]    || CLIP="spex/scripts/spex-runbook-clip.sh"
```

The runbook path always comes from `"$STATUS" locate`. Never guess it, and never
edit `.gitignore` or `.git/info/exclude` (the scratch folder ignores itself).

<HARD-GATE>
## Never Fabricate Evidence

You MUST NOT simulate, summarize, or hand-write what the system would do. Every
step runs the real command or the real action. If a step cannot be genuinely run
by either party, record it as `skipped` with an honest reason, never as a pass.
Before any command output is written into the runbook, redact credentials to
`[redacted]` (FR-028).
</HARD-GATE>

## Command forms

| Form | Behavior |
|---|---|
| `/speckit-spex-walkthrough` | Feature from the current branch. Existing runbook: run or resume. None: testability check, draft, then run. |
| `/speckit-spex-walkthrough --draft` | Testability check and draft only. No fixtures, no steps. Used by `ship`. |
| `/speckit-spex-walkthrough --force [what to try]` | Skip a "not testable" verdict and draft anyway, covering the given hint. |
| `/speckit-spex-walkthrough <feature>` | `<feature>` is a number prefix (`054`) or a spec directory name. Runs that runbook from any branch. |
| on the default branch, no feature argument | Picker over `"$STATUS" list` entries with status `drafted`, `stale`, `in_progress`, or `failed`. |

Flags combine: `<feature> --draft`, `<feature> --force`.

---

## Phase 1: Resolve feature and runbook

1. Determine the spec directory:
   - If `<feature>` is given, resolve it to `specs/<dir>` by exact directory
     name or by number prefix (`054` matches `specs/054-...`).
   - Otherwise, derive it from the current branch (`NNN-feature-name`).
   - On the default branch with no `<feature>` and no runbook for the current
     context, run `"$STATUS" list` and present a picker over entries whose status
     is `drafted`, `stale`, `in_progress`, or `failed` (FR-030). Resolve the chosen one.
2. Resolve the runbook path and scratch folder:

   ```bash
   LOC=$("$STATUS" locate "$SPEC_DIR" --create)
   RUNBOOK=$(printf '%s' "$LOC" | jq -r .runbook)
   SCRATCH=$(printf '%s' "$LOC" | jq -r .scratch)
   RELOCATED=$(printf '%s' "$LOC" | jq -r .relocated)
   ```

   If `RELOCATED` is `true`, tell the user the runbook lives at `$RUNBOOK`
   (inside the self-ignoring scratch folder) and why (detach mode keeps it out of
   git) (FR-038).
3. Read current status: `"$STATUS" show "$SPEC_DIR"`.
   - `exists: true` and status `in_progress`: go to **Resume** (Phase 6).
   - `exists: true` and status `drafted`, `failed`, or `passed`: offer to run or
     rerun, then go to Phase 4.
   - `exists: true` and status `stale` (spec 059 FR-031): `speckit-spex-evolve`
     reset the runbook after a requirement-changing spec amendment. Show the
     `stale_reason` from `show` and offer two choices: **refresh the affected
     steps** (read the spec's latest `## Revision Notes` entry, update the steps
     that exercise the superseded, retired, or added IDs, then `"$STATUS" steps`
     if the count changed) or **run as is**. Then go to Phase 4. The earlier
     step results in the body predate the change; each one is overwritten as
     its step is rerun.
   - `exists: false`: continue to Phase 2.
   - **Freshness (FR-031).** When running a previously drafted runbook, check
     `changed_since_draft` and `current` from `show`. If the code changed since
     the draft, list the `changed_files` (or show `changed_files_note` when the
     drafted commit is gone) and offer two choices: **refresh the affected
     steps** (re-read the diff, update the steps the change touches, then
     `"$STATUS" steps` if the count changed) or **run as is**. Never silently run
     a stale runbook.
4. **Unattended detection.** Treat the session as unattended when `ship` state
   (`.specify/.spex-state`) has `status: running` with `ask: never`, or when
   `finish` invoked the walkthrough with its auto option. When unattended, run
   phases 1 to 3 only and never prompt.

---

## Phase 2: Testability check (FR-001)

Skip this phase when a runbook already exists or when `--force` was given.

Judge whether a person could try the feature by hand. Draw on the spec, the
plan, `quickstart.md`, and the branch diff. There are three outcomes:

- **Testable**: there is a user-observable effect (a command's output, a file it
  writes, an API response, a page that renders). Continue to Phase 3.
- **Partly testable**: some parts can be tried, others cannot. Draft a runbook
  for the testable parts and list the rest under `## Not covered here` with
  reasons (FR-003).
- **Not testable**: the change is internal only (a refactor, a build-wiring
  change, a docs edit with no runnable effect). Print **one line** with the
  reason and the override hint, record it, and stop. Write no runbook and no
  scratch files (FR-002):

  ```text
  Not testable by hand: this change only restructures internal helpers with no user-visible effect. To try it anyway: /speckit-spex-walkthrough --force [what to try]
  ```

  Then run `"$STATUS" not-testable "$SPEC_DIR"` and stop.

**`--force [what to try]`** skips the verdict entirely and drafts a runbook,
covering the hint the user gave after `--force` (FR-002a).

---

## Phase 3: Draft the runbook (FR-004 to FR-008)

Write `RUNBOOK.md` as **one end-to-end journey in real-user order**: the steps a
person would actually take, start to finish, to exercise the feature. Do not
group by user story or by requirement; weave them into the natural order and tag
each step with the story it exercises.

Write the body with exactly these sections (structure enforced by
`spex-runbook-check.sh`):

1. `# Try it: <feature title>`
2. `## What you're testing` - a short overview and the order of the journey (FR-004).
3. `## Test environment` - one entry per fixture (filled in Phase 5). If there
   are no fixtures, say so.
4. `## Steps` - the `### Step N of M: <title> (US<k>)` blocks (FR-004a, FR-005).
5. `## Not covered here` - parts that cannot be tried, with reasons (FR-003).
   Omit this section when empty.
6. `## Coverage` - which user stories the journey covers and which it does not,
   with reasons (FR-004a).
7. `## Results` - left empty; written at wrap-up.

**Step anatomy** (exactly as the data model; the check enforces the required
parts):

```markdown
### Step N of M: <title> (US<k>)

**Why this step:** <purpose in plain words>

**Needs:** <earlier steps or fixtures, if any>

**Run:**

```
<the exact command>
```

**What you should see:** <written before running the command (FR-006)>

**If you see something else:** <symptom to likely meaning>

**Result:**
```

Rules while drafting:

- **Prerequisites become their own steps.** If a step needs a logged-in session,
  a built binary, or a running service, add an explicit earlier step for it.
- **Capture runtime values with commands**, never with a placeholder. If a step
  needs an ID or URL produced earlier, show the command that reads it (for
  example `kubectl get route ... -o jsonpath=...`), not `<the-url>`.
- **GUI or browser steps use `**Do:**`** with a short ordered list instead of
  `**Run:**` with a fenced block.
- Write `**What you should see:**` **before** you would ever run the command, so
  it is a genuine expectation and not a copy of the output (FR-006).

After writing the body:

```bash
"$STATUS" init "$RUNBOOK" --feature "$(basename "$SPEC_DIR")" --mode <light|full> --steps <N>
```

Then loop until clean:

```bash
"$CHECK" "$RUNBOOK"
```

Fix every `RUNBOOK_CHECK_FAIL` line (missing step section, step count mismatch,
placeholder inside a command block, or an unredacted secret) and re-run until it
prints `RUNBOOK_CHECK_PASS`. If you change the number of steps, call
`"$STATUS" steps "$RUNBOOK" <N>` so the count stays in sync.

**Mode is chosen by the heaviest fixture the journey needs (FR-011):**

- **light**: no fixtures, or only quick ones (a background process, a podman
  container, a podman compose stack).
- **full**: any slow local fixture (a long build, a local cluster) or any remote
  or paid fixture.

Set it with the `--mode` flag on `init`, or later with
`"$STATUS" mode "$RUNBOOK" full` (upgrades only; a downgrade after a step has a
result is rejected, FR-014).

**When `--draft` was given, stop here.** Report the drafted runbook path, the
step count, and the mode. Do not approve, set up fixtures, or run steps.

---

## Phase 4: Approve (light mode)

(Full mode adds a review pause and tiered consent; see Phase 4b below.)

In light mode, ask **one** question that approves the runbook and sets up the
quick fixtures together (FR-012, FR-017):

{harness:interactive-choice} (single-select, header: "Walkthrough"):

**"Runbook drafted: <N> steps, light mode. Fixtures needed: <list, or 'none'>. Start them and run the walkthrough?"**

1. **"Run it"**: "Start the quick fixtures and begin the step session"
2. **"Draft only"**: "Keep the runbook, do not run anything now"

If the user chooses "Draft only", stop after reporting the path.

---

## Phase 5: Test environment (light mode)

1. **Discover fixtures** the journey needs from the runbook steps, the spec, the
   plan, and `quickstart.md` (FR-015).
2. **Reuse first.** Before starting anything, check whether a needed service is
   already up (a reachable port, an existing container, an active login). If so,
   record it and do not start a duplicate (FR-016).
3. **Start quick fixtures** with the fixture script:

   ```bash
   "$FIXTURE" start "$SCRATCH" --name <name> --kind process -- <command...>
   "$FIXTURE" start "$SCRATCH" --name <name> --kind container -- podman run -d <image> <args...>
   "$FIXTURE" start "$SCRATCH" --name <name> --kind compose --file <compose-file>
   ```

   Containers use **podman** only.
4. **If `start` exits 4** (container runtime unavailable), report it with the
   command to start the runtime (for example `podman machine start`), then offer
   to **skip** the affected steps or **hand them over** for the user to run.
5. **If the user declines a fixture**, mark every step that needs it skipped and
   say why:

   ```bash
   "$STATUS" step "$RUNBOOK" <n> skipped
   ```

   Note the reason in that step's `**Result:**`.
6. **Write `## Test environment`** from `"$FIXTURE" status "$SCRATCH"`: one entry
   per fixture with how it was set up, who started it (agent or user), and its
   teardown command (FR-009).

---

## Phase 4b/5b: Full mode (review pause, tiered consent)

When the mode is `full`:

1. **Review pause before anything runs (FR-013).** Show the drafted journey and
   the fixtures it needs. Let the user change or drop steps. After edits, keep
   the count in sync with `"$STATUS" steps "$RUNBOOK" <N>`.
2. **Tiered consent, per fixture (FR-017, FR-018):**
   - **quick**: covered by the single light-mode approval.
   - **slow local** (a long build, a local cluster): state the time estimate and
     ask before starting.
   - **remote or paid** (a cloud cluster, a hosted service): state what will be
     created, how long it runs, and any possible cost, and require an explicit
     yes. If the user prefers, hand over the exact commands for them to run
     instead of running them.
3. **Record external fixtures** (anything not started by the fixture script) so
   the environment section and cleanup stay complete:

   ```bash
   "$FIXTURE" record "$SCRATCH" --name <name> --tier <slow|remote> --owner <agent|user> --teardown "<command>" --note "<how it was set up>"
   ```

4. Keep `## Test environment` in sync with `fixtures.json` (FR-009).
5. **Upgrade to full** mid-session if a light setup turns out heavy:
   `"$STATUS" mode "$RUNBOOK" full`. Never downgrade (FR-014).

---

## Phase 6: Step session

Work through the steps in order.

**Always show the total.** Every time a step is mentioned in the chat (the step
introduction, the choice header, the agent-run output, a mismatch prompt, a
"Run the rest" progress line, or a resume offer), name it as `Step <n> of <M>`,
never a bare `Step <n>`. `<M>` is `steps.total` from `"$STATUS" show` (or from
the JSON that `"$STATUS" step` prints after each recorded result). Open each step
with a progress line before its content:

```text
Step 3 of 8: Build the plan (US2) · done so far: 2 passed, 0 failed, 0 skipped
```

For each step, first show that progress line, its `**Why**`, the exact command
(or the `**Do:**` list), and `**What you should see:**`. Then offer:

{harness:interactive-choice} (single-select, header: "Step <n>/<M>"):

1. **"Run it yourself"**: pipe the exact command to the clipboard and let the
   user run it:

   ```bash
   printf '%s' "<exact command>" | "$CLIP"
   ```

   On `CLIP_OK` tell them it is on the clipboard. On exit 3 (`CLIP_UNAVAILABLE`),
   just show the command to copy (FR-022).
2. **"Let the agent run it"**: run it with full transparency (see below). **Omit
   this choice, with the reason,** when the agent cannot do the step: a browser
   step with no browser automation tool connected, another GUI, an interactive
   terminal program, an action needing user-only credentials, or an action
   outside the sandbox (FR-021).
3. **"Run the rest"**: run every remaining agent-runnable step without pausing,
   stopping at the first mismatch, the first user-only step, or the next consent
   point. Print a one-line `Step <n> of <M>: <verdict>` after each step it runs,
   so progress stays visible while it runs unattended.
4. **"Skip"**: record the step as `skipped` with a reason.

### Agent-run transparency (FR-023, FR-023a, FR-024)

When the agent runs a step:

1. Print the exact command before running it.
2. Show the **real output in full** up to about 40 lines. If it is longer, save
   it to `"$SCRATCH/step-<n>.log"` and quote only the verbatim lines that matter.
3. Give an **expected-versus-actual** comparison, one line per observation, in
   this format:

   ```text
   Step 3 of 8 · Running: <exact command>

   <full output, or: Output: 212 lines, saved to specs/054-x/.walkthrough/step-3.log>

   Expected vs actual:
     ✔ "Plan written to .sandcast/build/openshell/plan.yaml"
         → line 41: Plan written to .sandcast/build/openshell/plan.yaml
     ✘ "Components already in the base marked skip"
         → found: all 18 components marked install (lines 12 to 29)
   ```

**Browser steps** are driven by a connected browser automation tool (such as
Playwright MCP, when connected), with screenshots saved under the scratch folder
as the evidence (FR-021a). If no such tool is connected, offer "Run it yourself"
only.

### Recording results (FR-027)

Record each result the moment it is known, before moving on:

```bash
"$STATUS" step "$RUNBOOK" <n> <passed|failed|skipped>
```

Then fill that step's `**Result:**` with the verdict, who ran it, the
expected-versus-actual comparison, and the quoted output lines or the log path.
**Redact credentials to `[redacted]` before writing any output into the runbook
(FR-028).**

---

## Phase 7: Mismatch handling (FR-025, FR-026)

When actual does not match expected, offer:

1. **Investigate**: look closer (read logs, inspect state) without changing anything.
2. **Fix and retry**: only when you have identified a concrete cause. Make the
   fix, then rerun the step. There is **no retry limit**; a step may be retried
   as many times as progress is being made.
3. **Record and continue**: mark it `failed` with what was observed, and move on.
4. **Stop**: end the session here.

If the mismatch reveals that the runbook itself was wrong (an expectation that
never made sense, a command with a typo), correct the step text and note the
correction in that step's `**Result:**` (FR-026).

---

## Phase 8: Wrap-up

1. Write `## Results`: a short summary of what passed, failed, and was skipped,
   and what a reader now knows the feature does.
2. Stop the quick fixtures:

   ```bash
   "$FIXTURE" stop "$SCRATCH" --quick
   ```

   In full mode, offer **keep or teardown** for each slow and remote fixture,
   with **keep as the default**, and make sure its teardown command is recorded
   (FR-019). Mark kept fixtures with `"$FIXTURE" keep "$SCRATCH" --name <name>`.
3. Run the final check: `"$CHECK" "$RUNBOOK"`, and fix anything it reports.
4. Give the closing summary in the chat: the status, the step tally against the
   total (for example `8 steps: 6 passed, 1 failed, 1 skipped`), and the runbook
   path.

### Commit offer (FR-030a)

**Only on the default branch, and never in detach mode or an unattended
session**, offer once to commit the updated runbook with a prepared message:

```text
docs(<number>): walkthrough results
```

Never push. Do not offer this on a feature branch (the branch's own commits
cover it) or when the runbook lives in the self-ignoring scratch folder.

---

## Resume

When Phase 1 found `status: in_progress`:

1. Offer to continue from the first `pending` step, naming it with the total and
   the progress so far (for example `Continue at Step 5 of 8? 4 done: 3 passed,
   1 skipped`).
2. Offer to restart any stopped quick fixtures (`"$FIXTURE" status "$SCRATCH"`
   shows their state).
3. Before reusing a kept slow or remote fixture, check that it is still
   available; if not, set it up again under the same consent rules.

Then continue the step session (Phase 6).
