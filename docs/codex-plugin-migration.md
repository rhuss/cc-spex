# Migrating to the Codex plugin

Spex 6 adds a native Codex distribution while retaining the Claude plugin.
Install Codex through its personal marketplace, then run `spex:init` in each
repository. Existing Claude configuration is left untouched unless you
explicitly request cross-harness changes.

Initialization now stores `.specify/spex-profile.yml` with the selected
extensions and one security level: `safe`, `autonomous`, or `yolo`. Legacy
inputs map as follows:

| Legacy input | New selection |
|---|---|
| `standard` | `safe` |
| `yolo` | `yolo` |
| `none` | `safe` with no optional extensions |

Safe preserves host policy. Autonomous permits only enumerated,
non-destructive Spex operations in the repository/worktree. YOLO additionally
permits other non-destructive workspace operations. Network access, external
side effects, destructive actions, and out-of-workspace operations remain host
approval boundaries. If the installed Codex cannot express a requested level,
initialization offers a safer fallback and changes nothing until confirmed.

On refresh, existing extension and security selections are retained by
default. Teams remains experimental and is never enabled implicitly. Claude
status-line configuration is neither installed nor advertised by Codex.
