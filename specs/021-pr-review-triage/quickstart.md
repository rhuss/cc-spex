# Quickstart: PR Review Comment Triage

## Usage

```bash
# Triage all review comments on the current branch's PR
/speckit-spex-collab-triage

# Triage a specific PR
/speckit-spex-collab-triage --pr 142

# Loop mode: re-run every 5 minutes
/loop 5m /speckit-spex-collab-triage
```

## What It Does

1. Detects the open PR for the current branch
2. Fetches all review threads via the GitHub API
3. Skips resolved threads
4. **Bot comments** (autonomous): assesses each suggestion, applies valid fixes, rejects invalid ones with justification, posts replies, optionally auto-resolves threads
5. **Human comments** (interactive): presents each comment with an assessment verdict (agree/disagree/partial) and proposed reply for user approval
6. Batches all applied fixes into a single commit and pushes

## Configuration

Bot behavior is configured via hardcoded profiles (CodeRabbit, Copilot) with optional overrides in `.specify/collab-config.yml`:

```yaml
triage:
  bot-profiles:
    - login: "my-custom-bot[bot]"
      self-resolves: false
      auto-resolve: true
```

## State Tracking

Handled comments are tracked in `.specify/.pr-triage-state.json` (gitignored). This prevents re-processing on repeated invocations. Delete the file to force a fresh triage pass.

## Reply Signature

All replies include an invisible `<!-- spex-triage -->` marker for detection on subsequent runs.
