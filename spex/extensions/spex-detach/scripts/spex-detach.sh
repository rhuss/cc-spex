#!/bin/sh
# spex-detach.sh - Shim that delegates to spex-detach.py
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
for cmd in python3 py python; do
  command -v "$cmd" >/dev/null 2>&1 && exec "$cmd" "$SCRIPT_DIR/spex-detach.py" "$@"
done
echo "ERROR: No Python interpreter found (tried python3, py, python)" >&2
exit 1
