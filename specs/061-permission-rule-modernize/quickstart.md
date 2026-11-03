# Quickstart: Validate Permission Rule Modernization

Prerequisites: `jq`, a shell, this branch checked out. `S=spex/scripts/spex-permissions.sh`.

## 1. Automated tests

```bash
make test-permissions
```

Expected: all PASS, exit 0.

## 2. Migrate a legacy project

```bash
P=$(mktemp -d) && mkdir -p "$P/.claude"
printf '{"permissions":{"defaultMode":"bypassPermissions","allow":["Bash(*)","Read(*)","Edit(*)","Write(*)","Bash(npm test)"]},"hooks":{"Stop":[]}}' > "$P/.claude/settings.json"
sh $S migrate --root "$P"
jq -c .permissions.allow "$P/.claude/settings.json"
```

Expected stderr: `Migrated: .claude/settings.json permissions: Bash(*) -> Bash, Read(*) -> Read, Edit(*) -> Edit, Write(*) -> Write`
Expected list: `["Bash","Read","Edit","Write","Bash(npm test)"]`; `hooks` still present.

## 3. Idempotence

```bash
cksum "$P/.claude/settings.json"; sh $S migrate --root "$P"; cksum "$P/.claude/settings.json"
```

Expected: identical checksums, no output.

## 4. Broken file is untouched

```bash
printf '{broken' > "$P/.claude/settings.local.json"
sh $S migrate --root "$P"; cat "$P/.claude/settings.local.json"
```

Expected: a `WARNING:` naming `.claude/settings.local.json`, content still `{broken`, exit 0.

## 5. Real refresh (manual)

In a project initialized with an older spex YOLO setup, run `/spex:init --refresh`, restart Claude Code (2.1.317 or later), and confirm that no `Allow rule "Read(*)"` style warnings appear.
