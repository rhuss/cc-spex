---
runbook_version: 1
feature: 058-codex-ship-progress
status: drafted
mode: light
steps_total: 9
step_results: pending,pending,pending,pending,pending,pending,pending,pending,pending
drafted_at: 0000f33
drafted_fingerprint: 599381319a3f38233bd96a4327781864c8e41c68e0e4bda4cb52e15a7e1b3b32
tested_at:
tested_fingerprint:
updated: 2026-10-26
---

# Try it: Ship Progress in Codex

<!-- runbook-status -->
> **Status:** drafted · 0 of 9 steps · Mode: light · Drafted at 0000f33 · 2026-10-26
<!-- /runbook-status -->

## What you're testing

You will see what a Codex user sees while a ship pipeline runs, without starting Codex: the banner line and the eight-step plan that the pipeline prints after each state change, how a pause shows up, the instructions Codex receives (and that Claude receives nothing new), and the opt-in change to the Codex footer and title on a throwaway config.

Journey order: start a pipeline state, read its progress, pause and resume it, look at the done form, compare the Codex and Claude ship commands, then edit a scratch Codex config and record a decline.

All commands run from the repository root of the `058-codex-ship-progress` worktree. They only touch temporary directories.

## Test environment

No fixtures. Every step uses a temporary directory created in Step 1 and removed in the last step.

## Steps

### Step 1 of 9: Create a scratch area (US1)

**Why this step:** Keeps the pipeline state and the Codex config out of your real project and your real `~/.codex`.

**Run:**

```
export WT_TMP=$(mktemp -d) && export SHIP_STATE_FILE="$WT_TMP/.spex-state" && export CODEX_HOME="$WT_TMP/codex" && echo "$WT_TMP"
```

**What you should see:** One line with a fresh temporary directory path.

**If you see something else:** An error from `mktemp` means the temp directory is not writable; set `TMPDIR` and retry.

**Result:**

### Step 2 of 9: Start a pipeline at implement and read its progress (US1)

**Needs:** Step 1

**Why this step:** This is what Codex prints after `create`: one banner line and the plan it passes to `update_plan`.

**Run:**

```
spex/scripts/spex-ship-state.sh create brainstorm/51-codex-ship-progress.md --start-from implement && spex/scripts/spex-ship-state.sh progress
```

**What you should see:** `CREATED stage=implement index=6 ask=smart`, then `BANNER 🧬 ship 🔨 implement ▓▓▓▓▓▓▓░░ 7/8 🧠`, then a `PLAN [...]` line with eight entries: specify through review-plan `completed`, `implement` `in_progress`, `review-code` `pending`. No color codes.

**If you see something else:** No output after `CREATED` means `progress` did not find the state file; check that `SHIP_STATE_FILE` is still exported in this shell.

**Result:**

### Step 3 of 9: Pause and see the paused marker (US2)

**Needs:** Step 2

**Why this step:** A paused pipeline waiting for input is the moment a user most needs to notice.

**Run:**

```
spex/scripts/spex-ship-state.sh pause && spex/scripts/spex-ship-state.sh progress
```

**What you should see:** `PAUSED`, a banner ending in `🧠 ⏸ paused`, and in the plan the current step labelled `implement (paused)` with status `in_progress`.

**If you see something else:** A banner without `⏸ paused` means the banner mode did not read the status field.

**Result:**

### Step 4 of 9: Resume and see the marker disappear (US2)

**Needs:** Step 3

**Why this step:** After the user replies, the indicators must return to normal.

**Run:**

```
spex/scripts/spex-ship-state.sh resume && spex/scripts/spex-ship-state.sh progress
```

**What you should see:** `RESUMED stage=implement index=6 ask=smart`, the banner from Step 2 again (no `⏸ paused`), and the plan step labelled plain `implement`.

**If you see something else:** A leftover `(paused)` suffix means the plan builder ignored the new status.

**Result:**

### Step 5 of 9: See the done form and the empty case (US1)

**Needs:** Step 1

**Why this step:** At completion the banner must be the Claude done line without colors and all eight steps completed; without a state file, nothing is printed.

**Run:**

```
printf '{"mode":"ship","stage":"done","stage_index":8,"total_stages":8,"ask":"smart","status":"completed"}\n' > "$SHIP_STATE_FILE" && spex/scripts/spex-ship-state.sh progress && rm "$SHIP_STATE_FILE" && spex/scripts/spex-ship-state.sh progress; echo "exit=$?"
```

