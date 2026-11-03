---
name: init
description: Initialize or update the project using the `specify` CLI (--refresh for templates, --update to upgrade CLI, --clear to reset status line). Do NOT search for speckit or spec-kit binaries.
---

You MUST complete ALL steps below. Do not stop after Step 1.

## Step 1: Run init script

Run the command from `<spex-init-command>` in the `<spex-context>` system reminder. This is your first and only Bash call. Do not run anything else before it.

- Remember the `DECLARATION_EXISTED=true` or `DECLARATION_EXISTED=false` line from the output (printed when the command runs without flags). Step 2 needs it.
- If output contains `NEED_INSTALL`: show output, STOP.
- If output contains `ERROR` or the script exits with a non-zero status other than `3` (`3` means `RESTART_REQUIRED`): show the error, STOP. Do not continue to Step 2, Step 3 or the restart advice.
  - In particular, init exits with status `1` and `ERROR: spex-worktrees requires the spec-kit git extension` when `spex-worktrees` is enabled but the `git` extension cannot be enabled. Show the message with its two fixes: add the git extension (`specify extension add git` / `specify extension enable git`) and run `/spex:init` again, or re-run setup with an extension selection that leaves out `spex-worktrees` (the message shows the `specify workflow run ... -i extensions=...` command). Do not tell the user to disable `spex-worktrees` by hand.
- If the command was run with `--refresh` or `--update` and output contains `RESTART_REQUIRED`: **SKIP Steps 2 and 3.** Templates and extensions were refreshed. When the project has a declaration (`.specify/spex.json`), the refresh re-applied its extension selection exactly (extensions toggled by hand are reset, and the output names every change); without a declaration, the enabled/disabled state of the installed extensions is preserved. No permission rules are added, but the refresh rewrites the legacy `Bash(*)`, `Read(*)`, `Edit(*)` and `Write(*)` rules that earlier spex versions wrote to the bare tool names (`Bash`, `Read`, `Edit`, `Write`, same meaning) in `.claude/settings.json` and `.claude/settings.local.json`, and prints one `Migrated: ...` line per changed file. Go directly to Step 4 and report that the refresh completed, including any `Enabled:`, `Disabled:`, `Migrated:` or `WARNING:` lines from the output. Tell the user to restart Claude Code.
- If output contains `READY` or `RESTART_REQUIRED`: **do not summarize yet**, go to Step 2.

## Step 2: Ask about extensions and permissions

You MUST ask all 3 questions below in a SINGLE AskUserQuestion call. Do NOT split, merge, reword, or reorder them. Pass them exactly as specified:

1. (`multiSelect: true`, header: "Quality"): "Which quality & review extensions do you want to enable?"
   - "spex-gates": "Quality gates on speckit commands (review-spec, review-code, verification)"
   - "spex-deep-review": "Multi-perspective code review with autonomous fix loop (5 agents)"
   - "spex-teams": "Parallel implementation with spec guardian review via Agent Teams (experimental, requires: spex-gates)"

2. (`multiSelect: true`, header: "Workflow"): "Which workflow extensions do you want to enable?"
   - "spex-worktrees": "Git worktree isolation: speckit-specify creates the worktree (in .claude/worktrees/) before the feature branch, so the main checkout never switches (requires the git extension)"
   - "spex-collab": "Phase-split collaboration with REVIEWERS.md for team PRs"
   - "spex-detach": "Strip spec artifacts at PR time for contributing to repos that don't use SDD"

3. (`multiSelect: false`, header: "Permissions"): "How should spex commands handle permission prompts?"
   - "Standard (Recommended)": "Auto-approve spex plugin scripts (spex-init.sh, specify CLI)"
   - "YOLO": "Auto-approve everything, bypass all permission prompts for unattended workflows"
   - "None": "Confirm every spex command before execution"

Then apply the selections:

**Dependency resolution**: `spex-deep-review`, `spex-teams` and `spex-collab` require `spex-gates`. If the user selected any of them but NOT `spex-gates`, `spex-gates` is enabled automatically. Warn:
> **Note:** spex-gates was auto-enabled because <extension> depends on it.

**Extensions**: The selection is exact: the selected extensions (plus `spex-gates` when required) are enabled, and every other optional extension is disabled. Do not run `specify extension enable` or `specify extension disable` yourself. Resolve, apply and persist the selection with the spex scripts, in this order. `<scripts>` is the directory that contains the `spex-init.sh` from `<spex-init-command>` (use its absolute path). `<csv>` is the comma-separated list of the selected extensions (empty when none was selected), and `<permissions>` is `none`, `standard` or `yolo` for the permission choice below:

```bash
set -e
RESOLVED=$(python3 "<scripts>/spex-setup-profile.py" resolve --root "$PWD" \
  --extensions "spex,<csv>" --legacy-permissions <permissions> [--harness claude])
SELECTED=$(printf '%s' "$RESOLVED" | jq -r '.extensions | join(",")')
sh "<scripts>/spex-apply-extensions.sh" "$SELECTED"
case ",$SELECTED," in
  *,spex-worktrees,*)
    jq -e '.extensions.git.enabled == true' .specify/extensions/.registry >/dev/null 2>&1 ||
      specify extension enable git >/dev/null 2>&1 || specify extension add git >/dev/null 2>&1 || true
    jq -e '.extensions.git.enabled == true' .specify/extensions/.registry >/dev/null 2>&1 || {
      echo "ERROR: spex-worktrees requires the spec-kit git extension" >&2
      echo "Fix it with one of: specify extension add git, then run /spex:init again;" >&2
      echo "or run /spex:init again with a selection that leaves out spex-worktrees." >&2
      exit 1
    } ;;
esac
printf '%s' "$RESOLVED" | python3 "<scripts>/spex-setup-profile.py" persist --root "$PWD"
```

