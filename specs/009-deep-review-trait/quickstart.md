# Quickstart: Deep-Review Trait

**Feature**: 009-deep-review-trait
**Date**: 2026-03-28

## Enable the Trait

```
/spex:init
# Select "deep-review" when prompted for traits
```

Or enable it directly:

```bash
spex/scripts/spex-traits.sh init --enable "deep-review"
```

The trait works independently. No other traits are required. Optionally enable `teams` for parallel agent execution.

## Usage

### Automatic (with superpowers trait)

When both `superpowers` and `deep-review` are enabled, deep review runs automatically after `/speckit.implement` completes:

1. Superpowers triggers `spex:review-code`
2. Stage 1: spec compliance check runs (must score >= 95%)
3. Stage 2: five review agents analyze the code
4. Fix loop auto-fixes Critical and Important findings (up to 3 rounds)
5. `review-findings.md` is written to the spec directory

### Manual

Run deep review at any time:

```
/spex:review-code
```

With a focus hint:

```
/spex:review-code check mutation safety and resource cleanup
```

### What the Five Agents Check

| Agent | Focus Areas |
|-------|-------------|
| Correctness | Mutation safety, shared references, logic errors, resource cleanup, error paths |
| Architecture & Idioms | Dead code, complexity, divergent duplication, naming, comment accuracy |
| Security | Input validation, injection, secrets, RBAC, CRD/CEL gaps, auth patterns |
| Production Readiness | Goroutine leaks, unbounded channels, memory patterns, operator patterns |
| Test Quality | Coverage gaps, weak assertions, wrong-reason passes, missing edge cases |

### Parallel Mode (with teams trait)

When `teams` is also enabled, all five agents run in parallel via Claude Code Agent Teams. This typically cuts review time in half.

## Output

### Progress Updates

During the review, you'll see per-agent status:

```
Stage 1: Spec compliance... 97% PASS
Stage 2: Multi-perspective review
  Agent 1/5: Correctness... done, 1 finding
  Agent 2/5: Architecture & Idioms... done, 0 findings
  Agent 3/5: Security... done, 2 findings
  Agent 4/5: Production Readiness... done, 1 finding
  Agent 5/5: Test Quality... done, 0 findings
CodeRabbit... done, 1 finding (optional)
Copilot... done, 0 findings (optional)

Merging findings: 5 total, 3 after dedup (2 Critical, 1 Important)
Fix round 1/3...
  Fixed 3 findings
  Re-reviewing modified files...
  0 Critical/Important remaining
Gate: PASS
```

### review-findings.md

Written to the spec directory after each review run (overwrites previous). Contains:

- Review metadata (date, branch, rounds, gate outcome)
- Per-round findings with severity, confidence, file:line, description, source agent, resolution
- Summary with counts by severity

## Severity Guide

| Severity | Blocks Gate? | Fix Loop Action |
|----------|-------------|-----------------|
| Critical | Yes | Auto-fixed |
| Important | Yes | Auto-fixed |
| Minor | No | Listed for awareness |

## Gate Behavior

- **Superpowers context**: Gate pass/fail controls whether implementation proceeds to verification
- **Manual context**: Gate result is advisory. Findings are reported, you decide next steps

## External Review Tools

Two optional external CLIs add independent AI perspectives from different models:

| Tool | Detection | Free Tier | Review Speed |
|------|-----------|-----------|-------------|
| CodeRabbit CLI | `which coderabbit` | Unlimited (rate-limited) | 7-30 min |
| GitHub Copilot CLI | `which copilot` | 50 premium requests/month (shared pool) | ~30 seconds |

If installed, they automatically run alongside the internal agents. If neither is installed, the trait works with internal agents only.

### Setting Up CodeRabbit CLI

1. **Create an account** at [coderabbit.ai](https://www.coderabbit.ai) (free tier available, no credit card required)

2. **Install the CLI:**
   ```bash
   # macOS / Linux (auto-detects platform)
   curl -fsSL https://cli.coderabbit.ai/install.sh | sh
   ```

3. **Authenticate:**
   ```bash
   coderabbit auth login
   # Follow the browser-based OAuth flow to authorize with your CodeRabbit account
   ```

4. **Verify** the setup:
   ```bash
   coderabbit --version
   ```

**Free tier limits:** Unlimited public and private repos, rate-limited to ~2 CLI reviews per hour.

### Setting Up GitHub Copilot CLI

1. **Prerequisites:** A GitHub account with a Copilot subscription. The free tier (Copilot Free) provides 50 premium requests per month, shared across all Copilot features (CLI, chat, agent mode, code review).

2. **Install the CLI:**
   ```bash
   # macOS
   brew install gh
   # Then install Copilot CLI (standalone binary, replaced the old gh-copilot extension)
   # Download from https://github.com/features/copilot or via GitHub releases
   ```

3. **Authenticate:**
   ```bash
   copilot auth login
   # Follow the OAuth browser flow to authorize with your GitHub account
   ```

4. **Verify** the setup:
   ```bash
   copilot --version
   ```

**Free tier limits:** 50 premium requests per month shared across all Copilot usage (CLI, chat, completions, reviews). Overages cost $0.04 per request. Unused requests do not roll over.

### Using Both Tools Together

Both tools can run in the same review session. Their findings are independently parsed and merged with the internal agents. Deduplication applies across all sources, so the same issue found by CodeRabbit and Copilot is consolidated into a single finding with both sources noted.

This is the recommended setup for maximum coverage: the internal agents provide Claude-based depth, CodeRabbit adds cross-file analysis from a different model, and Copilot adds a fast high-precision pass from yet another model.

### Controlling External Tools

By default, external tools run when installed. You can control this per invocation with flags or change the persistent default in config.

**Per-invocation flags:**

```
# Disable all external tools for this review
/spex:review-code --no-external

# Disable only Copilot (keep CodeRabbit)
/spex:review-code --no-copilot

# Disable only CodeRabbit (keep Copilot)
/spex:review-code --no-coderabbit

# Combine flags with hints
/spex:review-code --no-copilot check mutation safety
```

If the persistent default has external tools disabled, use the enable flags instead:

```
# Enable all external tools for this review
/spex:review-code --external

# Enable only CodeRabbit for this review
/spex:review-code --coderabbit
```

**Persistent defaults:**

Edit `external_tools` in `.specify/spex-traits.json` to change the default behavior:

```json
{
  "external_tools": {
    "enabled": true,
    "coderabbit": true,
    "copilot": true
  }
}
```

Set `enabled` to `false` to disable all external tools by default, or set individual tools to `false` to disable them specifically. Per-invocation flags always override these defaults.
