# Data Model: Collab Triage Lifecycle

## Flow State (`.specify/.spex-state`)

Extended fields (added to existing flow state JSON):

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `triage_spec_passed` | boolean | `false` | Set to `true` when spec triage gate is passed |
| `triage_impl_passed` | boolean | `false` | Set to `true` when impl triage gate is passed |

Valid `running` phase values (added to existing set):

| Value | Description |
|-------|-------------|
| `triage-spec` | Spec PR triage is active |
| `triage-impl` | Implementation PR triage is active |

Example state after spec triage completes:

```json
{
  "mode": "flow",
  "feature_branch": "022-collab-triage-lifecycle",
  "spec_dir": "specs/022-collab-triage-lifecycle",
  "implemented": false,
  "clarified": true,
  "review_spec_passed": true,
  "triage_spec_passed": true,
  "triage_impl_passed": false,
  "running": ""
}
```

## Collab Config (`.specify/extensions/spex-collab/collab-config.yml`)

Extended fields (added to existing config):

```yaml
triage:
  split_threshold: 100    # comment count above which PR split is recommended
  loop_interval: "5m"     # default interval for /loop triage suggestion
  bot-profiles: []        # (existing, unchanged)
  overrides: {}           # (existing, unchanged)
```

## Triage State (`.specify/.pr-triage-state.json`)

Existing file, not modified. Read-only access by the gate check.

Structure (per PR):

```json
{
  "<pr_number>": {
    "<comment_db_id>": {
      "action": "accepted|rejected|skipped",
      "handledAt": "ISO-8601",
      "replyId": "<reply_id>"
    }
  }
}
```

Gate check counts entries: `jq '."<pr_number>" | length'`

## Extension Registry (`.specify/extensions/.registry`)

Read-only. Used to check if spex-collab is enabled:

```json
{
  "extensions": {
    "spex-collab": {
      "enabled": true
    }
  }
}
```

## Flow State Gate Mapping

| Gate Action | State Field | Triggered By |
|-------------|-------------|--------------|
| `triage-spec` | `triage_spec_passed` | User runs `spex-flow-state.sh gate triage-spec` after spec triage |
| `triage-impl` | `triage_impl_passed` | User runs `spex-flow-state.sh gate triage-impl` after impl triage |
