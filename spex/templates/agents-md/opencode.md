# spex: Spec-Driven Development Plugin

## Workflow

spex enforces a spec-first development workflow. All features follow:
specify -> clarify -> plan -> tasks -> implement -> review -> verify

## Enforcement

Tool gates enforce this workflow mechanically via the spex plugin
(tool.execute.before event). The plugin blocks invalid tool calls.

Skill preambles provide additional command validation and context injection
that would normally come from UserPromptSubmit hooks. When you load a skill,
follow its preamble instructions before proceeding.

## Interactive Prompts

When a skill instructs you to present options to the user, use the
**question** tool to display choices. Structure options clearly:

```
Use the question tool with:
- A clear prompt describing what to choose
- Options as an array of labeled choices
```

Do NOT use AskUserQuestion (it does not exist on OpenCode).
Do NOT present options as plain text without the question tool.

## Parallel Work

Use the **Task** tool for parallel task dispatch. Each task runs independently.
Coordinate task completion before proceeding to review.

## Context Management

Start a **new session** to reset context when token usage is high.
There is no /clear command on OpenCode.

## Worktrees

OpenCode does NOT have the EnterWorktree tool. To create isolated workspaces,
use git commands directly:

```bash
git worktree add ../<feature-name> -b <branch-name>
```

When done, clean up with:

```bash
git worktree remove ../<feature-name>
```

## Commands

- `/spex:ship` - Full autonomous workflow (specify through verify)
- `/spex:brainstorm` - Refine ideas into specifications
- `/spex:help` - Quick reference for all commands
- `/speckit-specify` - Create feature specification
- `/speckit-plan` - Create implementation plan
- `/speckit-tasks` - Generate task breakdown
- `/speckit-implement` - Execute implementation
