#!/usr/bin/env python3
"""Validate the flattened device-tree header used by the PRO 5."""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path


FDT_MAGIC = 0xD00DFEED
FDT_HEADER_FORMAT = ">10I"
FDT_HEADER_SIZE = struct.calcsize(FDT_HEADER_FORMAT)


def integer(value: str) -> int:
    try:
        return int(value, 0)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"invalid integer: {value}") from exc


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("dtb", type=Path)
    parser.add_argument("--max-size", type=integer)
    parser.add_argument("--expect-string", action="append", default=[])
    parser.add_argument("--require-no-trailing-data", action="store_true")
    args = parser.parse_args()

    file_size = args.dtb.stat().st_size
    data = args.dtb.read_bytes()
    if len(data) < FDT_HEADER_SIZE:
        print(f"DTB is smaller than its header: {file_size}", file=sys.stderr)
        return 1

    (
        magic,
        total_size,
        structure_offset,
        strings_offset,
        reserve_map_offset,
        version,
        last_compatible_version,
        boot_cpu_id,
        strings_size,
        structure_size,
    ) = struct.unpack_from(FDT_HEADER_FORMAT, data)

    failures: list[str] = []
    if magic != FDT_MAGIC:
        failures.append(f"invalid FDT magic: {magic:#010x}")
    if total_size > file_size or total_size < FDT_HEADER_SIZE:
        failures.append(f"invalid total size: {total_size} for file {file_size}")
    if args.require_no_trailing_data and total_size != file_size:
        failures.append(f"unexpected trailing data: file={file_size} fdt={total_size}")
    if args.max_size is not None and file_size > args.max_size:
        failures.append(f"DTB exceeds limit: {file_size} > {args.max_size}")
    for offset_name, offset in (
        ("structure", structure_offset),
        ("strings", strings_offset),
        ("reserve_map", reserve_map_offset),
    ):
        if offset < FDT_HEADER_SIZE or offset >= total_size:
            failures.append(f"invalid {offset_name} offset: {offset}")
    if structure_offset + structure_size > total_size:
        failures.append("structure block extends past the FDT total size")
    if strings_offset + strings_size > total_size:
        failures.append("strings block extends past the FDT total size")
    for expected_string in args.expect_string:
        if expected_string.encode() not in data[:total_size]:
            failures.append(f"missing expected string: {expected_string!r}")

    print(f"path={args.dtb}")
    print(f"file_size={file_size}")
    print(f"fdt_total_size={total_size}")
    print(f"version={version}")
    print(f"last_compatible_version={last_compatible_version}")
    print(f"boot_cpu_id={boot_cpu_id}")
    print(f"structure_offset={structure_offset}")
    print(f"structure_size={structure_size}")
    print(f"strings_offset={strings_offset}")
    print(f"strings_size={strings_size}")
    print(f"reserve_map_offset={reserve_map_offset}")

    if failures:
        for failure in failures:
            print(f"ERROR: {failure}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
