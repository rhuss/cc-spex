# Data Model: Detach Hardening

## Configuration: spex-detach-config.yml

No schema changes needed. Existing config structure is sufficient:

```yaml
archive:
  path: ""              # Sibling specs repo path (existing)
  auto_commit: true     # Auto-commit to sibling repo (existing)

upstream:
  default_branch: ""    # Override upstream default branch (existing)

detach:
  strip_paths:          # Paths to strip (existing)
    - ".specify"
    - "specs"
    - "brainstorm"
```

## Script Interface: spex-detach.py

### Existing subcommands (unchanged)

- `detach [--branch X] [--base X] [--strip ...]` - Create clean PR branch
- `archive [--target X] [--project X] [--feature X] [--auto-commit]` - Copy specs to sibling repo
- `is-enabled` - Check if extension is active
- `clean-branch-name [--branch X]` - Output `pr/<branch>`

### New subcommand

- `verify --branch <pr-branch> --base <merge-base>` - Verify no SpecKit fingerprints in PR diff

### Modified subcommand

- `archive` gains `--move` flag: delete source after successful copy+commit
- `archive` gains `--include-brainstorm` flag: include `brainstorm/` in archive (currently only archives `.specify/` and `specs/<feature>/`)

### JSON output contracts

**verify** (new):
```json
{
  "clean": true,
  "leaked_files": [],
  "patterns_checked": [".specify/", "specs/", "brainstorm/"]
}
```

On failure (`clean: false`):
```json
{
  "clean": false,
  "leaked_files": ["specs/042-detach-hardening/spec.md", ".specify/extensions.yml"],
  "patterns_checked": [".specify/", "specs/", "brainstorm/"]
}
```

**archive** (extended with move info):
```json
{
  "archive_path": "/path/to/sibling-specs/project/feature",
  "files_copied": 15,
  "committed": true,
  "source_deleted": true
}
```

## File Modification Map

| File | Change Type | FR Coverage |
|------|-------------|-------------|
| `spex/extensions/spex/commands/speckit.spex.finish.md` | Modify (add Phase 3.5) | FR-001, FR-002, FR-003, FR-011 |
| `spex/extensions/spex/commands/speckit.spex.brainstorm.md` | Modify (fix path, line 282) | FR-005 |
| `spex/extensions/spex-detach/scripts/spex-detach.py` | Modify (add verify, move, brainstorm archive) | FR-004, FR-006, FR-007, FR-012 |
| `spex/extensions/spex/commands/speckit.spex.brainstorm.md` | Modify (add sibling repo scan) | FR-009 |
| `spex/extensions/spex-detach/scripts/spex-detach.py` | Modify (add .gitignore check) | FR-008 |
| `spex/docs/help.md` | Modify (document detach workflow) | FR-010 (documentation) |
| `README.md` | Modify (update spex-detach description) | Documentation |
