# Quickstart: Replace Traits with Spec-Kit Extensions

## What Changed

The spex traits/overlays system is replaced by spec-kit's native extension mechanism.

**Before** (traits):
```bash
# Enable a trait
spex-traits.sh enable superpowers
# Traits inject overlay content into spec-kit skill files via sentinel markers
```

**After** (extensions):
```bash
# Extensions installed during init
specify extension add spex/extensions/spex-gates --dev
# Extensions register commands and hooks natively
specify extension enable spex-gates
specify extension disable spex-gates
```

## Extension Layout

Each extension lives in `spex/extensions/{id}/`:

```
spex/extensions/spex-gates/
  extension.yml                    # Manifest (schema, commands, hooks)
  commands/
    speckit.spex-gates.review-spec.md
    speckit.spex-gates.review-plan.md
    speckit.spex-gates.review-code.md
    speckit.spex-gates.verify.md
    speckit.spex-gates.stamp.md
```

## Init Flow (New)

```bash
# 1. spec-kit core init (unchanged)
specify init --here --ai claude --force

# 2. Install bundled extensions (replaces apply_traits)
for ext in spex spex-gates spex-worktrees spex-teams spex-deep-review; do
  specify extension add "spex/extensions/$ext" --dev
done

# 3. Old traits config detected? Print warning
# "spex-traits.json detected. Traits have been replaced by extensions."
```

## Creating an Extension Command

1. Create `extension.yml` with manifest fields (see contracts/extension-manifest.yml)
2. Create command markdown file in `commands/` with frontmatter
3. Register hooks in manifest (if lifecycle integration needed)
4. Install with `specify extension add <path> --dev`

## Key Differences from Traits

| Aspect | Traits (old) | Extensions (new) |
|--------|-------------|------------------|
| Storage | `spex/overlays/<trait>/` | `spex/extensions/<ext>/` |
| Config | `.specify/spex-traits.json` | `.specify/extensions/.registry` |
| Mechanism | Content injection via sentinels | Commands + lifecycle hooks |
| Enable/disable | `spex-traits.sh enable/disable` | `specify extension enable/disable` |
| Agent support | Claude Code only | Any agent (via spec-kit detection) |
| Ship pipeline | `_ship-guard` overlays | Commands check `.spex-state` themselves |
| Teams routing | Hook pre-emption | Standalone command, ship routes |

## Verification

```bash
# Run integration tests
make release

# Verify extensions installed
specify extension list

# Verify hooks registered
cat .specify/extensions.yml
```
