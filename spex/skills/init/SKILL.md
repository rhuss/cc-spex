---
name: init
description: Initialize or refresh Spex with harness-neutral extension and security profiles.
---

# Spex initialization

After initialization, use `speckit.spex.ship` for the continuous validated
workflow. Codex receives native hooks and project security configuration here;
Claude status-line support is not installed for Codex.

Complete the workflow through its final report. A successful bootstrap alone is
not completion.

## 1. Establish current intent

Read `.specify/spex-profile.yml` when it exists. Treat its
`enabled_extensions` and `requested_security` as the defaults for a refresh.
Do not infer a user's choices only from installed extension directories.

For a new project, recommend:

- `spex-gates`, `spex-deep-review`, and `spex-worktrees`
- Safe security

Keep `spex-teams`, `spex-collab`, and `spex-detach` disabled unless explicitly
selected. Describe Teams as experimental. If Teams, deep review, or
collaboration is selected, include `spex-gates` as its required dependency.

When this is not a no-change refresh, use the active harness's supported choice
surface, or a concise text prompt when no native choice surface exists, to ask
for:

1. Extensions to enable.
2. Exactly one security profile: Safe, Autonomous, or YOLO.

Explain the security boundary before applying it:

- Safe preserves host approval and sandbox policy.
- Autonomous permits only enumerated, non-destructive Spex workflow operations
  inside the repository and active feature worktree.
- YOLO permits non-destructive workspace operations inside those locations.
- Network access, external side effects, destructive operations, and activity
  outside granted workspace authority remain approval boundaries.

## 2. Run the setup workflow

Resolve the plugin root from `<plugin-root>` in the `<spex-context>` reminder.
Run `setup.yml` through the `specify workflow run` command with:

- `integration=<active harness>`
- `extensions=<selected comma-separated list>` (or `recommended` on a new
  project and on a no-change refresh)
- `security=<requested profile>`
- `fallback_confirmation=decline`

For `--refresh`, keep the persisted selections and requested security unless
the user explicitly changes them. For `--update`, update the Specify CLI first,
then run the same refresh workflow. For `--clear`, use the init command from
the context reminder and report the reset without changing the profile.

If Specify is unavailable, report the exact installation instruction emitted
by the init command and stop without changing configuration.

## 3. Handle a safer fallback

The active harness adapter may determine that the requested security behavior
cannot be represented safely. When setup reports `confirmation_required`:

1. Show the requested level, proposed safer level, reason, additional autonomy
   that would be lost, and safeguards that remain.
2. Ask one focused confirmation question.
3. On acceptance, rerun the same workflow with
   `fallback_confirmation=accept`.
4. On refusal, stop. Do not edit the initialization profile or harness project
   configuration.

Never silently broaden a security profile or silently persist a safer fallback.
Any validation, capability, or persistence failure must be reported without
manual repair or partial profile edits.

## 4. Report the effective result

Read the persisted profile and report:

- active harness
- enabled extensions
- requested and effective security levels
- any confirmed fallback and unavailable/degraded capabilities
- profile revision
- whether the harness requires trust review, refresh, or a new session

Do not advertise integrations that the active harness does not support.
