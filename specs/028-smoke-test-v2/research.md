# Research: Smoke Test V2

**Date**: 2026-06-23

## Evidence Transfer Mechanism

**Decision**: Subagent returns evidence as structured text via the Agent tool's return value.
**Rationale**: The Agent tool returns the subagent's final text as a string. This is the simplest approach with no file coordination. The evidence payload (scenario results with command output) fits comfortably in a return message. If individual command outputs are very large, they can be truncated with markers.
**Alternatives considered**: Writing a JSON file to `.specify/` (adds file coordination complexity), returning both file and text (over-engineered for this use case).

## App Lifecycle Ownership

**Decision**: The main session owns app startup and shutdown. The subagent assumes the app is already running.
**Rationale**: The subagent is ephemeral. If it starts an app process, that process dies when the subagent ends, before the human review phase begins. The main session persists across both phases, so it can keep the app running throughout.
**Alternatives considered**: Subagent handles everything (app dies between phases), no auto-start (manual only, increases friction).

## Subagent Context Isolation

**Decision**: The Agent tool spawns subagents with no access to the parent conversation's context. This is the documented behavior and is the core mechanism for achieving fresh context.
**Rationale**: Confirmed by the Agent tool documentation: "A new Agent call starts a fresh agent with no memory of prior runs, so the prompt must be self-contained." This is exactly the property needed for unbiased smoke testing.
**Alternatives considered**: Using /clear (doesn't truly remove context, only compresses), starting a new session (too heavy, loses project state).
