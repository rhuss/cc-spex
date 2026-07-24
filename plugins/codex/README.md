# Codex distribution descriptor

This directory owns the thin Codex-specific distribution descriptor. The
materializer combines it with the canonical shared implementation under
`spex/`; shared workflows and scripts must not be copied here.

Planned inventory:

- `.codex-plugin/plugin.json` — native Codex plugin manifest
- `hooks/hooks.json` — plugin-root-relative Codex hooks
- harness adapter metadata used during materialization

Generated or materialized plugin contents do not belong in this source
directory.
