# spex: Spec-Driven Development Plugin

## Workflow

spex enforces a spec-first development workflow. All features follow:
specify -> clarify -> plan -> tasks -> implement -> review -> verify

## Enforcement

Hooks enforce this workflow mechanically via PreToolUse and UserPromptSubmit hooks.
You do not need to remember the rules; the hooks will block invalid actions.

## Interactive Prompts

When a skill needs user input, use the **AskUserQuestion** tool to present options.
Structure choices with clear labels and descriptions. Support multi-select when needed.

## Parallel Work

Use the **Agent** tool with `team_name` for parallel task dispatch via Agent Teams.
Each teammate gets an isolated worktree. The lead reviews all changes against spec.md.

## Context Management

Use **/clear** between phases to reset context when token usage is high.
The ship pipeline statusline shows current progress.

## Worktrees

Use **EnterWorktree** to create isolated workspaces for feature development.
The worktree extension automates creation after specify completes.

## Commands

- `/spex:ship` - Full autonomous workflow (specify through verify)
- `/spex:brainstorm` - Refine ideas into specifications
- `/spex:help` - Quick reference for all commands
- `/speckit-specify` - Create feature specification
- `/speckit-plan` - Create implementation plan
- `/speckit-tasks` - Generate task breakdown
- `/speckit-implement` - Execute implementation
