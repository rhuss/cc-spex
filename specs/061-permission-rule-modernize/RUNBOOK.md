---
runbook_version: 1
feature: 061-permission-rule-modernize
status: passed
mode: light
steps_total: 8
step_results: passed,passed,passed,passed,passed,passed,passed,skipped
drafted_at: fedcede
drafted_fingerprint: 9f13e607829d3a71bed8a883f2bb70d4df3135e95de6d089e31fed14b6fe15be
tested_at: 53b7554
tested_fingerprint: 9f13e607829d3a71bed8a883f2bb70d4df3135e95de6d089e31fed14b6fe15be
updated: 2026-11-03
---

# Try it: Modernize Generated Permission Rules

<!-- runbook-status -->
> **Status:** passed · 8 of 8 steps (7 passed, 1 skipped) · Mode: light · Tested at 53b7554 · 2026-11-03
<!-- /runbook-status -->









## What you're testing

spex used to write `Bash(*)`, `Read(*)`, `Edit(*)` and `Write(*)` for the YOLO permission level, and current Claude Code releases warn about them. The new `spex-permissions.sh` rewrites them to bare tool names on refresh and writes bare names on new inits, without touching anything else in your settings.

The journey: run the automated tests, build a throwaway project with legacy settings, migrate it and inspect the result, confirm a second run changes nothing, confirm a broken file is left alone, apply YOLO to a fresh project, and finally check a real `/spex:init --refresh` in Claude Code.

All commands run from the worktree root (`.claude/worktrees/061-permission-rule-modernize`).

## Test environment

No fixtures. Steps 2 to 7 use a throwaway directory under the self-ignoring scratch folder `specs/061-permission-rule-modernize/.walkthrough/`. Teardown: `rm -rf specs/061-permission-rule-modernize/.walkthrough/demo specs/061-permission-rule-modernize/.walkthrough/fresh`.

## Steps

### Step 1 of 8: Run the automated tests (US1, US2, US3)

**Why this step:** The script's behavior is pinned down by tests. If they pass, the hand checks below are confirming known-good behavior instead of debugging.

**Needs:** `jq` on PATH.

**Run:**

```
make test-permissions
```

**What you should see:** A list of `PASS:` lines ending in a summary with 0 failures, and exit status 0.

**If you see something else:** `FAIL:` lines point at the broken case. `jq: command not found` means jq is missing.

**Result:** passed (agent). ✔ 0 failures → `Results: 300 passed, 0 failed`, exit 0. Output: 355 lines, saved to `.walkthrough/step-1.log`.

### Step 2 of 8: Build a project with legacy settings (US2)

**Why this step:** This recreates what an older spex YOLO init left behind: the four legacy rules, a user rule, a hook from another tool, and a personal settings file.

**Needs:** Step 1.

**Run:**

```
D=specs/061-permission-rule-modernize/.walkthrough/demo; rm -rf "$D"; mkdir -p "$D/.claude" && printf '%s' '{"permissions":{"defaultMode":"bypassPermissions","allow":["Bash(*)","Read(*)","Edit(*)","Write(*)","Skill","Bash(npm test)"]},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo bye"}]}]}}' > "$D/.claude/settings.json" && printf '%s' '{"permissions":{"allow":["Read","Read(*)"]}}' > "$D/.claude/settings.local.json" && ls -a "$D/.claude"
```

**What you should see:** `settings.json` and `settings.local.json` listed.

**If you see something else:** A permission error means the scratch folder is not writable.

**Result:** passed (agent). ✔ both files listed → `settings.json`, `settings.local.json`, exit 0.

### Step 3 of 8: Migrate the legacy rules (US2)

**Why this step:** This is what `/spex:init --refresh` and `--update` now run. Both settings files should be repaired, each with its own report line.

**Needs:** Step 2.

**Run:**

```
sh spex/scripts/spex-permissions.sh migrate --root specs/061-permission-rule-modernize/.walkthrough/demo
```

**What you should see:** Two lines on stderr:
`Migrated: .claude/settings.json permissions: Bash(*) -> Bash, Read(*) -> Read, Edit(*) -> Edit, Write(*) -> Write`
`Migrated: .claude/settings.local.json permissions: Read(*) -> Read`

**If you see something else:** No output means the files were not found (wrong `--root`). A `WARNING:` about user-level settings means the path resolved outside the project.

**Result:** passed (agent). ✔ both `Migrated:` lines, verbatim:
`Migrated: .claude/settings.json permissions: Bash(*) -> Bash, Read(*) -> Read, Edit(*) -> Edit, Write(*) -> Write`
`Migrated: .claude/settings.local.json permissions: Read(*) -> Read`

### Step 4 of 8: Inspect what changed and what did not (US2)

**Why this step:** The fix is only safe if it leaves user rules, `defaultMode` and other tools' hooks alone, and collapses duplicates of the bare names.

**Needs:** Step 3.

**Run:**

```
D=specs/061-permission-rule-modernize/.walkthrough/demo; jq -c '{mode: .permissions.defaultMode, allow: .permissions.allow, hooks: (.hooks | keys)}' "$D/.claude/settings.json"; jq -c .permissions.allow "$D/.claude/settings.local.json"
```

**What you should see:**
`{"mode":"bypassPermissions","allow":["Bash","Read","Edit","Write","Skill","Bash(npm test)"],"hooks":["Stop"]}`
`["Read"]`

