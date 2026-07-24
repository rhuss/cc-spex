# Claude distribution descriptor

This directory owns the thin Claude-specific distribution descriptor. The
materializer combines it with the canonical shared implementation under
`spex/`; shared workflows and scripts must not be copied here.

Planned inventory:

- `adapter.json` — Claude manifest, configuration, hook, and capability mapping
- harness-owned manifest metadata referenced by the adapter

Generated or materialized plugin contents do not belong in this source
directory.
