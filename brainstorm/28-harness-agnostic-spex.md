# Brainstorm: Harness-Agnostic Spex

**Date:** 2026-07-02
**Status:** active
**Upstream:** [spec-kit#3303](https://github.com/github/spec-kit/issues/3303) + [spec-kit brainstorm/01](https://github.com/rhuss/spec-kit/blob/main/brainstorm/01-extension-capability-system.md)

## Problem Framing

Spec-kit (`specify` CLI) already supports 28 agent harnesses through a clean integration architecture: each agent is a Python subclass with format/path/structure config, and a `CommandRegistrar` converts extension command markdown to the right format for each agent. The abstraction works well at the infrastructure level.

The spex extensions, however, are deeply tied to Claude Code. An audit of all extension commands found 46 Claude Code-specific references across 41 CORE dependencies and 5 suggestions. These fall into a few patterns:

- **`find ~/.claude` for script discovery** (14 instances, 30% of all refs) - relies on Claude Code's plugin install directory
- **Tool name references** (`AskUserQuestion`, `Agent`, `EnterWorktree`) in command instructions
- **`settings.json` / `settings.local.json`** for permissions and feature flags
- **Hook protocol** (`UserPromptSubmit`, `PreToolUse`) for process enforcement
- **Status line** integration
- **`/clear`** command for context management

Spec-kit's `CommandRegistrar` handles format and path differences but does NOT transform command content. That's where the Claude Code-specific instructions live. The result: spex only works on Claude Code despite spec-kit supporting many harnesses.

## Inventory of CC Dependencies by Extension

| Extension | CC Refs | CORE | SUGGESTION | Agnostic Feasibility |
|-----------|---------|------|------------|----------------------|
| spex/ (core) | 16 | 13 | 3 | Medium (ship is heavily coupled via Agent tool) |
| spex-gates/ | 5 | 5 | 0 | High (only find ~/.claude + AskUserQuestion refs) |
| spex-worktrees/ | 1 | 0 | 1 | Very High (already uses raw git commands) |
| spex-collab/ | 5 | 4 | 1 | High (mostly generic prompting) |
| spex-teams/ | 8 | 8 | 0 | Medium (already has multi-platform dispatch) |
| spex-deep-review/ | 5 | 5 | 0 | Medium (has sequential fallback) |
| spex-detach/ | 1 | 1 | 0 | Very High (only find ~/.claude) |
| init (skill) | 5 | 5 | 0 | Low (deeply CC-coupled: settings, permissions) |

The most pervasive single pattern is `find ~/.claude` (14 instances). The most complex dependency is the Agent tool for subagent spawning in ship, teams, and deep-review.

## Spec-Kit Architecture Analysis

Spec-kit has three relevant abstraction layers:

1. **Integration layer** (`integrations/` package) - 28 agents, each a subclass of `IntegrationBase`, `MarkdownIntegration`, `TomlIntegration`, `YamlIntegration`, or `SkillsIntegration`
2. **CommandRegistrar** (`agents.py`) - writes extension commands to all active agent directories in the correct format
3. **Extension system** (`extensions.py`) - the plugin contract for adding commands and hooks

Key findings from source analysis:

- **`post_process_skill_content()`** exists on `SkillsIntegration` (called during extension install) but only covers skills-format agents (Claude, Codex, Cursor, Kimi, Agy, Trae). OpenCode uses `MarkdownIntegration` and has no equivalent hook.
- **No capability system exists on integrations.** No `capabilities`, `features`, or `supports` attributes. The closest are `_feature_capabilities()` (CLI-level, wrong scope), `_invocation_style.py` (syntax classification, not functional capabilities), and `multi_install_safe` (single boolean).
- **No conditional content processing** in `process_template()`. The template engine does flat substitution only (`{SCRIPT}`, `__AGENT__`, `__CONTEXT_FILE__`).
- **Workflow expressions engine** (`expressions.py`) implements a safe Jinja2 subset with conditional evaluation, but it's walled off from command template processing.
- **Extension manifest `requires`** has a `tools` list but no `capabilities` validation.

## Approaches Considered

### A: Capability Metadata + Template Conditionals (chosen)

Add a declarative capability system to spec-kit integrations, with conditional content processing in the template pipeline. Extension commands use generic capability placeholders and conditional blocks. Each integration's post-processor rewrites them to agent-specific instructions at install time.

- Pros: Clean separation of concerns. Generic enough for any extension. Follows existing spec-kit patterns. Zero degradation for Claude Code (post-processing injects CC-optimized content). Source commands are readable with explicit conditional syntax.
- Cons: Introduces a template conditional syntax into command markdown. Requires spec-kit changes. Extensions must learn the placeholder vocabulary.

### B: Content Transform Callbacks (No Template Language)

Commands stay written in "Claude Code vocabulary" (the reference agent). Each integration's post-processor rewrites tool names and removes/adds sections. No template syntax in source.

- Pros: No new syntax. Commands remain simple. Claude Code commands unchanged.
- Cons: Fragile text replacement. Section removal/addition is complex without markers. Claude Code becomes the "default" rather than one-among-equals. Each integration must know what to rewrite.

### C: Conditional Section Markers (HTML Comments)

Use HTML comment markers (`<!-- BEGIN:subagents -->...<!-- END:subagents -->`) that the registrar strips at install time.

- Pros: Lightweight. Familiar syntax.
- Cons: HTML comments are invisible in rendered markdown, making both conditional branches appear as equivalent text. Authors reading the source see conflicting instructions without understanding which applies where. Defeats the purpose of explicit conditionals.

## Decision (Revised 2026-07-02)

**Original decision (Approach A: Capability Matrix + Template Conditionals) was rejected by upstream.**

After [detailed feedback from the spec-kit maintainer](https://github.com/github/spec-kit/issues/3303#issuecomment-4866030391), the approach has been revised to work within spec-kit's existing extensibility layers rather than adding new core abstractions.

### Upstream Feedback Summary

The maintainer accepted one part and redirected the rest:

**Accepted for a core PR:**
- Generalizing `post_process_skill_content()` into `post_process_command_content()` for all format types (not just skills-format agents). This gives extension authors a clean per-agent content transform seam.

**Rejected (capability matrix + conditional template blocks):**
- Breaks the "materialization invariant": after `specify init`, the project directory is the whole truth. A capability system would be the first feature where understanding a command requires reaching into core Python that lives in a different repo on a different release cadence.
- Extension templates in catalog repos would reference capabilities defined in core, breaking independent reviewability.
- Capability data is volatile and externally controlled (agent vendors change tools on their own schedule). Core would be subscribing to dozens of external changelogs.
- Maintainers can't reliably test ~40 agents. The people who can verify a given agent's behavior are the folks who actually run it.

**Suggested alternative (presets + extensions):**
- **Presets** specialize agnostic commands for a specific agent via `prepend`/`replace`. A user installs only the preset matching their agent. Each variant is self-contained plain text, owned and tested by someone who runs that agent.
- **Extension-local paths** already handle script discovery (`.specify/extensions/<id>/` is stable and project-local, path rewriting preserves references).
- The `post_process_command_content()` hook provides the per-agent content transform seam.

### Revised Approach: Presets + Post-Processing

The architecture becomes: write commands in neutral vocabulary, then specialize via per-agent presets and the post-processing hook.

| Layer | Mechanism | Who owns it |
|-------|-----------|-------------|
| Command source | Neutral vocabulary, no agent-specific tool names | Extension author (us) |
| Agent specialization | Presets with `prepend`/`replace` directives | Per-agent preset author (us for Claude, community for others) |
| Content transforms | `post_process_command_content()` on `IntegrationBase` | spec-kit core (our PR) |
| Script discovery | Extension-local paths + context hook | spec-kit paths + spex context hook |
| Hook adapters | Per-agent adapter scripts | Extension author (us, already done) |

## Revised Key Requirements

### Upstream PR: `post_process_command_content()` hook

A focused PR to spec-kit core:

1. Add `post_process_command_content(content: str, command_name: str) -> str` to `IntegrationBase` with a default no-op implementation.
2. Call it from `register_commands()` in `agents.py` for all format types (markdown, TOML, YAML), not just skills-format agents.
3. Each integration subclass can override to apply agent-specific transforms at install time.

This is low-risk, branch-free, and testable per-integration. The maintainer explicitly invited this PR.

### Spex Work: Neutral Commands + Claude Preset

**Phase 1: Script discovery (DONE)**
- Replaced all 16 `find ~/.claude` patterns with `<PLUGIN_ROOT>` references (shipped in 033-plugin-root-refs).
- The context hook injects the plugin root path in every prompt. This is spex-specific but aligns with spec-kit's extension-local path philosophy.

**Phase 2: Neutral command vocabulary**
- Rewrite commands to use generic descriptions for agent capabilities instead of tool-specific names.
- Example: "Present the user with a choice between these options" instead of "Use the `AskUserQuestion` tool with these options."
- Where Claude Code has a specific tool (Agent, AskUserQuestion, EnterWorktree) and others don't, use natural language instructions that any agent can interpret.
- Keep the behavioral intent clear so presets can specialize effectively.

**Phase 3: Claude Code preset**
- Create a `claude-spex` preset that optimizes neutral commands for Claude Code.
- Uses `prepend`/`replace` directives to inject Claude-specific tool references where they improve behavior.
- Example: replace "present the user with a choice" with "use AskUserQuestion with structured options."
- The preset is self-contained, installed by users who run Claude Code, and testable by us.

**Phase 4: Community presets (stretch)**
- Document how to create presets for other agents.
- The `post_process_command_content()` hook provides the programmatic seam.
- A preset like `opencode-spex` or `codex-spex` could be authored by someone who actually uses those agents.

### Design Properties (Revised)

- **Materialized and auditable**: everything is in the project as plain text after install. No reaching into core Python.
- **Self-contained per agent**: each user only installs their own agent's preset. No N-variant maintenance burden on core.
- **Testable by owners**: each preset is owned and tested by someone who runs that agent.
- **Incremental**: the upstream PR is independent. Phase 1 is done. Phases 2-4 can proceed independently.
- **Zero degradation for Claude Code**: the Claude preset injects the same optimized instructions we have today.

## Open Questions

- What is the right granularity for neutral vocabulary? Some instructions are naturally generic ("ask the user"), while others are deeply tool-specific (Agent tool's subagent spawning with worktree isolation, schema validation, etc.). The preset `replace` mechanism may struggle with complex multi-paragraph tool-specific sections.
- How should the Claude preset interact with existing spex commands that are already installed? Does `specify init` with a preset re-render commands, or is it additive?
- Should the hook adapter layer (detect-agent.sh + per-agent adapters) also move to the preset pattern, or does it stay as extension-level scripts?
- How do we handle the ship pipeline's deep coupling to the Agent tool? The ship command's subagent dispatch (stages 2, 5, 6, 7) is structurally different from "run sequentially" and a simple preset replace won't capture the architectural difference.

---

## Revisit: 2026-07-08

### Upstream Feedback: No New Hooks Needed

The spec-kit maintainer responded to [#3359](https://github.com/github/spec-kit/issues/3359) with a clear position: **everything needed for per-harness setup and adaptation is already achievable with existing workflow primitives.** No `on_install` hook, no `post_process_command_content()` upstream PR required.

Key points from the maintainer:
- Workflow `shell` + `switch` steps can express all per-harness adaptation logic
- `specify workflow run <https-url>` is the supported one-command install pattern
- Bundles declare `provides.workflows` so the setup workflow ships with extensions
- Adding `on_install` would make `specify extension add` a code-execution step, which is a larger trust surface than user-invoked workflows

### Impact on Phase Plan

This changes the dependency graph significantly. The original plan assumed Phases 2-3 needed an upstream `post_process_command_content()` hook. With the workflow approach, **all phases can proceed without upstream changes.**

| Phase | Original dependency | Updated dependency |
|-------|--------------------|--------------------|
| Phase 0: Setup workflow | None | **DONE** (feature 037) |
| Phase 1: Script discovery | None | **DONE** (feature 033) |
| Phase 2: Neutral vocabulary | Upstream hook | **None** (workflow `adapt-commands` step) |
| Phase 3: Claude preset | Upstream hook + Phase 2 | **Phase 2 only** (workflow applies transforms) |
| Phase 4: Community presets | Phase 3 | Phase 3 |

### Revised Approach: Workflow-Driven Command Adaptation

Instead of an upstream hook that transforms commands at `specify extension add` time, the **setup workflow transforms commands after installation** using shell steps:

```yaml
- id: adapt-commands
  type: switch
  expression: "{{ steps.detect-agent.output.stdout }}"
  cases:
    codex:
      - type: shell
        run: |
          # Transform skill files for Codex vocabulary
          adapt_script="{{ steps.locate-source.output.stdout }}/scripts/adapt-commands.sh"
          [ -f "$adapt_script" ] && sh "$adapt_script" codex .claude/skills/
    opencode:
      - type: shell
        run: |
          adapt_script="{{ steps.locate-source.output.stdout }}/scripts/adapt-commands.sh"
          [ -f "$adapt_script" ] && sh "$adapt_script" opencode .claude/skills/
```

The `adapt-commands.sh` script would:
1. Read each SKILL.md file
2. Apply per-harness substitution rules (maintained as a mapping file, not inline sed)
3. Handle complex multi-paragraph sections (tool-specific blocks delimited by markers)
4. Write the transformed files back

This is more capable than sed substitutions because the script can handle:
- Conditional block replacement (replace entire `### Agent Dispatch` sections)
- Tool name mapping with context awareness (AskUserQuestion with options vs without)
- Section removal (strip `EnterWorktree` instructions for harnesses without it)

### Updated Phase Plan

**Phase 2: Neutral command vocabulary (next)**
- Audit all 41 Claude Code-specific references in command files
- Add delimiter markers around tool-specific sections: `<!-- cc:agent-dispatch -->...<!-- /cc:agent-dispatch -->`
- Rewrite unmarked references to use natural language
- Write `adapt-commands.sh` with a mapping table per harness
- Add `adapt-commands` step to setup.yml after extension installation

**Phase 3: Claude Code optimization (after Phase 2)**
- The Claude case in setup.yml is a no-op (commands are already written for Claude)
- Or: write commands in neutral vocabulary, then the Claude `adapt-commands` case re-injects tool-specific references for optimal behavior
- Decision: no-op is simpler, but neutral-then-specialize is more principled

**Phase 4: Codex + OpenCode presets**
- Create `adapt-commands.sh` codex/opencode mapping tables
- Test on real projects with each harness
- Document how to add new harness mappings

### Open Questions (Updated)

- Should commands be written neutral-first and then specialized for ALL harnesses (including Claude), or written for Claude and then de-specialized for others? The neutral-first approach is cleaner but means Claude users see slightly different wording than today until the Claude adaptation step runs.
- The delimiter marker approach (`<!-- cc:agent-dispatch -->`) adds noise to the command files. Is there a cleaner way to identify tool-specific sections for replacement?
- How do we test that neutral commands produce acceptable behavior on each harness? The brainstorm with Codex showed that without skill content, the agent produces a brain dump instead of a structured dialogue. Neutral vocabulary alone may not be enough; the behavioral structure (checklist steps, one question at a time) needs to survive the transformation.