**If you see something else:** A sorted list means order was not preserved. A missing `hooks` key means other keys were dropped. Two `Read` entries mean deduplication did not run.

**Result:** passed (agent). ✔ order, `defaultMode` and hooks kept → `{"mode":"bypassPermissions","allow":["Bash","Read","Edit","Write","Skill","Bash(npm test)"],"hooks":["Stop"]}`. ✔ deduplicated → `["Read"]`.

### Step 5 of 8: Run the migration again (US2)

**Why this step:** Refresh runs often. A second run must not rewrite files or print anything.

**Needs:** Step 4.

**Run:**

```
D=specs/061-permission-rule-modernize/.walkthrough/demo; cksum "$D/.claude/settings.json"; sh spex/scripts/spex-permissions.sh migrate --root "$D"; cksum "$D/.claude/settings.json"
```

**What you should see:** Two identical `cksum` lines and nothing in between.

**If you see something else:** Different checksums or a `Migrated:` line mean the migration is not idempotent.

**Result:** passed (agent). ✔ identical checksums → `1450536277 355` both times. ✔ no output from the second migrate.

### Step 6 of 8: A broken settings file is left alone (US3)

**Why this step:** Settings files carry hooks from other tools. A file spex cannot parse must survive untouched, with a warning instead of a crash.

**Needs:** Step 2.

**Run:**

```
D=specs/061-permission-rule-modernize/.walkthrough/demo; printf '{broken' > "$D/.claude/settings.local.json"; sh spex/scripts/spex-permissions.sh migrate --root "$D"; echo "exit=$?"; cat "$D/.claude/settings.local.json"; echo
```

**What you should see:** A `WARNING:` line naming `.claude/settings.local.json` as not valid JSON, `exit=0`, and the content still `{broken`.

**If you see something else:** A non-zero exit or changed content means the guard failed.

**Result:** passed (agent). ✔ `WARNING: .claude/settings.local.json is not valid JSON; permission rules not migrated`. ✔ `exit=0`. ✔ content still `{broken`.

### Step 7 of 8: Apply YOLO to a fresh project (US1)

**Why this step:** New inits now go through `apply` with the bare rule names, so no legacy rule is ever written.

**Needs:** Step 1.

**Run:**

```
F=specs/061-permission-rule-modernize/.walkthrough/fresh; rm -rf "$F"; mkdir -p "$F"; sh spex/scripts/spex-permissions.sh apply --root "$F" --default-mode bypassPermissions Bash Read Edit Write Skill WebFetch WebSearch; jq -c .permissions "$F/.claude/settings.json"
```

**What you should see:** `Default mode set to bypassPermissions in .claude/settings.json` and `Permissions configured in .claude/settings.json (7 rules added)` on stderr, then `{"allow":["Bash","Read","Edit","Write","Skill","WebFetch","WebSearch"],"defaultMode":"bypassPermissions"}` (key order may differ).

**If you see something else:** Any `(*)` form in the list means the caller passed legacy rules. A missing file means `.claude/` was not created.

**Result:** passed (agent). ✔ `Default mode set to bypassPermissions in .claude/settings.json`. ✔ `Permissions configured in .claude/settings.json (7 rules added)`. ✔ `{"defaultMode":"bypassPermissions","allow":["Bash","Read","Edit","Write","Skill","WebFetch","WebSearch"]}`, with no `(*)` forms.

### Step 8 of 8: Check a real refresh in Claude Code (US2)

**Why this step:** The success criterion is that Claude Code itself stops warning. Only a real restart shows that.

**Needs:** A project initialized with an older spex YOLO setup (its `.claude/settings.json` contains `Read(*)`), and this branch's spex plugin installed.

**Do:**

1. In that project, run `/spex:init --refresh` in Claude Code.
2. Look for a `Migrated: .claude/settings.json permissions: ...` line in the refresh report.
3. Restart Claude Code (2.1.317 or later) in the project.

**What you should see:** The refresh report includes the `Migrated:` line, and after the restart there are no `Allow rule "Read(*)"`, `"Edit(*)"` or `"Write(*)"` warnings.

**If you see something else:** No `Migrated:` line means the installed plugin is not this branch. Warnings after restart that name other rules come from rules spex did not write.

**Result:** skipped (user). The installed spex plugin is not this branch yet. A separate manual check in Claude Code (trust prompt in a scratch project with legacy rules) showed no "Allow rule" warnings before or after migration, so this release does not reproduce the warning. The prompt listed `Bash(*)` as `Bash`, which means Claude Code already treats the two as the same.

## Coverage

- US1 (fresh YOLO init writes bare rules): Steps 1 and 7. The interactive init skill and `setup.yml` callers are covered by the automated tests in Step 1, not by hand.
- US2 (refresh repairs existing projects): Steps 2 to 5 and 8.
- US3 (never damage unhandled settings): Steps 1 and 6.

## Results

8 steps: 7 passed, 0 failed, 1 skipped (Step 8, real Claude Code refresh and restart).

`spex-permissions.sh` rewrites the four legacy rules to bare names in both project settings files. It keeps rule order, `defaultMode` and other tools' hooks, and collapses duplicate bare names. A second run is byte-identical and silent. A broken file is left alone with a warning and exit 0. A fresh YOLO apply writes only bare names. Not shown by hand: the end-to-end `/spex:init --refresh` inside Claude Code, and the warnings actually disappearing after a restart.
