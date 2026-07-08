#!/bin/sh
# spex-ship-state.sh - Shim that delegates to spex-ship-state.py via python-resolve.sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESOLVE="$SCRIPT_DIR/../../../scripts/hooks/python-resolve.sh"
exec sh "$RESOLVE" "$SCRIPT_DIR/spex-ship-state.py" "$@"
