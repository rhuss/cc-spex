# Data Model: Update Check on Init

## Entities

### VERSION File

- **Location**: Repository root (`VERSION`)
- **Format**: Single line, no trailing newline required
- **Content**: Semver version string
- **Valid values**: `MAJOR.MINOR.PATCH` or `MAJOR.MINOR.PATCH-dev`
- **Examples**: `5.9.0`, `5.9.1-dev`, `6.0.0`
- **Lifecycle**: Set to release version before tagging, bumped to next-dev after release

### marketplace.json Version Field

- **Location**: `.claude-plugin/marketplace.json` → `.plugins[0].version`
- **Format**: Semver string (no `v` prefix)
- **Relationship**: Derived from VERSION file during `make release`
- **Sync rule**: Updated atomically with VERSION during release; may diverge during development (marketplace.json keeps last release version, VERSION has `-dev`)

### GitHub Release Response

- **Source**: `GET https://api.github.com/repos/rhuss/cc-spex/releases/latest`
- **Key fields**:
  - `tag_name`: Version tag string (e.g., `v5.9.0`) with `v` prefix
  - `body`: Release notes markdown, may contain `BREAKING:` prefixed lines
- **Transient**: Not stored, fetched on each init run

## State Transitions

```
VERSION lifecycle during development:

  [release 5.9.0]
       |
  VERSION = "5.9.0"
       |
  make release
       |
  ├── marketplace.json.version = "5.9.0"
  ├── git tag v5.9.0
  ├── git push
  └── VERSION = "5.9.1-dev"
       |
  [development continues]
       |
  [prepare release 5.9.1]
       |
  VERSION = "5.9.1"  (manually remove -dev)
       |
  make release
       |
  └── ... (cycle repeats)
```
