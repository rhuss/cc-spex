# Plugin Schema Extensions

This document describes the schema used in `spex/.claude-plugin/plugin.json` for the cc-spex plugin.

## Standard Claude Code Fields

The plugin uses all standard Claude Code plugin.json fields as specified in the [official documentation](https://code.claude.com/docs/en/plugins-reference):

### Required Fields

- **name**: `"cc-spex"` - Unique plugin identifier (kebab-case)
- **version**: `"1.0.0"` - Semantic version string
- **description**: Brief description of plugin purpose

### Metadata Fields

- **author**: Object with name and email
  ```json
  {
    "name": "Roland Huss",
    "email": "rhuss@redhat.com"
  }
  ```

- **license**: `"MIT"` - License identifier
- **repository**: Object with type and URL
- **homepage**: Plugin documentation URL
- **bugs**: Issue tracker URL
- **keywords**: Array of discovery tags

### Component Fields

- **skills**: Array of skill definitions
  ```json
  {
    "name": "skill-name",
    "path": "skills/skill-name/SKILL.md",
    "description": "What the skill does",
    "category": "workflow|core|spex-specific|modified-core"
  }
  ```

## Custom Extension Fields

The following fields extend the standard schema to provide additional functionality and documentation. Claude Code ignores unknown fields, so these are safe to include without breaking plugin functionality.

### configuration

**Type**: Object containing JSON Schema

**Purpose**: Defines user-configurable settings that can be set in project-level `.claude/settings.json`

**Structure**:
```json
{
  "configuration": {
    "schema": {
      "type": "object",
      "properties": {
        "spex": {
          "type": "object",
          "properties": {
            "auto_update_spec": { ... },
            "spec_kit": { ... },
            "constitution": { ... },
            "specs": { ... }
          }
        }
      }
    }
  }
}
```

**Available Settings**:

#### spex.auto_update_spec
Controls automatic spec updates:
- `enabled` (boolean, default: true) - Enable automatic spec updates
- `threshold` (enum: "none"|"minor"|"moderate", default: "minor") - Update threshold
- `notify` (boolean, default: true) - Notify user when auto-updates occur

#### spex.spec_kit
Spec-kit CLI integration:
- `enabled` (boolean, default: true) - Use spec-kit CLI if available
- `path` (string, default: "specify") - Path to spec-kit binary

#### spex.constitution
Constitution file settings:
- `path` (string, default: ".specify/memory/constitution.md") - Path to constitution file
- `required` (boolean, default: false) - Require constitution before spec work

#### spex.specs
Specification directory settings:
- `directory` (string, default: "specs/features") - Directory for feature specifications
- `format` (string, default: "markdown") - Specification file format

**Usage in .claude/settings.json**:
```json
{
  "spex": {
    "auto_update_spec": {
      "enabled": true,
      "threshold": "minor"
    },
    "spec_kit": {
      "enabled": true,
      "path": "/usr/local/bin/specify"
    }
  }
}
```

### dependencies

**Type**: Object with optional array

**Purpose**: Documents optional external tools that enhance functionality

**Structure**:
```json
{
  "dependencies": {
    "optional": [
      {
        "name": "spec-kit",
        "url": "https://github.com/github/spec-kit",
        "description": "Enhanced spec management tooling (recommended but not required)"
      }
    ]
  }
}
```

**Fields**:
- `optional`: Array of optional dependencies
  - `name`: Dependency name
  - `url`: Where to get it
  - `description`: What it provides

**Note**: Plugin works without these dependencies but may have enhanced features when they're installed.

### acknowledgements

**Type**: Array of objects

**Purpose**: Credits to upstream projects and authors whose work this plugin builds upon

**Structure**:
```json
{
  "acknowledgements": [
    {
      "project": "superpowers",
      "url": "https://github.com/obra/superpowers",
      "author": "Jesse Vincent",
      "description": "Process discipline and workflow enforcement foundation"
    },
    {
      "project": "spec-kit",
      "url": "https://github.com/github/spec-kit",
      "author": "GitHub",
      "description": "Specification-driven development workflows and tooling"
    }
  ]
}
```

**Fields**:
- `project`: Project name
- `url`: Project URL
- `author`: Project author/organization
- `description`: What we use from this project

### bundled_resources

**Type**: Object with resource categories

**Purpose**: Documents files bundled with the plugin

**Note**: Templates, scripts, and spec-kit commands are NOT bundled. They are provided by spec-kit CLI via `specify init` in each project.

**Structure**:
```json
{
  "bundled_resources": {
    "commands": {
      "path": "commands",
      "description": "Slash commands for spex workflows (spec-kit commands installed via specify init)",
      "files": [
        "brainstorm.md",
        "spec.md",
        "implement.md",
        "evolve.md",
        "review-spec.md",
        "review-code.md",
        "constitution.md"
      ]
    }
  }
}
```

**Resource Categories**:
- `commands`: Slash command implementations

**Each category has**:
- `path`: Directory path relative to plugin root
- `description`: What these resources provide
- `files`: Array of filenames in the directory

**External Resources** (not bundled):
- Templates: Provided by `specify init` in `.specify/templates/`
- Scripts: Provided by `specify init` in `.specify/scripts/`
- Spec-kit commands: Provided by `specify init` in `.claude/skills/speckit-*`
- Source of truth: spec-kit repository

## Skill Categories

The plugin uses a custom `category` field in skill definitions to organize skills:

- **core**: Entry skills that establish mandatory workflows
- **workflow**: Main spex workflow skills (brainstorm, spec, implement, evolve)
- **modified-core**: Superpowers skills extended with spex functionality
- **spex-specific**: Skills unique to specification-driven development

## Schema Validation

While Claude Code doesn't validate custom fields, this plugin follows these principles:

1. **Backward compatibility**: Custom fields don't interfere with Claude Code's operation
2. **Documentation**: All custom fields are documented here
3. **JSON validity**: The entire plugin.json must be valid JSON
4. **Semantic meaning**: Custom fields provide value to developers and users

## Future Considerations

As Claude Code evolves, these custom fields may:
- Become standard in future Claude Code releases
- Be used by plugin development tools
- Inform best practices for plugin metadata

For now, they serve as documentation and potential extension points for tooling.

## References

- [Claude Code Plugins Reference](https://code.claude.com/docs/en/plugins-reference)
- [JSON Schema Specification](https://json-schema.org/)
- [Semantic Versioning](https://semver.org/)
