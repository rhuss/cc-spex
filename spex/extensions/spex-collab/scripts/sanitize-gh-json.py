#!/usr/bin/env python3
"""Sanitize GitHub API JSON output that contains raw control characters.

GitHub API responses (especially PR comment bodies) can contain unescaped
control characters (U+0000-U+001F) inside JSON strings, which causes jq
and Python's json module to reject the input. This script escapes those
characters inside strings while preserving structural JSON whitespace.

Usage: gh api graphql ... | python3 sanitize-gh-json.py | jq .
"""
import sys


def sanitize(raw: bytes) -> bytes:
    result = bytearray()
    in_string = False
    escape_next = False

    for b in raw:
        if escape_next:
            result.append(b)
            escape_next = False
            continue

        if b == 0x5C:  # backslash
            result.append(b)
            if in_string:
                escape_next = True
            continue

        if b == 0x22:  # double quote
            in_string = not in_string
            result.append(b)
            continue

        if in_string and b < 0x20:
            if b == 0x0A:
                result.extend(b"\\n")
            elif b == 0x0D:
                result.extend(b"\\r")
            elif b == 0x09:
                result.extend(b"\\t")
            else:
                result.extend(f"\\u{b:04x}".encode())
        else:
            result.append(b)

    return bytes(result)


raw = sys.stdin.buffer.read()
sys.stdout.buffer.write(sanitize(raw))
