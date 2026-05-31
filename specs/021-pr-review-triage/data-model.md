# Data Model: PR Review Comment Triage

## Entities

### ReviewThread

Represents a single review thread on a PR, containing one or more comments.

| Field | Type | Source | Description |
|-------|------|--------|-------------|
| `id` | string | GraphQL `node.id` | GitHub node ID (used for resolve/unresolve mutations) |
| `isResolved` | boolean | GraphQL | Whether the thread is resolved |
| `path` | string | GraphQL | File path the thread is attached to |
| `line` | integer | GraphQL | Line number in the diff |
| `comments` | Comment[] | GraphQL nested | Comments in this thread |

**State transitions**: `open` -> `resolved` (by bot self-resolve, skill auto-resolve, or manual resolve)

### Comment

Represents a single comment within a review thread.

| Field | Type | Source | Description |
|-------|------|--------|-------------|
| `id` | integer | REST `id` / GraphQL `databaseId` | Numeric comment ID (used for reply endpoint) |
| `nodeId` | string | GraphQL `id` | GitHub node ID |
| `authorLogin` | string | `user.login` / `author.login` | Author's login name |
| `authorType` | string | `user.type` | `"Bot"` or `"User"` |
| `body` | string | `body` | Comment text content |
| `createdAt` | string (ISO 8601) | `created_at` / `createdAt` | Creation timestamp |
| `inReplyToId` | integer or null | `in_reply_to_id` | Parent comment ID if this is a reply |

### BotProfile

Configuration for a known bot reviewer. Hardcoded with config override.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `login` | string (glob) | - | Login pattern (e.g., `coderabbitai[bot]`) |
| `selfResolves` | boolean | `false` | Whether the bot resolves its own threads when satisfied |
| `autoResolve` | boolean | `false` | Whether the skill should resolve threads after handling |

**Hardcoded profiles**:
- `coderabbitai[bot]`: selfResolves=true, autoResolve=false
- `copilot[bot]`: selfResolves=false, autoResolve=true

**Unknown bots**: selfResolves=false, autoResolve=false (FR-017)

### TriageState

Persistent state for tracking handled comments across invocations.

| Field | Type | Description |
|-------|------|-------------|
| `lastRun` | string (ISO 8601) | Timestamp of last triage run for this PR |
| `comments` | map<commentId, HandledComment> | Per-comment handling state |

### HandledComment

State record for a single handled comment.

| Field | Type | Description |
|-------|------|-------------|
| `handledAt` | string (ISO 8601) | When the comment was handled |
| `action` | enum: `accepted`, `rejected`, `skipped` | What action was taken |
| `ourReplyId` | integer | ID of the reply we posted (for detection) |

## State File Schema

File: `.specify/.pr-triage-state.json`

```json
{
  "<pr_number>": {
    "lastRun": "<ISO 8601>",
    "comments": {
      "<comment_id>": {
        "handledAt": "<ISO 8601>",
        "action": "accepted|rejected|skipped",
        "ourReplyId": <integer>
      }
    }
  }
}
```

## Config File Schema

File: `.specify/collab-config.yml` (extends existing collab config)

```yaml
triage:
  bot-profiles:
    - login: "<bot-login-pattern>"
      self-resolves: <boolean>
      auto-resolve: <boolean>
  overrides:
    "<existing-bot-login>":
      auto-resolve: <boolean>
      self-resolves: <boolean>
```

## Relationships

```text
PR (1) --has--> (N) ReviewThread
ReviewThread (1) --contains--> (N) Comment
Comment (1) --authored-by--> (1) User/Bot
BotProfile (1) --matches--> (N) Comment (via login pattern)
TriageState (1 per PR) --tracks--> (N) HandledComment
```

## Comment Processing Flow

```text
Fetch reviewThreads (GraphQL)
  |
  v
For each thread:
  resolved? --> skip
  |
  v
  First comment author type?
  |
  +--> Bot: assess validity, apply/reject, reply, update state
  |         |
  |         +--> autoResolve profile? --> resolve thread (GraphQL)
  |
  +--> Human: present assessment, await user action, reply if approved
```
