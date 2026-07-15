# Data Model: Brainstorm Directory Sync

## Entities

### BrainstormDocument

Represents a markdown file in `brainstorm/` containing a brainstorm session.

| Attribute | Type | Source |
|-----------|------|--------|
| filename | string | Filesystem (e.g., `09-traits-to-extensions.md`) |
| number | string or null | Parsed from filename prefix (e.g., `09`), null for unnumbered |
| slug | string | Topic portion of filename (e.g., `traits-to-extensions`) |
| status | string | Parsed from `**Status:**` header field |
| inferred_status | string or null | Set to `spec-created` when spec match found but status differs |
| spec_match | string or null | Matching spec directory number (e.g., `016`) |
| match_source | string or null | How the match was found: `slug`, `overview`, or null |
| action | string | Classification result: `attic` or `keep` |

### SpecDirectory

Represents a numbered directory in `specs/` containing a feature specification.

| Attribute | Type | Source |
|-----------|------|--------|
| dirname | string | Filesystem (e.g., `016-traits-to-extensions`) |
| number | string | Parsed from directory prefix (e.g., `016`) |
| slug | string | Topic portion (e.g., `traits-to-extensions`) |

### OverviewMapping

Represents a row in the `brainstorm/00-overview.md` Sessions table.

| Attribute | Type | Source |
|-----------|------|--------|
| brainstorm_number | string | `#` column |
| topic | string | `Topic` column |
| status | string | `Status` column |
| spec_number | string or null | `Spec` column (e.g., `024` or `-`) |

## State Transitions

```
BrainstormDocument.action classification:

  status in {spec-created, abandoned, completed, resolved, decided}
    → action = "attic"

  status in {active, parked, draft, idea}
    AND no spec match
    → action = "keep"

  status in {active, draft, idea}
    AND spec match found
    → inferred_status = "spec-created"
    → action = "attic"

  status is null/unparseable
    → status defaults to "active"
    → action = "keep"
```

## Relationships

- BrainstormDocument 1:0..1 SpecDirectory (matched by slug overlap or overview mapping)
- BrainstormDocument 1:0..1 OverviewMapping (matched by number)
- OverviewMapping 1:0..1 SpecDirectory (via spec_number column)
