# Extension Command Contract

Each extension command is a Markdown file with YAML frontmatter.

## Format

```markdown
---
description: "One-line description of what this command does"
---

# Command Title

[Command instructions for the AI agent]
```

## Naming Convention

Command files MUST be named `speckit.{extension-id}.{command-name}.md`.

Examples:
- `speckit.spex.brainstorm.md`
- `speckit.spex-gates.review-spec.md`
- `speckit.spex-teams.implement.md`

## Location

Commands live in `commands/` within the extension directory:
```
spex/extensions/{ext-id}/commands/speckit.{ext-id}.{cmd}.md
```

After installation, they are registered in the agent-specific directory:
```
.claude/commands/speckit.{ext-id}.{cmd}.md    # Claude Code
.codex/commands/speckit.{ext-id}.{cmd}.md     # Codex (future)
```

## Autonomous Mode Support

Commands that participate in the ship pipeline MUST check `.specify/.spex-state`:
- If `status` is `running`, suppress user prompts and completion summaries
- If `ask` is `smart` or `never`, do not use AskUserQuestion

This replaces the `_ship-guard` overlay pattern. Each command owns its autonomous behavior.
