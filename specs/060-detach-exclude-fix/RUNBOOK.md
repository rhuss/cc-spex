---
runbook_version: 1
feature: 060-detach-exclude-fix
status: passed
mode: light
steps_total: 7
step_results: passed,passed,passed,passed,passed,passed,passed
drafted_at: 234644f
drafted_fingerprint: 7e0a2895e5f105d99c2ec31f7183d003e81370f418711082a3e604316de8d258
tested_at: 91b7fb4
tested_fingerprint: 286415b2dc7d2d3592f20f1d0be01bd465fcfd49091fc3691510c3e6c7e22f25
updated: 2026-11-03
---

# Try it: Detach stealth-mode exclude gap and config loss on refresh

<!-- runbook-status -->
> **Status:** passed · 7 of 7 steps (7 passed) · Mode: light · Tested at 91b7fb4 · 2026-11-03
<!-- /runbook-status -->








## What you're testing

Selecting spex-detach in setup now really hides spec artifacts from git and checks that it did. A refresh keeps your detach configuration and repairs exclude entries that went missing. Projects without detach see no change.

The journey: create a throwaway repository, run setup with spex-detach, confirm git ignores the spec paths, run the standalone check, customize the config and refresh, delete an entry and refresh again, then run setup in a second repository without detach.

## Test environment

No fixtures. Every step works in two throwaway repositories under `${TMPDIR:-/tmp}`: `spex-detach-try` and `spex-detach-try-plain`. Run all steps in one terminal session, because step 1 exports `SPEX_REPO` and `TRY` for the later steps.

Teardown: `rm -rf "${TMPDIR:-/tmp}/spex-detach-try" "${TMPDIR:-/tmp}/spex-detach-try-plain"`

The `git check-ignore` commands pass `-c core.excludesFile=/dev/null`, so your global git ignore file cannot make a path look ignored for the wrong reason.

## Steps

### Step 1 of 7: Create a throwaway repository (US1)

**Why this step:** Setup runs against a fresh git repository, the same way it would in a new fork, so nothing in your real projects changes.

**Needs:** A terminal in the cc-spex checkout that contains this feature (the feature branch worktree, or `main` after the merge). The `specify`, `jq` and `yq` CLIs on PATH.

**Run:**

```
export SPEX_REPO="$(git rev-parse --show-toplevel)" && export TRY="${TMPDIR:-/tmp}/spex-detach-try" && rm -rf "$TRY" && mkdir -p "$TRY" && git -C "$TRY" init -q && echo "SPEX_REPO=$SPEX_REPO" && echo "TRY=$TRY"
```

**What you should see:** Two lines. `SPEX_REPO=` shows the cc-spex checkout path, and `TRY=` shows a path ending in `spex-detach-try`.

**If you see something else:** `fatal: not a git repository` means you are not inside the cc-spex checkout. `cd` there and run it again.

**Result:** passed (agent). `SPEX_REPO=/Users/rhuss/Development/context-engineering/cc-spex/.claude/worktrees/060-detach-exclude-fix` and `TRY=/var/folders/3v/16m6pn090hl4d60grm1057ww0000gn/T//spex-detach-try`.

### Step 2 of 7: Run setup with spex-detach selected (US1)

**Why this step:** This is the path that used to enable spex-detach without writing a single exclude entry. Setup should now write the entries and verify them.

**Needs:** Step 1.

**Run:**

```
cd "$TRY" && SPEX_SOURCE="$SPEX_REPO/spex" specify workflow run "$SPEX_REPO/spex/setup.yml" -i integration=claude -i extensions=spex-detach -i security=safe >/dev/null && sh "$SPEX_REPO/spex/scripts/spex-setup-report.sh"
```

**What you should see:** The report includes `Enabled: spex-detach`, then `Stealth mode: exclude entries written: .specify/ specs/ brainstorm/`, then `Stealth mode: active (verified: .specify/ specs/ brainstorm/)`.

