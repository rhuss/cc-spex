# Quickstart: Validate the Detach Fix

Prerequisites: `specify` CLI, `jq`, `yq`, `git`, run from the cc-spex repo root.

## Automated

```bash
make test-detach            # verify/ensure + config save/restore
make test-apply-extensions  # stealth output from the selection step
make test-workflow-setup    # end-to-end: setup, refresh, config survives
```

All three must pass.

## Manual (scratch repo)

```bash
T=$(mktemp -d) && git -C "$T" init -q && cd "$T"
SPEX_SOURCE=<cc-spex>/spex specify workflow run <cc-spex>/spex/setup.yml \
  -i integration=claude -i extensions=spex-detach -i security=safe
<cc-spex>/spex/scripts/spex-setup-report.sh
```

Expected: `Enabled: spex-detach`, `Stealth mode: exclude entries written: .specify/ specs/ brainstorm/`, `Stealth mode: active (verified: ...)`.

```bash
git check-ignore specs/x/spec.md .specify/spex.json .specify/memory/constitution.md brainstorm/x.md
```

Expected: all four paths printed.

Config survives refresh:

```bash
yq -i '.archive.path = "/tmp/x-specs"' .specify/extensions/spex-detach/spex-detach-config.yml
shasum .specify/extensions/spex-detach/spex-detach-config.yml
SPEX_SOURCE=<cc-spex>/spex specify workflow run <cc-spex>/spex/setup.yml
shasum .specify/extensions/spex-detach/spex-detach-config.yml   # same hash
```

Repair:

```bash
sed -i '' '/^specs\/$/d' "$(git rev-parse --git-common-dir)/info/exclude"
SPEX_SOURCE=<cc-spex>/spex specify workflow run <cc-spex>/spex/setup.yml
<cc-spex>/spex/scripts/spex-setup-report.sh   # "Repaired stealth mode: added specs/"
grep -c '^specs/$' "$(git rev-parse --git-common-dir)/info/exclude"   # 1
```
