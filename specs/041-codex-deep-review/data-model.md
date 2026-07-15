# Data Model: Codex Integration for Deep Review

**Date**: 2026-07-14
**Feature**: 041-codex-deep-review

## Entities

### External Tool Config (extended)

The `external_tools` section in `deep-review-config.yml` gains a new `codex` key:

```yaml
external_tools:
  coderabbit: true    # existing
  copilot: false      # existing
  codex: true         # NEW: enabled by default
```

**Attributes**:
- `codex` (boolean, default: `true`): Whether to detect and invoke Codex CLI during deep review

### Finding Schema (unchanged, new source_agent value)

The common finding schema is reused with a new `source_agent` value:

```
{
  id: "FINDING-N",
  severity: Critical|Important|Minor|Notable,
  confidence: 75,                    # fixed for Codex (same as CodeRabbit/Copilot)
  file: "relative/path",
  line_start: N,
  line_end: N,
  category: "external",             # same as CodeRabbit/Copilot
  description: "what is wrong",
  rationale: "why it matters",
  fix: "how to fix it",
  source_agent: "codex",            # NEW value
  also_reported_by: [],
  external_rationale: "full rationale from Codex output",
  resolution: "pending",
  round_found: N
}
```

### Harness Marker Block (new token)

A new harness marker token `codex-review-tool` wraps the Codex detection and dispatch content:

```
{harness:codex-review-tool}
... Codex detection, invocation, and parsing logic ...
{/harness:codex-review-tool}
```

**Adapter inclusion**:

| Adapter | Token present | Effect |
|---------|--------------|--------|
| Claude  | Yes          | Codex tool block included in adapted command |
| OpenCode| Yes          | Codex tool block included in adapted command |
| Codex   | No (omitted) | Codex tool block stripped, preventing recursion |

### Ship Pipeline Flags (extended)

The ship pipeline's external tool flag resolution gains two new flags:

| Flag | Effect |
|------|--------|
| `--codex` | Override config to enable Codex |
| `--no-codex` | Override config to disable Codex |

These follow the same resolution logic as `--coderabbit`/`--no-coderabbit` and `--copilot`/`--no-copilot`.
