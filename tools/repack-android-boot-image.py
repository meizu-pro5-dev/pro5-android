#!/usr/bin/env python3
"""Repack a classic Android boot image while preserving its board header."""

from __future__ import annotations

import argparse
import hashlib
import struct
from dataclasses import dataclass
from pathlib import Path


BOOT_MAGIC = b"ANDROID!"
HEADER_FORMAT = "<8s10I16s512s32s1024s"
HEADER_SIZE = struct.calcsize(HEADER_FORMAT)


def align(value: int, page_size: int) -> int:
    return (value + page_size - 1) // page_size * page_size


def pad(value: bytes, alignment: int) -> bytes:
    return value + b"\0" * (align(len(value), alignment) - len(value))


@dataclass(frozen=True)
class BootImage:
    kernel: bytes
    ramdisk: bytes
    second: bytes
    dt: bytes
    kernel_addr: int
    ramdisk_addr: int
    second_addr: int
    tags_addr: int
    page_size: int
    os_version_or_unused: int
    name: bytes
    cmdline: bytes
    image_id: bytes
    extra_cmdline: bytes

    @classmethod
    def read(cls, path: Path) -> "BootImage":
        raw = path.read_bytes()
        if len(raw) < HEADER_SIZE:
            raise ValueError(f"{path}: truncated boot image header")

        unpacked = struct.unpack_from(HEADER_FORMAT, raw)
        if unpacked[0] != BOOT_MAGIC:
            raise ValueError(f"{path}: invalid boot image magic")

        (
            kernel_size,
            kernel_addr,
            ramdisk_size,
            ramdisk_addr,
            second_size,
            second_addr,
            tags_addr,
            page_size,
            dt_size,
            os_version_or_unused,
        ) = unpacked[1:11]
        if page_size < HEADER_SIZE or page_size & (page_size - 1):
            raise ValueError(f"{path}: invalid page size {page_size}")

        kernel_offset = page_size
        ramdisk_offset = kernel_offset + align(kernel_size, page_size)
        second_offset = ramdisk_offset + align(ramdisk_size, page_size)
        dt_offset = second_offset + align(second_size, page_size)
        end_offset = dt_offset + align(dt_size, page_size)
        if end_offset > len(raw):
            raise ValueError(
                f"{path}: truncated payload ({len(raw)} < {end_offset})"
            )

        return cls(
            kernel=raw[kernel_offset : kernel_offset + kernel_size],
            ramdisk=raw[ramdisk_offset : ramdisk_offset + ramdisk_size],
            second=raw[second_offset : second_offset + second_size],
            dt=raw[dt_offset : dt_offset + dt_size],
            kernel_addr=kernel_addr,
            ramdisk_addr=ramdisk_addr,
            second_addr=second_addr,
            tags_addr=tags_addr,
            page_size=page_size,
            os_version_or_unused=os_version_or_unused,
            name=unpacked[11],
            cmdline=unpacked[12],
            image_id=unpacked[13],
            extra_cmdline=unpacked[14],
        )


def boot_image_id(
    kernel: bytes,
    ramdisk: bytes,
    second: bytes,
    dt: bytes,
    scheme: str,
) -> bytes:
    """Return a classic mkbootimg SHA-1 identifier.

    The PRO 5's known-working recovery uses ``conditional-dtb``: kernel,
    ramdisk, and second always contribute a length, while DT contributes only
    when present.  The Android 9 build tree's mkbootimg uses ``all-sections``
    and also contributes the zero DT length when no DT is embedded.
    """

    digest = hashlib.sha1()
    for payload in (kernel, ramdisk, second):
        digest.update(payload)
        digest.update(struct.pack("<I", len(payload)))
    if dt or scheme == "all-sections":
        digest.update(dt)
        digest.update(struct.pack("<I", len(dt)))
    return digest.digest().ljust(32, b"\0")


def detect_image_id_scheme(image: BootImage) -> str:
    for scheme in ("conditional-dtb", "all-sections"):
        expected = boot_image_id(
            image.kernel, image.ramdisk, image.second, image.dt, scheme
        )
        if image.image_id == expected:
            return scheme
    raise ValueError(
        "base image ID does not match the supported conditional-dtb or "
        "all-sections mkbootimg algorithms; pass --image-id-scheme explicitly"
    )


def replacement(path: Path | None, original: bytes) -> bytes:
    return original if path is None else path.read_bytes()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument("base", type=Path)
    parser.add_argument("--kernel", type=Path)
    parser.add_argument("--ramdisk", type=Path)
    parser.add_argument("--second", type=Path)
    parser.add_argument("--dt", type=Path)
    parser.add_argument(
        "--image-id-scheme",
        choices=("auto", "conditional-dtb", "all-sections"),
        default="auto",
    )
    parser.add_argument("--output", required=True, type=Path)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    if args.output.resolve() == args.base.resolve():
        raise ValueError("output must not overwrite the base image")

    base = BootImage.read(args.base)
    kernel = replacement(args.kernel, base.kernel)
    ramdisk = replacement(args.ramdisk, base.ramdisk)
    second = replacement(args.second, base.second)
    dt = replacement(args.dt, base.dt)
    image_id_scheme = args.image_id_scheme
    if image_id_scheme == "auto":
        image_id_scheme = detect_image_id_scheme(base)
    image_id = boot_image_id(
        kernel, ramdisk, second, dt, image_id_scheme
    )

    header = struct.pack(
        HEADER_FORMAT,
        BOOT_MAGIC,
        len(kernel),
        base.kernel_addr,
        len(ramdisk),
        base.ramdisk_addr,
        len(second),
        base.second_addr,
        base.tags_addr,
        base.page_size,
        len(dt),
        base.os_version_or_unused,
        base.name,
        base.cmdline,
        image_id,
        base.extra_cmdline,
    )
    output = b"".join(
        pad(component, base.page_size)
        for component in (header, kernel, ramdisk, second, dt)
    )
    args.output.write_bytes(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
