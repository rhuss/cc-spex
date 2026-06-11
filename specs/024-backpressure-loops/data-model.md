# Data Model: Backpressure Loops

## Watch State (extension of .specify/.spex-state)

The existing state file gains a new `mode: "watch"` value and watch-specific fields.

### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| mode | string | yes | `"watch"` (new value alongside existing `"ship"` and `"flow"`) |
| pr_number | integer | yes | PR number being monitored |
| pr_url | string | yes | Full PR URL for reporting |
| watch_started_at | ISO 8601 string | yes | When watch mode began |
| watch_timeout_minutes | integer | yes | Max watch duration (default: 30) |
| watch_poll_interval_seconds | integer | yes | Polling interval (default: 60) |
| last_ci_status | string | yes | One of: `"pending"`, `"passing"`, `"failing"`, `"none"` |
| last_ci_check_at | ISO 8601 string | no | Timestamp of last CI poll |
| ci_fix_attempts | integer | yes | Number of CI fix attempts made (max 2) |
| last_triage_at | ISO 8601 string | no | Timestamp of last triage invocation |
| triage_count | integer | yes | Number of triage passes executed |
| feature_branch | string | yes | Branch name (for statusline context) |
| spec_dir | string | no | Spec directory path (for context) |

### State Transitions

```
finish --watch creates PR
    → mode: "watch", last_ci_status: "pending"

Poll: CI pending
    → no change, schedule next poll

Poll: CI passing, no new comments
    → cleanup state, exit success

Poll: CI passing, new comments (collab enabled)
    → invoke triage, update last_triage_at, schedule next poll

Poll: CI failing
    → attempt fix, increment ci_fix_attempts, push, schedule next poll

Poll: CI failing, ci_fix_attempts >= 2
    → pause, report unresolvable failure

Poll: timeout expired
    → report final status, cleanup state, exit

Poll: PR closed/merged externally
    → cleanup state, exit
```

## Spex Config (new file)

`.specify/extensions/spex/spex-config.yml` provides project-level configuration for spex core extension behavior.

### Schema

```yaml
implement:
  test_between_tasks: true  # default: true, set false to skip inter-task checkpoints

watch:
  timeout_minutes: 30       # default: 30
  poll_interval_seconds: 60  # default: 60
```

### Defaults

All fields are optional. When the config file doesn't exist or a field is missing, the defaults shown above apply.
