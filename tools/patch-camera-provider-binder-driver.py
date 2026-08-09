#!/usr/bin/env python3
"""Retarget the legacy camera provider's libbinder driver without relinking."""

from __future__ import annotations

import argparse
from pathlib import Path


OLD_DRIVER = b"/dev/vndbinder\0"
NEW_DRIVER = b"/dev/binder\0".ljust(len(OLD_DRIVER), b"\0")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    image = args.input.read_bytes()
    count = image.count(OLD_DRIVER)
    if count != 1:
        raise SystemExit(
            f"expected one {OLD_DRIVER[:-1]!r} string, found {count}"
        )

    patched = image.replace(OLD_DRIVER, NEW_DRIVER, 1)
    if len(patched) != len(image):
        raise SystemExit("patched provider size changed")
    if OLD_DRIVER in patched:
        raise SystemExit("old binder driver remains in patched provider")

    args.output.write_bytes(patched)
    args.output.chmod(args.input.stat().st_mode)


if __name__ == "__main__":
    main()