**If you see something else:** `Enabled: spex-detach` with no `Stealth mode` lines means the old gap is still there. A `WARNING: stealth mode is NOT fully active` line names the path that is still visible. A workflow error before the report means setup itself failed. Run the same command without `>/dev/null` to see why.

**Result:** passed (agent). Expected vs actual: `Enabled: spex-detach` seen; `Stealth mode: exclude entries written: .specify/ specs/ brainstorm/` seen; `Stealth mode: active (verified: .specify/ specs/ brainstorm/)` seen. The report also listed `Disabled:` lines for the other extensions (fresh installs start enabled; existing behavior).

### Step 3 of 7: Confirm git ignores every spec artifact (US1)

**Why this step:** The setup message is only a claim. Here git itself confirms that a spec file, the project declaration, the constitution and a brainstorm document are all hidden, and shows which rule hides each one.

**Needs:** Step 2.

**Run:**

```
cd "$TRY" && mkdir -p specs/001-x brainstorm && touch specs/001-x/spec.md brainstorm/01-idea.md && git -c core.excludesFile=/dev/null check-ignore -v specs/001-x/spec.md .specify/spex.json .specify/memory/constitution.md brainstorm/01-idea.md
```

**What you should see:** Four lines, one per path. Each starts with `.git/info/exclude:` plus a line number and a pattern. `specs/` covers the spec file, `.specify/` covers `spex.json` and the constitution, and `brainstorm/` covers the idea file.

**If you see something else:** Fewer than four lines means git does not ignore a path, so it would leak with `git add -A`. A line pointing at a `!**/.specify/...` pattern means spex's own re-include rule won.

**Result:** passed (agent). Output:

```
.git/info/exclude:12:specs/	specs/001-x/spec.md
.git/info/exclude:11:.specify/	.specify/spex.json
.git/info/exclude:11:.specify/	.specify/memory/constitution.md
.git/info/exclude:13:brainstorm/	brainstorm/01-idea.md
```

### Step 4 of 7: Run the standalone stealth check (US1)

**Why this step:** You can re-check stealth mode at any time without changing anything, for example before opening an upstream PR.

**Needs:** Step 2.

**Run:**

```
cd "$TRY" && .specify/extensions/spex-detach/scripts/spex-detach.sh verify | jq -c '{active, visible}'
```

**What you should see:** `Stealth mode: active (verified: .specify/ specs/ brainstorm/)` on stderr, followed by `{"active":true,"visible":[]}`.

**If you see something else:** `"active":false` lists each visible entry and its reason (`not-ignored` or `tracked`). A `jq` parse error means the subcommand printed no JSON. Run it without the pipe to see the raw output.

**Result:** passed (agent). Output: `Stealth mode: active (verified: .specify/ specs/ brainstorm/)` and `{"active":true,"visible":[]}`.

### Step 5 of 7: Customize the detach config and refresh (US2)

**Why this step:** A refresh used to reset the detach config to the template, which silently dropped your archive path. The file should now come through byte-identical.

**Needs:** Step 2.

**Run:**

```
cd "$TRY" && C=.specify/extensions/spex-detach/spex-detach-config.yml && yq -i '.archive.path = "/tmp/spex-detach-try-specs" | .archive.auto_commit = false' "$C" && shasum "$C" && SPEX_SOURCE="$SPEX_REPO/spex" specify workflow run "$SPEX_REPO/spex/setup.yml" >/dev/null && shasum "$C" && yq '.archive' "$C"
```

**What you should see:** Two `shasum` lines with the same hash, then the archive block showing `path: /tmp/spex-detach-try-specs` and `auto_commit: false`.

**If you see something else:** Two different hashes, or `path: ""` with `auto_commit: true`, mean the refresh replaced the config with the template. An `ERROR: cannot save` line means setup stopped on purpose, because it could not back up the config.

**Result:** passed (agent). Both hashes `e1d6bcc9f97d488827a2654034101c3f9feb06af`; archive block `path: "/tmp/spex-detach-try-specs"`, `auto_commit: false`, template comments kept.

