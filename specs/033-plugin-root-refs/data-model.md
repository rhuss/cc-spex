# Data Model: Replace find calls with plugin root references

This feature has no data model changes. It modifies only the path resolution mechanism in markdown command files. No entities, attributes, or relationships are created, modified, or removed.

## Entities (unchanged, reference only)

- **Extension Command File**: Markdown file containing AI agent instructions. Location: `spex/extensions/<ext>/commands/*.md`. Modified by this feature (content changes only).
- **Plugin Root Path**: String value injected by context hook as `<plugin-root>` in the `<spex-context>` system reminder. Not modified.
- **Helper Script**: Shell script under `spex/scripts/`. Not modified.
