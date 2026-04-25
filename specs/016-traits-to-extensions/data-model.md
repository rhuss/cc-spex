# Data Model: Replace Traits with Spec-Kit Extensions

## Entities

### Extension (spec-kit native)

Represents a self-contained capability bundle installed in a project.

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique identifier (e.g., `spex`, `spex-gates`) |
| `name` | string | Human-readable name |
| `version` | semver | Extension version |
| `description` | string | One-line purpose |
| `author` | string | Author identifier |
| `enabled` | boolean | Whether the extension is active |
| `priority` | integer | Execution order (lower = higher precedence, default 10) |

**Identity**: `id` is unique across all installed extensions.
**Lifecycle**: installed (via `specify extension add`) -> enabled (default) <-> disabled (via `specify extension disable/enable`) -> removed (via `specify extension remove`).

### Extension Command

A markdown file that defines an AI agent command provided by an extension.

| Field | Type | Description |
|-------|------|-------------|
| `name` | dotted-string | Command identifier (e.g., `speckit.spex-gates.review-spec`) |
| `file` | path | Relative path to markdown file within extension |
| `description` | string | One-line purpose |
| `agent` | string | Target agent (detected automatically by spec-kit) |

**Identity**: `name` is unique across all extensions (enforced by `speckit.{ext-id}.{cmd}` naming).
**Naming convention**: `speckit.{extension-id}.{command-name}`

### Lifecycle Hook

A before/after trigger that invokes an extension command at a spec-kit lifecycle event.

| Field | Type | Description |
|-------|------|-------------|
| `extension` | string | FK to Extension.id |
| `command` | dotted-string | FK to Extension Command.name |
| `event` | enum | Lifecycle event (see below) |
| `optional` | boolean | `true` = user can skip; `false` = always runs |
| `enabled` | boolean | Matches extension enabled state |
| `prompt` | string? | User-facing prompt text (optional hooks only) |
| `description` | string | Purpose description |
| `condition` | string? | Condition expression (evaluated by spec-kit) |

**Lifecycle events**: `before_constitution`, `after_constitution`, `before_specify`, `after_specify`, `before_clarify`, `after_clarify`, `before_plan`, `after_plan`, `before_tasks`, `after_tasks`, `before_implement`, `after_implement`, `before_checklist`, `after_checklist`, `before_analyze`, `after_analyze`, `before_taskstoissues`, `after_taskstoissues`

**Execution order**: Multiple hooks on the same event execute sequentially in the order they appear in `.specify/extensions.yml`.

### Extension Config

Per-extension YAML configuration with two layers.

| Field | Type | Description |
|-------|------|-------------|
| `template` | filename | Shipped default config (never modified by user) |
| `active` | filename | User-editable config (copied from template on install) |

**Override precedence**: Extension defaults (template) < Project overrides (active config file).

### Extension Registry Entry

Tracking record for an installed extension in `.specify/extensions/.registry`.

| Field | Type | Description |
|-------|------|-------------|
| `version` | semver | Installed version |
| `source` | string | Install source (`local` for `--dev` installs) |
| `manifest_hash` | string | SHA-256 of `extension.yml` |
| `enabled` | boolean | Active state |
| `priority` | integer | Execution priority |
| `registered_commands` | map | Agent -> list of command names |
| `registered_skills` | list | Auto-generated skill files |
| `installed_at` | ISO-8601 | Installation timestamp |

### Ship Pipeline State

Tracking file for autonomous pipeline execution (`.specify/.spex-state`).

| Field | Type | Description |
|-------|------|-------------|
| `mode` | enum | `flow` (autonomous) |
| `status` | string | Pipeline status |
| `started_at` | ISO-8601 | Pipeline start time |
| `feature_branch` | string | Current branch |
| `spec_dir` | string | Spec directory path |
| `ask` | enum | User interaction level (`always`, `smart`, `never`) |
| `implemented` | boolean | Whether implement phase completed |
| `clarified` | boolean | Whether clarify phase completed |

**Unchanged from current system.** Ship state is independent of the overlay/extension mechanism.

## Relationships

```
Extension 1--* Extension Command
Extension 1--* Lifecycle Hook
Extension 0..1--1 Extension Config
Extension 1--1 Extension Registry Entry
Lifecycle Hook *--1 Extension Command (hook.command -> command.name)
```

## State Transitions

### Extension Lifecycle

```
[not installed] --add--> [installed, enabled]
[installed, enabled] --disable--> [installed, disabled]
[installed, disabled] --enable--> [installed, enabled]
[installed, *] --remove--> [not installed]
```

**On disable**: Commands removed from agent directory, hooks set `enabled: false` in `extensions.yml`, generated skills removed.
**On enable**: Commands re-registered, hooks set `enabled: true`, skills regenerated.
**On remove**: Extension directory deleted, registry entry removed, hooks removed from `extensions.yml`.

### Ship Pipeline

```
[idle] --ship start--> [running: specify]
[running: specify] --after_specify hooks--> [running: plan]
[running: plan] --after_plan hooks--> [running: tasks]
[running: tasks] --> [running: implement]
[running: implement] --check teams--> [running: teams-implement | standard-implement]
[running: *-implement] --after_implement hooks--> [running: pr]
[running: pr] --> [idle]
```

The ship command checks `spex-teams` enabled state in the registry to decide between standard and teams implement.
