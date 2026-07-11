#!/bin/sh
# spex-ship-state.sh - Shim that delegates to spex-ship-state.py
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
for cmd in python3 py python; do
  command -v "$cmd" >/dev/null 2>&1 && exec "$cmd" "$SCRIPT_DIR/spex-ship-state.py" "$@"
done
echo "ERROR: No Python interpreter found (tried python3, py, python)" >&2
exit 1
