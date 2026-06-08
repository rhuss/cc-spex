# Proposal: Hook Adapter Framework for spec-kit Extensions

**Target repo:** github/spec-kit (upstream)
**Status:** draft (local review before posting)
**Related:** cc-spex brainstorm 16 (multi-agent-support)

---

## Title

Feature: Hook adapter framework for agent-portable extension enforcement

## Summary

Extensions can declare hooks in `extension.yml` (e.g., `before_specify`, `after_implement`), and spec-kit registers them. But the hook *scripts* themselves are agent-specific: Claude Code uses Python hooks with `UserPromptSubmit`/`PreToolUse` events, Codex CLI uses the same event names but a different JSON contract, OpenCode uses TypeScript plugins with `tool.execute.before`, and Gemini uses shell scripts with `BeforeTool`.

This means extension authors who want enforcement hooks must write separate implementations per agent, or accept that their hooks only work on one agent.

## Proposal

Add a hook adapter layer to spec-kit that:

1. **Defines a portable hook contract**: Extension hooks declare their intent (block tool X until condition Y, inject context Z before prompt) in `extension.yml` using a declarative format.

2. **Generates agent-specific hook scripts**: During `specify init` or extension install, spec-kit generates the correct hook implementation for the detected agent, similar to how `CommandRegistrar` generates command files in the right format per agent.

3. **Provides a shared logic layer**: Hook business logic (e.g., "block non-Skill tools until command is resolved") lives in a shared module. Agent-specific adapters translate between the shared logic and each agent's hook API.

## Proposed extension.yml syntax

```yaml
hooks:
  before_specify:
    command: speckit.git.feature
    optional: false
    description: "Create feature branch before specification"

  # New: enforcement hooks (declarative)
  enforce:
    - event: pre_tool_use
      condition: "pending_command and tool != 'Skill'"
      action: deny
      message: "Load the skill first"
    
    - event: user_prompt_submit
      action: inject_context
      context:
        plugin_root: true
        session_state: true
        command_validation: true
```

## Agent mapping

| Portable event | Claude Code | Codex CLI | OpenCode | Gemini CLI |
|---|---|---|---|---|
| `pre_tool_use` | PreToolUse hook | PreToolUse hook | tool.execute.before plugin event | BeforeTool hook |
| `user_prompt_submit` | UserPromptSubmit hook | UserPromptSubmit hook | In-skill preamble (no equivalent) | BeforeAgent hook |
| `ask_user` | AskUserQuestion tool | Inline text prompt | question tool | Inline text prompt |

## Benefits

- Extension authors write enforcement logic once
- spec-kit generates the right hook format per agent
- Consistent with spec-kit's existing pattern (write once, generate per agent)
- Enables the extension ecosystem to work across all 32 supported agents

## Alternatives considered

- **Extensions ship per-agent hooks**: Works but doesn't scale. Every extension author must understand every agent's hook API.
- **Advisory enforcement only**: Skip hooks entirely, rely on AGENTS.md instructions. Loses the mechanical enforcement that makes process discipline reliable.

## Open questions

- Should the declarative format support arbitrary conditions, or a fixed set of known patterns (pending_command, stage_ordering, verify_before_commit)?
- How to handle agents that can't support a hook at all (graceful degradation vs skip)?
- Should the shared logic layer be Python, shell, or something else?

## Prior art

- `CommandRegistrar` already does this for commands (write once, generate per agent)
- `ExtensionManifest` already declares hooks in extension.yml
- The integration base classes (MarkdownIntegration, TomlIntegration, SkillsIntegration) show the pattern of abstracting agent differences behind a common interface
