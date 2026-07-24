#!/usr/bin/env bash
# Compatibility entry point for the canonical harness-neutral setup workflow.
#
# Usage:
#   spex-init.sh [--refresh] [--integration <claude|codex|opencode>]
#                [--extensions <selection>] [--security <safe|autonomous|yolo>]
#   spex-init.sh --update [setup options]
#   spex-init.sh --clear

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: spex-init.sh [--refresh] [--update] [--clear]
                    [--integration <claude|codex|opencode>]
                    [--extensions <selection>]
                    [--security <safe|autonomous|yolo>]
EOF
  exit 2
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SPEX_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
SETUP_WORKFLOW="$SPEX_ROOT/setup.yml"
DETECT_AGENT="$SCRIPT_DIR/hooks/shared/detect-agent.sh"

MODE="setup"
EXPLICIT_HARNESS=""
EXTENSIONS=""
SECURITY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --refresh|-r)
      [[ "$MODE" == "setup" || "$MODE" == "refresh" ]] || usage
      MODE="refresh"
      shift
      ;;
    --update|-u)
      [[ "$MODE" == "setup" || "$MODE" == "update" ]] || usage
      MODE="update"
      shift
      ;;
    --clear)
      [[ "$MODE" == "setup" ]] || usage
      MODE="clear"
      shift
      ;;
    --integration|--harness)
      [[ $# -ge 2 ]] || usage
      EXPLICIT_HARNESS="$2"
      shift 2
      ;;
    --extensions)
      [[ $# -ge 2 && -n "$2" ]] || usage
      EXTENSIONS="$2"
      shift 2
      ;;
    --security)
      [[ $# -ge 2 ]] || usage
      SECURITY="$2"
      shift 2
      ;;
    --help|-h)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

if [[ "$MODE" == "clear" ]]; then
  [[ -z "$EXPLICIT_HARNESS" && -z "$EXTENSIONS" && -z "$SECURITY" ]] || usage
  STATE_FILE=".specify/.spex-state"
  if [[ -f "$STATE_FILE" ]]; then
    rm -f -- "$STATE_FILE"
    echo "Cleared local Spex workflow state."
  else
    echo "No local Spex workflow state to clear."
  fi
  exit 0
fi

case "$EXPLICIT_HARNESS" in
  ""|claude|codex|opencode) ;;
  *) die "unsupported harness '$EXPLICIT_HARNESS'" ;;
esac
case "$SECURITY" in
  ""|safe|autonomous|yolo) ;;
  *) die "unsupported security profile '$SECURITY'" ;;
esac

resolve_harness() {
  if [[ -n "$EXPLICIT_HARNESS" ]]; then
    printf '%s\n' "$EXPLICIT_HARNESS"
    return 0
  fi

  if [[ -n "${CLAUDE_PROJECT_DIR:-}" && -n "${CODEX_SESSION_ID:-}" ]]; then
    die "conflicting Claude and Codex runtime indicators; pass --integration explicitly"
  fi
  [[ -f "$DETECT_AGENT" ]] || die "harness detector is unavailable: $DETECT_AGENT"

  # Outside an active harness, multiple project configuration roots are
  # ambiguous. An explicit selection is required rather than guessing.
  if [[ -z "${CLAUDE_PROJECT_DIR:-}" && -z "${CODEX_SESSION_ID:-}" ]]; then
    local roots=0
    [[ -d .claude ]] && roots=$((roots + 1))
    [[ -d .codex ]] && roots=$((roots + 1))
    [[ -d .opencode ]] && roots=$((roots + 1))
    if [[ $roots -gt 1 ]]; then
      die "multiple harness configurations found; pass --integration explicitly"
    fi
    if [[ $roots -eq 0 ]]; then
      [[ -f .specify/init-options.json ]] || \
        die "active harness cannot be determined; pass --integration explicitly"
      command -v jq >/dev/null 2>&1 || \
        die "jq is required to resolve the harness from .specify/init-options.json"
      local configured
      configured="$(jq -r '.ai // empty' .specify/init-options.json 2>/dev/null)" || \
        die "cannot read harness identity from .specify/init-options.json"
      case "$configured" in
        claude|codex|opencode) printf '%s\n' "$configured"; return 0 ;;
        *) die "init-options.json does not contain a supported harness identity" ;;
      esac
    fi
  fi

  local detected
  detected="$(sh "$DETECT_AGENT" "$(pwd -P)")" || die "harness detection failed"
  case "$detected" in
    claude|codex|opencode) printf '%s\n' "$detected" ;;
    *) die "harness detector returned unsupported identity '$detected'" ;;
  esac
}

command -v specify >/dev/null 2>&1 || {
  echo "NEED_INSTALL"
  echo "The 'specify' CLI is required. Install specify-cli, then retry." >&2
  exit 2
}
[[ -f "$SETUP_WORKFLOW" ]] || die "canonical setup workflow is unavailable: $SETUP_WORKFLOW"

if [[ "$MODE" == "update" ]]; then
  command -v uv >/dev/null 2>&1 || die "uv is required for --update"
  uv tool install specify-cli --force --from git+https://github.com/github/spec-kit.git
fi

HARNESS="$(resolve_harness)"
WORKFLOW_ARGS=(--input "integration=$HARNESS")
[[ -z "$EXTENSIONS" ]] || WORKFLOW_ARGS+=(--input "extensions=$EXTENSIONS")
[[ -z "$SECURITY" ]] || WORKFLOW_ARGS+=(--input "security=$SECURITY")

# The setup workflow owns initialization, refresh preservation, extensions,
# security configuration, hooks, and harness-specific project guidance.
SPEX_SOURCE="$SPEX_ROOT" specify workflow run "$SETUP_WORKFLOW" "${WORKFLOW_ARGS[@]}"