Run the block as one Bash call so `set -e` stops it before `persist` when a step fails.

- Pass `--harness claude` only when Step 1 printed `DECLARATION_EXISTED=false`. When it printed `DECLARATION_EXISTED=true`, leave the stored harness as it is.
- Always start `--extensions` with `spex`, so choosing no optional extension yields only `spex`.
- `--legacy-permissions` maps None to `safe`, Standard to `autonomous` and YOLO to `yolo` in `.specify/spex.json`.
- If the block fails, the declaration is not written. Show the error and STOP. For `ERROR: spex-worktrees requires the spec-kit git extension`, offer the two fixes from Step 1: add the git extension and run `/spex:init` again, or choose again without `spex-worktrees`. Otherwise report the `Enabled:` / `Disabled:` lines in Step 4.

**Permissions**: The `specify` CLI does not manage permissions. All Claude permission writes go through `spex-permissions.sh` in the same `<scripts>` directory. Do not edit `.claude/settings.json` yourself, and do not merge rules with your own `jq` calls. Run the block for the user's choice as one Bash call, copying the rule arguments verbatim (do not modify or rephrase the permission strings):

- **Standard**:
  ```bash
  sh "<scripts>/spex-permissions.sh" apply \
    Skill 'Bash(specify *)' 'Bash(*spex-init.sh*)' 'Bash(*spex-ship-statusline.sh*)'
  sh "<scripts>/spex-permissions.sh" migrate
  ```
- **YOLO**:
  ```bash
  sh "<scripts>/spex-permissions.sh" apply --default-mode bypassPermissions \
    Bash Read Edit Write WebFetch WebSearch Skill \
    'Bash(specify *)' 'Bash(*spex-init.sh*)' 'Bash(*spex-ship-statusline.sh*)'
  sh "<scripts>/spex-permissions.sh" migrate
  ```
  Note: `defaultMode: "bypassPermissions"` skips all permission prompts. The broad `allow` rules serve as additional fallback. Use this for unattended ship pipelines or when you trust the agent fully. The bare tool names `Bash`, `Read`, `Edit` and `Write` allow the tool for every command and every path, including sibling worktrees outside the working directory. Never write `Bash(*)`, `Read(*)`, `Edit(*)` or `Write(*)` instead: current Claude Code releases flag these forms, and `Read(*)`, `Edit(*)` and `Write(*)` only cover the working directories there.
- **None**: Do not add permission rules. Still run the migration, so legacy rules from an earlier spex version are repaired:
  ```bash
  sh "<scripts>/spex-permissions.sh" migrate
  ```

`apply` appends the missing rules to the project's `.claude/settings.json` (created when missing) without re-sorting the existing list, and leaves every other setting alone. `migrate` rewrites the legacy `Bash(*)`, `Read(*)`, `Edit(*)` and `Write(*)` rules to the bare names in `.claude/settings.json` and `.claude/settings.local.json`. Both print their results on stderr: `Permissions configured in .claude/settings.json (<n> rules added)`, `Default mode set to bypassPermissions in .claude/settings.json` when YOLO changed the default mode, one `Migrated: ...` line per repaired file, and `WARNING: ...` lines for files they left alone (including a project settings path that resolves to the user-level `~/.claude` settings, which spex never changes). Keep these lines for Step 4.

## Step 3: Detect companion plugins and seed memory

Scan the available skills list from the system reminder for companion plugins:

### 3a: Superpowers plugin

Check for any of these upstream superpowers skills: `test-driven-development`, `systematic-debugging`, `brainstorming`, `writing-plans`. These are skills from [obra/superpowers](https://github.com/obra/superpowers) that complement spex but are NOT bundled with it.

- If **found**: record "superpowers" as a detected companion plugin in the Step 4 report. No further action needed.
- If **not found** and the user enabled the `spex-gates` extension in Step 2: show a recommendation in the Step 4 report (see below). Do NOT block init or make it an error.

## Step 4: Report

Summarize: extensions enabled, permission level, and companion plugins detected. Relay every `Migrated:` and `WARNING:` line from the Step 1 and Step 2 output verbatim (for a full init as well as for `--refresh` and `--update`), so the user sees which permission rules were rewritten and which settings files were left alone. Tell the user to restart Claude Code if Step 1 said RESTART_REQUIRED, if a `Permissions configured in ... (<n> rules added)` line has n greater than 0, if a `Default mode set to ...` line appeared, or if any `Migrated:` line appeared.

If superpowers companion plugin was NOT detected (Step 3b), append this to the report:

> **Recommended companion:** The [Superpowers](https://github.com/obra/superpowers) plugin by Jesse Vincent adds TDD discipline and systematic debugging skills that complement spex's spec-first workflow. spex absorbs superpowers' quality gates and anti-rationalization patterns, but does not bundle these standalone skills:
> - **test-driven-development**: strict RED-GREEN-REFACTOR, no production code without failing test
> - **systematic-debugging**: 4-phase root cause analysis with defense-in-depth
>
> Install with: `/plugin install superpowers@claude-plugins-official` (or `claude plugin install superpowers@claude-plugins-official` from the terminal)
