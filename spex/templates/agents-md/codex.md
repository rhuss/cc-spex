# spex: Spec-Driven Development Plugin

## Workflow

spex enforces a spec-first development workflow. All features follow:
specify -> clarify -> plan -> tasks -> implement -> review -> verify

## Enforcement

Hooks enforce this workflow mechanically via PreToolUse and UserPromptSubmit hooks.
You do not need to remember the rules; the hooks will block invalid actions.

## Interactive Prompts

Codex does NOT have the AskUserQuestion tool. When a skill instructs you to
present options to the user, use an **inline numbered list** instead:

```
Choose an option:
1. Option A - description
2. Option B - description
3. Option C - description

Enter the number of your choice:
```

Wait for the user's response before proceeding. Do NOT call AskUserQuestion
(it does not exist on Codex). Do NOT assume a default choice.

## Parallel Work

Use **subagents** when explicitly requested for parallel task dispatch.
Each subagent should work on independent tasks. Coordinate completion
before proceeding to review.

## Context Management

Start a **new session** to reset context when token usage is high.
There is no /clear command on Codex.

## Worktrees

Codex does NOT have the EnterWorktree tool. To create isolated workspaces,
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
