# Quickstart: Harden Deep Review Process

## What Changes

Four enhancements to the deep review extension, all in `speckit.spex-deep-review.run.md`:

1. **Fix loop runs tests** after each fix round (new Step 7.6)
2. **Test-quality agent** cross-references spec acceptance scenarios against test verification methods
3. **Correctness agent** detects swallowed errors from fallible operations
4. **Review hints injection** from `.specify/review-hints.md` into all agent prompts

## Files Modified

| File | Change |
|------|--------|
| `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md` | Add Step 7.6 (test execution), enhance agent prompts, add review hints injection |
| `spex/extensions/spex-deep-review/config-template.yml` | Add `test_command` and `test_timeout_seconds` keys |

## How to Use

### Test suite in fix loop

Automatic. When the fix loop runs, it detects your project's test command and runs it after applying fixes. No configuration needed for standard project layouts (Makefile, go.mod, package.json, pyproject.toml).

To override the test command:
```yaml
# .specify/extensions/spex-deep-review/deep-review-config.yml
test_command: "make integration-test"
test_timeout_seconds: 600
```

### Review hints

Create `.specify/review-hints.md` in your project with framework-specific patterns:

```markdown
## controller-runtime Gotchas

- `client.Patch(ctx, obj, patch)` and `client.Update(ctx, obj)` refresh `obj`
  from the API server response. Any in-memory mutations to `obj` that haven't
  been persisted will be lost.
```

The content is injected into every review agent's prompt automatically.

### Spec-anchored test validation

Automatic when a spec is available. Write acceptance scenarios with explicit verification methods:

```markdown
**Given** a card fetch succeeds, **When** the reconcile completes,
**Then** confirm `status.card` is populated via `kubectl get agentruntime -o yaml`
```

The test-quality agent will check that corresponding tests use the same verification method.

## Verification

Run a deep review on any project to verify:
1. Fix loop output includes "Running test suite..." line
2. Test failures appear as Critical findings with `source_agent: test-suite`
3. Review hints appear in agent prompts when `.specify/review-hints.md` exists
4. Test-quality agent flags verification method mismatches