### Step 6 of 7: Delete an exclude entry and let refresh repair it (US3)

**Why this step:** Projects set up before this fix may be missing some entries. The next refresh should put them back, say that it repaired them, and never add a duplicate.

**Needs:** Step 2.

**Run:**

```
cd "$TRY" && X="$(git rev-parse --git-common-dir)/info/exclude" && sed -i.bak '/^specs\/$/d' "$X" && rm -f "$X.bak" && SPEX_SOURCE="$SPEX_REPO/spex" specify workflow run "$SPEX_REPO/spex/setup.yml" >/dev/null && sh "$SPEX_REPO/spex/scripts/spex-setup-report.sh" && grep -c '^specs/$' "$X"
```

**What you should see:** The report includes `Repaired stealth mode: added specs/` and `Stealth mode: active (verified: .specify/ specs/ brainstorm/)`. The last line is `1`.

**If you see something else:** `Stealth mode: exclude entries written: specs/` means the entry came back but was not recognized as a repair. `2` or more on the last line means a duplicate entry. No `Stealth mode` lines at all means refresh skipped the repair.

**Result:** passed (agent). Output: `Repaired stealth mode: added specs/`, `Stealth mode: active (verified: .specify/ specs/ brainstorm/)`, `Extensions: 0 enabled, 0 disabled, 6 unchanged`, last line `1`.

### Step 7 of 7: Run setup without spex-detach (US4)

**Why this step:** Most projects don't use detach. For them, setup must print nothing new and write no detach entries.

**Needs:** Step 1 (for `SPEX_REPO` and `TRY`).

**Run:**

```
rm -rf "$TRY-plain" && mkdir -p "$TRY-plain" && git -C "$TRY-plain" init -q && cd "$TRY-plain" && SPEX_SOURCE="$SPEX_REPO/spex" specify workflow run "$SPEX_REPO/spex/setup.yml" -i integration=claude -i extensions=spex-gates -i security=safe >/dev/null && sh "$SPEX_REPO/spex/scripts/spex-setup-report.sh"; grep -c 'spex-detach' .git/info/exclude
```

**What you should see:** The report shows the extension summary (`Extensions: ...`), with no `Stealth mode` or `Repaired` line. The last line is `0`.

**If you see something else:** A `Stealth mode` line, or a count above `0`, means detach logic ran in a project that did not select it.

**Result:** passed (agent), with a runbook correction. No `Stealth mode` or `Repaired` line; last line `0` (exit code 1 comes from `grep -c` finding nothing). Correction: the draft expected `Enabled: spex-gates`, but on a fresh install every added extension starts enabled, so the report showed `Extensions: 0 enabled, 4 disabled, 2 unchanged`. The expectation above was fixed; the feature behaved correctly.

## Not covered here

- The case where saving the config fails. Making that happen needs a deliberately broken file system state. The automated tests cover it (`make test-detach`, `make test-workflow-setup`).
- The Claude Code `/spex:init` dialog itself. The steps call the same setup workflow and selection script that `/spex:init` and Codex setup use, but they don't go through the interactive questions.

## Coverage

- US1 (setup hides spec artifacts): steps 2, 3, 4.
- US2 (refresh keeps the config): step 5.
- US3 (refresh repairs missing entries): step 6.
- US4 (no change without detach): step 7.

## Results

7 steps: 7 passed, 0 failed, 0 skipped (all run by the agent on 2026-11-03).

Selecting spex-detach in setup now writes the exclude entries and confirms them with git, including the project declaration and the constitution that spex's own rules would otherwise re-include. The standalone `verify` check reports the same result without changing anything. A refresh keeps a customized detach configuration byte-identical, repairs a deleted exclude entry with a `Repaired stealth mode` message and no duplicate, and a project without spex-detach sees no stealth-mode output and no detach entries. One expectation in step 7 was wrong in the draft and was corrected.
