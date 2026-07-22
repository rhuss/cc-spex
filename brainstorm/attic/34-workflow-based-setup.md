# Brainstorm: Workflow-Based Setup (Harness-Agnostic Spex 6.0)

**Date:** 2026-07-07
**Status:** active
**Related:** [#28 Harness-Agnostic Spex](28-harness-agnostic-spex.md), [#33 Extension-Local Scripts](33-extension-local-scripts.md)
**Upstream:** [spec-kit#3359](https://github.com/github/spec-kit/issues/3359) (on_install hook, redirected to workflows)

## Problem Framing

Spex's init and setup logic lives in a 400-line bash script (`spex-init.sh`) that centralizes per-extension, per-harness adaptation. Every new extension or harness means more branches in this script. The spec-kit maintainer's feedback on #3359 points to an existing solution: the spec-kit **workflow engine** can express all of this as declarative YAML with `switch` on the detected integration, shipped as part of a **bundle**.

The question is whether the workflow engine can actually replicate what `spex-init.sh` does today, especially the interactive parts (extension selection, permission configuration) and the per-agent adapter setup.

## What spex-init.sh Does Today

| Function | What it does | Workflow equivalent? |
|----------|-------------|---------------------|
| `check_version` | Verify `specify` CLI >= 0.5.0 | `shell` step |
| `check_update` | Check GitHub for newer spex versions | `shell` step |
| `check_ready` | Fast-path: is everything already initialized? | `if` step |
| `do_init` | Run `specify init`, install extensions | `init` + `shell` steps |
| `install_extensions` | Loop `specify extension add` for 7 extensions in dependency order | `shell` steps (sequential) |
| `install_agent_adapter` | Detect agent, install hooks/configs for Claude/Codex/OpenCode | `switch` on `inputs.integration` |
| `configure_statusline` | Set up `.claude/settings.local.json` statusline | `shell` step (Claude branch) |
| `configure_gitignore` | Add spex patterns to `.gitignore` | `shell` step |
| `fix_constitution` | Migrate legacy constitution paths | `shell` step |
| `migrate_old_commands` | Remove pre-skills-format command files | `shell` step |
| **Interactive extension selection** | AskUserQuestion in init skill (not in bash) | `prompt` or `gate` step (?) |
| **Permission configuration** | Write to `.claude/settings.json` | `shell` step per agent |

## Approaches Considered

### A: Full Workflow Replacement (chosen)

Replace `spex-init.sh` entirely with a `setup.yml` workflow. Ship as a spec-kit bundle.

- Pros: Single distribution model for all harnesses. Declarative, reviewable YAML. Clean install/uninstall via bundle provenance. `switch` on integration replaces bash `case` cascades. Ships with extensions and presets. One-command install via `specify workflow run <url>`.
- Cons: Interactive UX for extension selection is uncertain (workflow `prompt` steps send text to the AI agent, but structured multi-select depends on what the agent supports). Permission setup requires per-agent `switch` branches. The fast-path check (`check_ready`) needs a way to skip the full workflow if already initialized.

### B: Hybrid (Workflow for Setup, Bash for Interactive)

Use the workflow for non-interactive setup (extension install, adapter config, gitignore). Keep a thin bash or skill-based layer for interactive extension selection and permission prompts.

- Pros: Interactive UX stays agent-native (AskUserQuestion on Claude, equivalent on others). Workflow handles the mechanical parts well.
- Cons: Two systems to maintain. The boundary between "workflow handles this" and "skill handles this" is another integration point.

### C: Keep spex-init.sh, Add Workflow as Alternative

Keep `spex-init.sh` for Claude Code users. Add a workflow as an alternative install path for other harnesses.

- Pros: Zero risk for existing users. Other harnesses get a native path.
- Cons: Doubles maintenance. The whole point is to reduce maintenance.

## Decision

**Approach A: Full workflow replacement.** The interactive UX concern is real but solvable: the workflow `prompt` step asks the AI agent to present choices, and each agent uses its native mechanism (AskUserQuestion on Claude, equivalent elsewhere). If structured multi-select isn't available on a given agent, the prompt degrades gracefully to text-based selection.

## Key Feasibility Questions

These must be validated before committing to implementation:

### 1. Interactive Extension Selection via Workflow

**Current behavior:** The init skill uses `AskUserQuestion` with multi-select to let users pick extensions.

**Workflow approach:** A `prompt` step sends a prompt to the AI agent asking it to present extension choices to the user. The agent uses whatever native mechanism it has.

**Risk:** The workflow engine may not support passing structured output from a `prompt` step back into subsequent `if`/`switch` steps. If the prompt just sends text and the agent responds with text, parsing the response is fragile.

**Mitigation:** Use `inputs.extensions` with a default of `"all"`. Users who want interactive selection run the workflow with `--set extensions=interactive`, which triggers the prompt step. Most users accept the default (all extensions enabled). After the workflow runs, users can `specify extension disable <ext>` for anything they don't want.

**Alternative mitigation:** Use `gate` steps (one per optional extension). Each gate pauses for approve/reject. Less elegant than multi-select but deterministic and agent-agnostic.

### 2. Per-Agent Permission Configuration

**Current behavior:** The init skill writes to `.claude/settings.json` with specific permission allowlists.

**Workflow approach:** A `switch` on `inputs.integration` runs the right `shell` step:
```yaml
- id: permissions
  type: switch
  expression: "{{ inputs.integration }}"
  cases:
    claude:
      - type: shell
        run: |
          # Write Claude Code permissions
    codex:
      - type: shell
        run: |
          # Write Codex permissions
  default:
    - type: shell
      run: echo "No agent-specific permissions configured"
```

**Risk:** Low. Shell steps can write any file. This is straightforward.

### 3. Fast-Path (Already Initialized)

**Current behavior:** `spex-init.sh` exits immediately with `READY` if everything is already set up.

**Workflow approach:** An `if` step at the top checks for initialization markers:
```yaml
- id: check-ready
  type: if
  condition: "{{ steps.check.output.ready == 'true' }}"
  then:
    - type: shell
      run: echo "READY"
  else:
    # ... full init sequence
```

**Risk:** Low. The `shell` step can run the same checks as bash.

### 4. Subagent Dispatch in Commands (Ship, Teams, Deep-Review)

**Current behavior:** Commands use the `Agent` tool (Claude Code-specific) to spawn subagents for context isolation.

**Workflow approach:** This is NOT about the setup workflow. This is about the command content itself. The ship pipeline, teams implementation, and deep-review all embed `Agent` tool instructions. For harness-agnostic operation, these need neutral vocabulary + per-agent presets.

**Risk:** High. This is the hardest CC coupling. A simple preset `replace` won't work for the Agent tool's complex dispatch patterns (schema validation, worktree isolation, model selection). This is a Phase 2 concern (after the setup workflow migration), and may require a spec-kit upstream feature (`post_process_command_content()` from brainstorm #28).

**Decision:** Defer command neutralization to a separate brainstorm/spec. The setup workflow migration is valuable independently: it replaces `spex-init.sh` with a harness-agnostic install mechanism, even while the commands themselves remain CC-optimized.

### 5. Bundle Distribution

**What we need to validate:**
- Can `bundle.yml` reference local extensions (relative paths)?
- Does `specify workflow run <url>` download and execute correctly from GitHub releases?
- Does bundle install handle dependency ordering (spex-gates before spex-teams)?
- Can a workflow step run `specify bundle install` or does the bundle install happen before the workflow?

**Risk:** Medium. Bundle support may have rough edges since it's relatively new in spec-kit. Need to prototype.

### 6. Claude Code Plugin Compatibility

**Current behavior:** `claude plugin install spex@spex-plugin-development` installs the plugin from the marketplace.

**Transition plan:** Keep the CC plugin as a thin shim for 5.x. It runs `specify workflow run` under the hood. Eventually deprecate when 6.0 is stable.

**Risk:** Low. The plugin model and the bundle model can coexist. The plugin's `spex-init.sh` can be updated to call the setup workflow.

## Implementation Phases

### Phase 1: Setup Workflow Prototype
- Create `setup.yml` that replicates `spex-init.sh` functionality
- Test with `specify workflow run` locally
- Validate interactive extension selection approach
- Validate per-agent `switch` branches

### Phase 2: Bundle Packaging
- Create `bundle.yml` with all extensions and the setup workflow
- Test bundle install/uninstall
- Validate HTTPS URL distribution from GitHub releases

### Phase 3: Neutral Command Vocabulary (separate brainstorm)
- Rewrite commands to use generic descriptions
- Create Claude Code preset for tool-specific optimizations
- Validate that preset `prepend`/`replace` covers the real command patterns

### Phase 4: Migration and Deprecation
- Update Claude Code plugin to call setup workflow
- Publish migration guide
- Deprecation timeline for direct plugin install

## Open Questions

- Can workflow `prompt` step output be used in subsequent `if`/`switch` conditions, or is it fire-and-forget?
- Does `specify bundle install` handle extension dependency ordering, or must the workflow enforce it?
- What is the minimum spec-kit version required for workflow + bundle support?
- Should the setup workflow be idempotent (safe to re-run) or require `--force` for re-initialization?
