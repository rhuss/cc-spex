# Data Model

No new persistent data. Files involved:

| File | Owner | Role in this feature |
|------|-------|----------------------|
| `.specify/extensions/spex-detach/spex-detach-config.yml` | user (template from extension) | Preserved byte-identical across reinstall (FR-007, FR-009a) |
| `.specify/.spex-detach-config.saved.yml` | spex (transient) | Exists only between `save` and `restore` during setup/refresh, or after an interrupted run |
| `<git-common-dir>/info/exclude` | clone-local | Receives configured entries under the `# spex-detach:` marker; each entry at most once |
| `.specify/extensions/.registry` | spec-kit | Source of truth for whether spex-detach is enabled |

## Exclude entry classification (verify)

| Form | Example | Probe |
|------|---------|-------|
| Directory | `specs/` | `specs/.spex-detach-probe` |
| Glob | `*.local.md` | `spex-probe.local.md` |
| File | `CLAUDE.md` | `CLAUDE.md` |
| Negation / comment / blank | `!keep.md`, `# x` | skipped |

Visible reasons: `not-ignored` (git does not ignore the probe), `tracked` (git tracks files under the entry).