**What you should see:** `BANNER 🧬 ship ✅ done ▓▓▓▓▓▓▓▓ 8/8`, a `PLAN` with eight `completed` entries, then nothing more except `exit=0`.

**If you see something else:** Any traceback after the `rm` means the missing-state case is not handled silently.

**Result:**

### Step 6 of 9: Compare the Codex and Claude ship commands (US1, US4)

**Why this step:** Codex must get the progress rule, Claude must get nothing new.

**Run:**

```
for h in codex claude; do rm -rf "$WT_TMP/ext-$h"; cp -R spex/extensions "$WT_TMP/ext-$h"; spex/scripts/spex-adapt-commands.sh "$h" "$WT_TMP/ext-$h" spex/scripts/adapters >/dev/null; echo "$h: $(grep -c 'update_plan' "$WT_TMP/ext-$h/spex/commands/speckit.spex.ship.md") update_plan mentions, $(grep -c 'harness:ship-progress' "$WT_TMP/ext-$h/spex/commands/speckit.spex.ship.md") raw markers"; done
```

**What you should see:** `codex:` with one or more `update_plan` mentions and `0 raw markers`; `claude: 0 update_plan mentions, 0 raw markers`.

**If you see something else:** Raw markers left in either output mean the adapter did not resolve the `ship-progress` block.

**Result:**

### Step 7 of 9: Check and apply the footer/title change on a scratch config (US3)

**Needs:** Step 1

**Why this step:** This is the change Codex init makes after you say yes: it appends `task-progress` and keeps everything else.

**Run:**

```
mkdir -p "$CODEX_HOME" && printf '# my settings\n[tui]\nstatus_line = ["model-with-reasoning", "git-branch"]\n' > "$CODEX_HOME/config.toml" && python3 spex/scripts/spex-codex-progress.py check --root "$WT_TMP" && python3 spex/scripts/spex-codex-progress.py apply && cat "$CODEX_HOME/config.toml" && python3 spex/scripts/spex-codex-progress.py check --root "$WT_TMP"
```

**What you should see:** `ASK`, then `APPLIED path=.../codex/config.toml`, then the file with `# my settings` kept, `status_line = ["model-with-reasoning", "git-branch", "task-progress"]`, and `terminal_title = ["activity", "thread-name", "project-name", "task-progress"]` added inside `[tui]`, then `CONFIGURED`.

**If you see something else:** `UNSUPPORTED` from `check` means your `python3` has no TOML reader (needs 3.11+ or `tomli`); exit code 3 from `apply` with a snippet means the file form was rejected.

**Result:**

### Step 8 of 9: Decline in a scratch project (US3)

**Needs:** Step 1

**Why this step:** A "no" must be remembered per project so init does not ask again.

**Run:**

```
mkdir -p "$WT_TMP/proj/.specify" && rm -f "$CODEX_HOME/config.toml" && python3 spex/scripts/spex-codex-progress.py decline --root "$WT_TMP/proj" && jq -c . "$WT_TMP/proj/.specify/spex.json" && python3 spex/scripts/spex-codex-progress.py check --root "$WT_TMP/proj"
```

**What you should see:** The hint line `To show spex progress later, run /statusline and /title in Codex and add "task progress".`, a `spex.json` containing `"codex_progress":"declined"`, then `DECLINED`.

**If you see something else:** `ASK` at the end means the decline was not stored or not read back.

**Result:**

### Step 9 of 9: Clean up (US1)

**Why this step:** Removes the scratch area and the exported variables.

**Run:**

```
rm -rf "$WT_TMP" && unset WT_TMP SHIP_STATE_FILE CODEX_HOME && echo cleaned
```

**What you should see:** `cleaned`.

**If you see something else:** Nothing else is expected.

**Result:**

## Not covered here

- **The live Codex experience** (checklist rendering, `Tasks n/8` in the footer and terminal title during a real ship run, the init question and its escalation prompt): needs an interactive Codex TUI session. Follow quickstart step 5 by hand.
- **The Claude status line staying byte-identical**: covered by golden tests (`make test-statusline`), not visible by eye.

## Coverage

- US1 (current stage in a Codex run): Steps 2, 5, 6.
- US2 (paused/failed state): Steps 3, 4 (pause and resume; fail behaves the same and is covered by `make test-ship-state`).
- US3 (footer and title opt-in): Steps 7, 8 (script level; the live init dialog is not covered).
- US4 (Claude unchanged): Step 6 (command); status line bytes via tests.

## Results
