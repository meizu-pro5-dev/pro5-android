#!/usr/bin/env bash

set -euo pipefail

dev_null=/dev/null
if [[ ! -c "$dev_null" ]]; then
  printf 'Builder invariant failed: %s is not a character device.\n' \
    "$dev_null" >&2
  printf 'Restore it as character device 1:3 before starting Android tools.\n' \
    >&2
  exit 1
fi

dev_null_rdev="$(stat -Lc '%t:%T' "$dev_null")"
if [[ "$dev_null_rdev" != 1:3 ]]; then
  printf 'Builder invariant failed: %s has rdev %s, expected 1:3.\n' \
    "$dev_null" "$dev_null_rdev" >&2
  exit 1
fi

if [[ ! -r "$dev_null" || ! -w "$dev_null" ]]; then
  printf 'Builder invariant failed: %s is not readable and writable.\n' \
    "$dev_null" >&2
  exit 1
fi
