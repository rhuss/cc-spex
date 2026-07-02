# Brainstorm: Harness-Agnostic Spex

**Date:** 2026-07-02
**Status:** active

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

## Decision

**Approach A: Capability Metadata + Template Conditionals**, delivered as two coordinated specs.

Approach C was eliminated because invisible HTML comments make source files confusing (both branches render as equivalent text). Approach B was eliminated because fragile text replacement and implicit "reference agent" conventions are error-prone.

The implementation approach for the template conditional system (reuse workflow expressions engine vs. purpose-built) is left to the spec-kit spec.

## Key Requirements

### Spec A: Spec-Kit Capability System (generic, upstream)

1. **Capability declarations on integrations** - Each `IntegrationBase` subclass declares a `capabilities` dict with:
   - `interactive_prompts` - tool name, structured vs simple, multi-select support
   - `subagents` - tool name, background execution, worktree isolation
   - `process_enforcement` - hooks available, pre-tool gate
   - `worktrees` - built-in tool vs manual git
   - `context_clearing` - command name or unavailable
   - Generic-to-agent tool name mapping

2. **Conditional content processing** - A mechanism in the template pipeline to include/exclude sections based on capability flags and substitute generic tool names with agent-specific ones. Implementation approach TBD (could reuse the existing workflow expressions engine or add a simpler system).

3. **Generalize post-processing to all format types** - Call `post_process_command_content()` from `register_commands()` in `agents.py` for markdown, TOML, and YAML agents, not just skills-format agents.

4. **Plugin root variable** - Expose `__PLUGIN_ROOT__` or equivalent substitution so extensions don't need `find ~/.claude` patterns for script discovery.

### Spec B: Spex Harness-Agnostic Refactor (depends on Spec A)

1. **Replace all `find ~/.claude` patterns** (14 instances) with the plugin root variable
2. **Replace tool name references** with generic capability placeholders
3. **Add conditional sections** for capability-dependent features (subagent dispatch, interactive prompts, context clearing)
4. **Refactor init skill** with per-agent init templates for permissions/settings configuration
5. **Hook system** stays in the adapter layer (already agent-specific via detect-agent.sh + per-agent adapters)
6. **All extensions in scope** - spex, spex-gates, spex-worktrees, spex-teams, spex-deep-review, spex-collab, spex-detach
7. **Zero degradation for Claude Code** - spec-kit's post-processing injects CC-optimized content at install time

### Design Properties

- **Declarative capability model** - integrations declare what they support statically, not discovered at runtime
- **Generic source, optimized output** - command sources use generic vocabulary; installed commands are agent-specific
- **Follows existing patterns** - extends `_feature_capabilities()` pattern to integration level, extends `post_process_skill_content()` to all formats
- **Incremental** - spec-kit enhancement is small and independently useful; spex refactor can be done extension by extension

## Open Questions

- What is the exact capability vocabulary? The initial list (interactive_prompts, subagents, etc.) needs validation against all 28 supported agents
- Should the capability dict be flat booleans or structured (with tool names and sub-properties)?
- How should extensions declare minimum capability requirements in their `extension.yml` manifest?
- Should spec-kit warn or error when installing an extension on an agent that lacks required capabilities?
- How should the hook adapter layer evolve? Currently spex has adapters for Claude Code, Codex, and OpenCode. Should spec-kit's integration system manage hook adapters too?
- How much of the existing multi-platform dispatch sections in teams/deep-review commands can be replaced by the capability system vs. remaining as explicit agent-specific instructions?
