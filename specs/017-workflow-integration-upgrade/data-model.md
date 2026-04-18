# Data Model: Workflow and Integration Upgrade

## Entities

### Workflow Definition (`spex-ship.yml`)

A declarative YAML file defining the ship pipeline.

**Fields:**
- `id` (string): Workflow identifier, e.g., `spex-ship`
- `name` (string): Human-readable name
- `version` (string): Semver version
- `inputs` (map): Typed workflow inputs (spec, ask, create_pr, use_teams)
- `hooks.pre_run` (list): Shell commands to run before workflow starts
- `hooks.post_run` (list): Shell commands to run after workflow completes
- `steps` (list): Ordered pipeline steps with optional conditions

**Relationships:** Installed in `.specify/workflows/spex-ship/` by `specify workflow add`. References extension commands as step targets.

### Workflow Marker (`.specify/.spex-workflow-active`)

A JSON file signaling that a workflow is running.

**Fields:**
- `pid` (integer): Process ID of the workflow runner
- `started_at` (string, ISO 8601): Timestamp when workflow started

**Lifecycle:** Created by `pre_run` hook, removed by `post_run` hook. Stale markers (dead PID) are cleaned by init and ignored by review commands.

### Plugin Mapping (`spex/plugin-integrations.yml`)

A YAML configuration defining companion plugins to detect.

**Fields per plugin entry:**
- `detect` (string): Filesystem path to check (supports `~` expansion)
- `marker` (string): File to validate inside the detected directory (default: `plugin.json`)
- `skills` (list of strings): Skill names the plugin provides
- `inject_into` (map): Command name to injection instruction mapping

**Relationships:** Read by `spex-init.sh` during initialization. Results written to `.specify/spex-plugins.json`.

### Plugin State (`.specify/spex-plugins.json`)

A JSON file recording detected companion plugins.

**Fields per plugin:**
- `available` (boolean): Whether the plugin was found and validated
- `path` (string): Resolved detection path
- `skills` (list of strings): Available skills from this plugin
- `inject_into` (map): Active injection targets (only populated when available)

**Lifecycle:** Written during init, refreshed on each init run. Read by extension commands at execution time.

## State Transitions

### Workflow Marker Lifecycle

```
[No marker] ---(workflow starts)---> [Active: PID alive]
[Active: PID alive] ---(workflow completes)---> [No marker]
[Active: PID alive] ---(process crashes)---> [Stale: PID dead]
[Stale: PID dead] ---(init runs)---> [No marker]
[Stale: PID dead] ---(review command checks)---> [No marker] (cleaned up, review proceeds)
```

### Plugin State Lifecycle

```
[No state file] ---(init runs)---> [State with detected plugins]
[State exists] ---(init runs again)---> [State refreshed]
[Plugin removed from system] ---(init runs)---> [Plugin marked unavailable]
```
