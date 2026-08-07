#!/usr/bin/env python3
"""Make the pinned TWRP diagnostic's power property inert in-place."""

from __future__ import annotations

import argparse
import hashlib
import struct
from pathlib import Path


ELF_MAGIC = b"\x7fELF"
EM_AARCH64 = 183
OLD_PROPERTY = b"sys.powerctl\0"
NEW_PROPERTY = b"twrp.loghold\0"
REQUIRED_NEIGHBORS = (
    b"/sbin/rebootsystem.sh\0",
    b"reboot,\0",
    b"reboot,recovery\0",
    b"reboot,bootloader\0",
)


def sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("--expect-input-sha256", required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    if args.output.exists():
        raise ValueError(f"refusing to overwrite output: {args.output}")
    if args.output.resolve() == args.input.resolve():
        raise ValueError("output must not overwrite the input ELF")

    payload = args.input.read_bytes()
    input_sha256 = sha256(payload)
    if input_sha256 != args.expect_input_sha256:
        raise ValueError(
            f"{args.input}: expected SHA-256 {args.expect_input_sha256}, "
            f"found {input_sha256}"
        )
    if len(payload) < 20 or payload[:4] != ELF_MAGIC:
        raise ValueError(f"{args.input}: not an ELF file")
    if payload[4] != 2 or payload[5] != 1:
        raise ValueError(f"{args.input}: expected ELF64 little-endian data")
    if struct.unpack_from("<H", payload, 18)[0] != EM_AARCH64:
        raise ValueError(f"{args.input}: expected an AArch64 ELF")
    if len(OLD_PROPERTY) != len(NEW_PROPERTY):
        raise AssertionError("diagnostic property replacement changes ELF size")
    if payload.count(OLD_PROPERTY) != 1:
        raise ValueError("expected exactly one sys.powerctl ELF literal")
    if NEW_PROPERTY in payload:
        raise ValueError("input already contains the inert diagnostic property")
    for neighbor in REQUIRED_NEIGHBORS:
        if payload.count(neighbor) != 1:
            raise ValueError(
                f"expected exactly one neighboring literal: {neighbor!r}"
            )

    offset = payload.index(OLD_PROPERTY)
    rewritten = (
        payload[:offset]
        + NEW_PROPERTY
        + payload[offset + len(OLD_PROPERTY) :]
    )
    if len(rewritten) != len(payload):
        raise AssertionError("rewritten ELF size changed")
    if rewritten.count(OLD_PROPERTY) != 0 or rewritten.count(NEW_PROPERTY) != 1:
        raise AssertionError("rewritten ELF literal inventory is invalid")

    args.output.write_bytes(rewritten)
    print(f"input={args.input}")
    print(f"input_size={len(payload)}")
    print(f"input_sha256={input_sha256}")
    print(f"old_literal={OLD_PROPERTY[:-1].decode()}")
    print(f"new_literal={NEW_PROPERTY[:-1].decode()}")
    print(f"literal_offset={offset}")
    print(f"changed_byte_range={offset}-{offset + len(OLD_PROPERTY) - 2}")
    print(f"output={args.output}")
    print(f"output_size={len(rewritten)}")
    print(f"output_sha256={sha256(rewritten)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
