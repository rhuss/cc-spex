#!/bin/sh
# spex-detach.sh - Shim that delegates to spex-detach.py via python-resolve.sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESOLVE="$SCRIPT_DIR/hooks/python-resolve.sh"
exec sh "$RESOLVE" "$SCRIPT_DIR/spex-detach.py" "$@"
