# Quickstart: Collab Triage Lifecycle

## Workflow (with spex-collab enabled)

### After spec PR creation

The workflow automatically suggests triage:

```
Bot reviewers typically need 1-2 minutes to post comments.
When ready, run:  /loop 5m /speckit-spex-collab-triage
```

Run the suggested command to triage bot and human review comments.

### After spec triage completes

Mark triage as done and invoke the phase-manager:

```
/speckit-spex-collab-phase-manager
```

The phase-manager checks comment volume and recommends:
- **< 100 comments**: Continue on same PR (updates title to "[Spec + Impl]")
- **>= 100 comments**: Merge spec PR, create separate impl PR(s)

### After implementation push

Same pattern as spec triage:

```
Bot reviewers typically need 1-2 minutes to post comments.
When ready, run:  /loop 5m /speckit-spex-collab-triage
```

## Configuration

In `.specify/extensions/spex-collab/collab-config.yml`:

```yaml
triage:
  split_threshold: 100    # comment count for split recommendation
  loop_interval: "5m"     # interval for /loop suggestion
```

## Status Line

The `T` badge shows triage state:
- `T ○` pending
- `T ▶` active (triage running)
- `T ✓` complete
