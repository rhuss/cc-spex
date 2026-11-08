# Quickstart: Validate Ship Progress in Codex

Run from the repository root of the feature branch.

## 1. Automated tests

```bash
make test-statusline        # Claude status line unchanged + --banner mode
make test-ship-state        # progress subcommand (banner + plan)
make test-adapt             # ship-progress marker per harness
make test-codex-progress    # Codex config editing
make test-setup-profile     # codex_progress field kept across resolve/persist
```

All must pass.

## 2. Banner and plan by hand

```bash
tmp=$(mktemp -d)
export SHIP_STATE_FILE="$tmp/.spex-state"
spex/scripts/spex-ship-state.sh create brainstorm/51-codex-ship-progress.md --start-from implement
spex/scripts/spex-ship-state.sh progress
# BANNER 🧬 ship 🔨 implement ▓▓▓▓▓▓▓░░ 7/8 🧠
# PLAN [... six "completed", implement "in_progress", review-code "pending"]
spex/scripts/spex-ship-state.sh pause && spex/scripts/spex-ship-state.sh progress   # "⏸ paused", "implement (paused)"
spex/scripts/spex-ship-state.sh resume && spex/scripts/spex-ship-state.sh progress
rm "$SHIP_STATE_FILE"; spex/scripts/spex-ship-state.sh progress                     # no output
```

`advance` verifies stage artifacts, so test the done form with a fixture state (`"stage": "done", "stage_index": 8, "status": "completed"`): expect `BANNER 🧬 ship ✅ done ▓▓▓▓▓▓▓▓ 8/8` and eight `completed` steps.

## 3. Adapter regression check (SC-003)

```bash
git worktree add /tmp/spex-main main
for h in claude codex opencode; do
  for side in /tmp/spex-main .; do
    out="/tmp/adapt-$h-$(basename "$side")"; rm -rf "$out"; cp -R "$side/spex/extensions" "$out"
    "$side/spex/scripts/spex-adapt-commands.sh" "$h" "$out" "$side/spex/scripts/adapters" >/dev/null
  done
  diff -r "/tmp/adapt-$h-spex-main" "/tmp/adapt-$h-." | head
done
git worktree remove /tmp/spex-main
```

Expected: no differences for `claude`; for `codex` and `opencode` only `spex/commands/speckit.spex.ship.md` differs (the progress subsection).

## 4. Codex config editing on a copy

```bash
export CODEX_HOME=$(mktemp -d)
printf '# my settings\n[tui]\nstatus_line = ["model-with-reasoning", "git-branch"]\n' > "$CODEX_HOME/config.toml"
python3 spex/scripts/spex-codex-progress.py check --root "$PWD"    # ASK
python3 spex/scripts/spex-codex-progress.py apply                  # APPLIED path=...
cat "$CODEX_HOME/config.toml"   # comment kept, git-branch kept, task-progress appended, terminal_title = defaults + task-progress
python3 spex/scripts/spex-codex-progress.py check --root "$PWD"    # CONFIGURED
```

## 5. Live Codex run (manual)

1. In a scratch project: `$cc-spex-init`, answer "yes" to the progress question, approve the write, restart Codex.
2. Run `$speckit-spex-ship <brainstorm>`.
3. Expect: a banner line and an updated checklist after each stage change; footer and terminal title show `Tasks n/8` matching the banner.
4. In another scratch project answer "no": `.specify/spex.json` contains `"codex_progress": "declined"`, and a second `$cc-spex-init` does not ask.

## Results

### 2026-10-26: Adapter regression check (step 3, T014)

Adapted `spex/extensions` from `main` (via `git archive main spex`) and from the branch, each with its own `spex-adapt-commands.sh` and adapter maps, for `claude`, `codex` and `opencode`, then compared the trees with `diff -rq`.

- `claude`: no difference in any `*/commands/*.md` file (SC-003 holds). The only differing files are the synced script copies `spex/scripts/spex-ship-state.py` and `spex/scripts/spex-ship-statusline.sh`, which the adapter does not touch.
- `codex` and `opencode`: among the commands, only `spex/commands/speckit.spex.ship.md` differs (the added progress subsection). The same two synced script copies differ as for `claude`.

### 2026-10-26: Claude init paths (T015)

`rg -n 'codex-progress|codex_progress' spex/scripts/spex-init.sh spex/skills/init spex/setup.yml spex/extensions` finds no match: Claude-side init (`spex-init.sh`, `/spex:init`) and the setup workflow never call `spex-codex-progress.py` or `codex-progress.sh` (FR-019). Only the Codex skill `spex/codex/skills/cc-spex-init` uses them.

### 2026-10-26: Banner and plan by hand (step 2, T028)

Ran step 2 against a temp `SHIP_STATE_FILE`. Outcome matched every expectation:

- `create --start-from implement` then `progress`: `BANNER 🧬 ship 🔨 implement ▓▓▓▓▓▓▓░░ 7/8 🧠`, plan with six `completed`, `implement` `in_progress`, `review-code` `pending`.
- `pause` then `progress`: banner ends in `⏸ paused`, step label `implement (paused)`.
- `resume` then `progress`: suffixes gone in banner and plan.
- After `rm` of the state file: no output, exit 0.
- Done fixture (`stage: done, stage_index: 8, status: completed`): `BANNER 🧬 ship ✅ done ▓▓▓▓▓▓▓▓ 8/8` and eight `completed` steps.

### 2026-10-26: Codex config editing on a copy (step 4, T028)

Ran step 4 with a temp `CODEX_HOME`. `check` printed `ASK`, `apply` printed `APPLIED path=$CODEX_HOME/config.toml`, and the file kept `# my settings`, kept `git-branch`, appended `task-progress` to `status_line` and added `terminal_title = ["activity", "thread-name", "project-name", "task-progress"]`. A second `check` printed `CONFIGURED`.

### Live Codex run (step 5, SC-001/SC-002): skipped: manual

Not run: it needs an interactive Codex TUI session (answering the init question, approving the escalated write, restarting Codex, watching the footer and terminal title during a full ship run), which cannot be driven non-interactively from this session. Run it by hand:

1. In a scratch project: `$cc-spex-init`, answer "yes" to the progress question, approve the write, restart Codex.
2. Run `$speckit-spex-ship <brainstorm>`.
3. Expect: a banner line and an updated checklist after each stage change; footer and terminal title show `Tasks n/8` matching the banner.
4. In another scratch project answer "no": `.specify/spex.json` contains `"codex_progress": "declined"`, and a second `$cc-spex-init` does not ask.
