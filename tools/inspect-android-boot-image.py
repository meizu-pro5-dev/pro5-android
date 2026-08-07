#!/usr/bin/env python3
"""Inspect and optionally gate a classic Android boot image header."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import lzma
import struct
import sys
from pathlib import Path


BOOT_MAGIC = b"ANDROID!"
HEADER_FORMAT = "<8s10I16s512s32s1024s"
HEADER_SIZE = struct.calcsize(HEADER_FORMAT)


def integer(value: str) -> int:
    try:
        return int(value, 0)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"invalid integer: {value}") from exc


def align(value: int, page_size: int) -> int:
    return (value + page_size - 1) // page_size * page_size


def boot_image_id(
    kernel: bytes,
    ramdisk: bytes,
    second: bytes,
    dt: bytes,
    include_empty_dt: bool,
) -> bytes:
    digest = hashlib.sha1()
    for payload in (kernel, ramdisk, second):
        digest.update(payload)
        digest.update(struct.pack("<I", len(payload)))
    if dt or include_empty_dt:
        digest.update(dt)
        digest.update(struct.pack("<I", len(dt)))
    return digest.digest().ljust(32, b"\0")


def decode_c_string(value: bytes) -> str:
    return value.split(b"\0", 1)[0].decode("utf-8", "replace")


def parse_archive_path(value: str) -> str:
    archive_path = value.removeprefix("/").removeprefix("./")
    path_parts = archive_path.split("/")
    if not archive_path or any(part in ("", ".", "..") for part in path_parts):
        raise argparse.ArgumentTypeError("expected a safe RAMDISK_PATH")
    return archive_path


def parse_hash_expectation(value: str) -> tuple[str, str]:
    try:
        archive_path, expected_hash = value.rsplit("=", 1)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(
            "expected RAMDISK_PATH=SHA256"
        ) from exc

    archive_path = parse_archive_path(archive_path)
    expected_hash = expected_hash.lower()
    if len(expected_hash) != 64 or any(
        character not in "0123456789abcdef" for character in expected_hash
    ):
        raise argparse.ArgumentTypeError(
            "expected a safe RAMDISK_PATH and a 64-character SHA-256"
        )
    return archive_path, expected_hash


def parse_directory_file_expectation(value: str) -> tuple[str, tuple[str, ...]]:
    try:
        archive_path, file_list = value.rsplit("=", 1)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(
            "expected RAMDISK_DIR=FILE[,FILE...]"
        ) from exc

    archive_path = parse_archive_path(archive_path)
    file_names = file_list.split(",")
    if not file_names or any(
        not file_name
        or "/" in file_name
        or file_name in (".", "..")
        for file_name in file_names
    ):
        raise argparse.ArgumentTypeError(
            "expected direct, safe file names after RAMDISK_DIR="
        )
    if len(set(file_names)) != len(file_names):
        raise argparse.ArgumentTypeError("directory file list contains duplicates")
    return archive_path, tuple(sorted(file_names))


def parse_newc_archive(archive: bytes) -> dict[str, bytes]:
    entries: dict[str, bytes] = {}
    offset = 0

    while True:
        header_end = offset + 110
        if header_end > len(archive):
            raise ValueError("truncated newc header")
        header = archive[offset:header_end]
        if header[:6] not in (b"070701", b"070702"):
            raise ValueError(
                f"unsupported cpio magic at offset {offset}: {header[:6]!r}"
            )
        try:
            fields = [
                int(header[field_offset : field_offset + 8], 16)
                for field_offset in range(6, 110, 8)
            ]
        except ValueError as exc:
            raise ValueError(f"invalid newc header at offset {offset}") from exc

        file_size = fields[6]
        name_size = fields[11]
        if name_size < 1:
            raise ValueError(f"invalid cpio name size at offset {offset}")

        name_start = header_end
        name_end = name_start + name_size
        if name_end > len(archive) or archive[name_end - 1] != 0:
            raise ValueError(f"truncated or unterminated cpio name at offset {offset}")
        try:
            name = archive[name_start : name_end - 1].decode("utf-8")
        except UnicodeDecodeError as exc:
            raise ValueError(f"non-UTF-8 cpio name at offset {offset}") from exc

        data_start = align(name_end, 4)
        data_end = data_start + file_size
        if data_end > len(archive):
            raise ValueError(f"truncated cpio payload for {name!r}")
        if name == "TRAILER!!!":
            return entries

        normalized_name = name.removeprefix("./").removeprefix("/")
        if normalized_name in entries:
            raise ValueError(f"duplicate cpio entry: {normalized_name!r}")
        entries[normalized_name] = archive[data_start:data_end]
        offset = align(data_end, 4)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument("image", type=Path)
    parser.add_argument("--expect-page-size", type=integer)
    parser.add_argument("--expect-kernel-addr", type=integer)
    parser.add_argument("--expect-ramdisk-addr", type=integer)
    parser.add_argument("--expect-second-addr", type=integer)
    parser.add_argument("--expect-tags-addr", type=integer)
    parser.add_argument("--expect-second-size", type=integer)
    parser.add_argument("--expect-dt-size", type=integer)
    parser.add_argument("--expect-valid-image-id", action="store_true")
    parser.add_argument("--expect-empty-cmdline", action="store_true")
    parser.add_argument(
        "--expect-ramdisk-compression",
        choices=("gzip", "lzma", "xz", "lz4", "unknown"),
    )
    parser.add_argument(
        "--expect-ramdisk-elf",
        action="append",
        default=[],
        type=parse_archive_path,
        metavar="RAMDISK_PATH",
        help="require an ELF file inside a supported compressed newc ramdisk",
    )
    parser.add_argument(
        "--expect-ramdisk-file",
        action="append",
        default=[],
        type=parse_archive_path,
        metavar="RAMDISK_PATH",
        help="require a file inside a supported compressed newc ramdisk",
    )
    parser.add_argument(
        "--expect-ramdisk-file-sha256",
        action="append",
        default=[],
        type=parse_hash_expectation,
        metavar="RAMDISK_PATH=SHA256",
        help=(
            "require a file and hash inside a supported compressed newc ramdisk"
        ),
    )
    parser.add_argument(
        "--expect-ramdisk-directory-files",
        action="append",
        default=[],
        type=parse_directory_file_expectation,
        metavar="RAMDISK_DIR=FILE[,FILE...]",
        help="require the exact direct-file inventory for a ramdisk directory",
    )
    parser.add_argument("--max-size", type=integer)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    image_size = args.image.stat().st_size
    with args.image.open("rb") as image_file:
        header = image_file.read(HEADER_SIZE)

    if len(header) != HEADER_SIZE:
        print(
            f"image is too small for the {HEADER_SIZE}-byte v0 header: "
            f"{image_size}",
            file=sys.stderr,
        )
        return 1

    unpacked = struct.unpack(HEADER_FORMAT, header)
    magic = unpacked[0]
    if magic != BOOT_MAGIC:
        print(f"invalid boot magic: {magic!r}", file=sys.stderr)
        return 1

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
    name = decode_c_string(unpacked[11])
    cmdline = decode_c_string(unpacked[12]) + decode_c_string(unpacked[14])
    image_id = unpacked[13]

    failures: list[str] = []
    ramdisk_magic = b""
    ramdisk_compression = "unknown"
    kernel_payload = b""
    ramdisk_payload = b""
    second_payload = b""
    dt_payload = b""
    conditional_dtb_image_id = b""
    all_sections_image_id = b""
    image_id_scheme = "unavailable"
    if page_size < 512 or page_size & (page_size - 1):
        failures.append(f"invalid page size: {page_size}")
        packed_size = 0
    else:
        packed_size = align(HEADER_SIZE, page_size)
        for component_size in (kernel_size, ramdisk_size, second_size, dt_size):
            packed_size += align(component_size, page_size)
        if image_size < packed_size:
            failures.append(
                f"truncated payload: file={image_size} calculated={packed_size}"
            )
        ramdisk_offset = align(HEADER_SIZE, page_size) + align(
            kernel_size, page_size
        )
        kernel_offset = align(HEADER_SIZE, page_size)
        second_offset = ramdisk_offset + align(ramdisk_size, page_size)
        dt_offset = second_offset + align(second_size, page_size)
        with args.image.open("rb") as image_file:
            image_file.seek(kernel_offset)
            kernel_payload = image_file.read(kernel_size)
            image_file.seek(ramdisk_offset)
            ramdisk_payload = image_file.read(ramdisk_size)
            image_file.seek(second_offset)
            second_payload = image_file.read(second_size)
            image_file.seek(dt_offset)
            dt_payload = image_file.read(dt_size)
        conditional_dtb_image_id = boot_image_id(
            kernel_payload,
            ramdisk_payload,
            second_payload,
            dt_payload,
            include_empty_dt=False,
        )
        all_sections_image_id = boot_image_id(
            kernel_payload,
            ramdisk_payload,
            second_payload,
            dt_payload,
            include_empty_dt=True,
        )
        if image_id == conditional_dtb_image_id:
            image_id_scheme = "conditional-dtb"
        elif image_id == all_sections_image_id:
            image_id_scheme = "all-sections"
        else:
            image_id_scheme = "unrecognized"
        if args.expect_valid_image_id and image_id_scheme == "unrecognized":
            failures.append(
                "unrecognized image ID: header="
                f"{image_id.hex()} conditional-dtb="
                f"{conditional_dtb_image_id.hex()} all-sections="
                f"{all_sections_image_id.hex()}"
            )
        ramdisk_magic = ramdisk_payload[:8]
        if ramdisk_magic.startswith(b"\x1f\x8b"):
            ramdisk_compression = "gzip"
        elif ramdisk_magic.startswith(b"\x5d\x00\x00"):
            ramdisk_compression = "lzma"
        elif ramdisk_magic.startswith(b"\xfd7zXZ\x00"):
            ramdisk_compression = "xz"
        elif ramdisk_magic.startswith((b"\x04\x22\x4d\x18", b"\x02\x21\x4c\x18")):
            ramdisk_compression = "lz4"

    expected_fields = (
        ("page_size", page_size, args.expect_page_size),
        ("kernel_addr", kernel_addr, args.expect_kernel_addr),
        ("ramdisk_addr", ramdisk_addr, args.expect_ramdisk_addr),
        ("second_addr", second_addr, args.expect_second_addr),
        ("tags_addr", tags_addr, args.expect_tags_addr),
        ("second_size", second_size, args.expect_second_size),
        ("dt_size", dt_size, args.expect_dt_size),
    )
    for field_name, actual, expected in expected_fields:
        if expected is not None and actual != expected:
            failures.append(
                f"{field_name}: expected {expected:#x}, found {actual:#x}"
            )
    if args.expect_empty_cmdline and cmdline:
        failures.append(f"expected an empty header cmdline, found {cmdline!r}")
    if (
        args.expect_ramdisk_compression is not None
        and ramdisk_compression != args.expect_ramdisk_compression
    ):
        failures.append(
            "ramdisk compression: expected "
            f"{args.expect_ramdisk_compression}, found {ramdisk_compression}"
        )
    if args.max_size is not None and image_size > args.max_size:
        failures.append(f"image exceeds limit: {image_size} > {args.max_size}")

    inspected_ramdisk_files: list[tuple[str, int, str]] = []
    requested_ramdisk_files: dict[str, str | None] = {
        archive_path: None for archive_path in args.expect_ramdisk_file
    }
    requested_ramdisk_files.update(
        {archive_path: None for archive_path in args.expect_ramdisk_elf}
    )
    requested_ramdisk_files.update(dict(args.expect_ramdisk_file_sha256))
    requested_ramdisk_directories = dict(args.expect_ramdisk_directory_files)
    inspected_ramdisk_directories: list[tuple[str, tuple[str, ...]]] = []
    if requested_ramdisk_files or requested_ramdisk_directories:
        if ramdisk_compression not in ("gzip", "lzma", "xz"):
            failures.append(
                "RAM disk file inspection requires gzip, LZMA, or XZ"
            )
        else:
            try:
                if ramdisk_compression == "gzip":
                    ramdisk_archive = gzip.decompress(ramdisk_payload)
                else:
                    ramdisk_archive = lzma.decompress(ramdisk_payload)
                ramdisk_entries = parse_newc_archive(ramdisk_archive)
            except (OSError, lzma.LZMAError, ValueError) as error:
                failures.append(
                    f"unable to parse {ramdisk_compression}/newc ramdisk: {error}"
                )
            else:
                for archive_path, expected_hash in requested_ramdisk_files.items():
                    content = ramdisk_entries.get(archive_path)
                    if content is None:
                        failures.append(f"ramdisk file is absent: {archive_path}")
                        continue
                    actual_hash = hashlib.sha256(content).hexdigest()
                    inspected_ramdisk_files.append(
                        (archive_path, len(content), actual_hash)
                    )
                    if (
                        archive_path in args.expect_ramdisk_elf
                        and not content.startswith(b"\x7fELF")
                    ):
                        failures.append(f"ramdisk file is not ELF: {archive_path}")
                    if expected_hash is not None and actual_hash != expected_hash:
                        failures.append(
                            f"ramdisk file hash for {archive_path}: expected "
                            f"{expected_hash}, found {actual_hash}"
                        )
                for archive_path, expected_files in (
                    requested_ramdisk_directories.items()
                ):
                    prefix = f"{archive_path}/"
                    actual_files = tuple(
                        sorted(
                            entry_name.removeprefix(prefix)
                            for entry_name in ramdisk_entries
                            if entry_name.startswith(prefix)
                            and "/" not in entry_name.removeprefix(prefix)
                        )
                    )
                    inspected_ramdisk_directories.append(
                        (archive_path, actual_files)
                    )
                    if actual_files != expected_files:
                        failures.append(
                            f"ramdisk directory files for {archive_path}: "
                            f"expected {','.join(expected_files)}, found "
                            f"{','.join(actual_files)}"
                        )

    print(f"path={args.image}")
    print(f"file_size={image_size}")
    print(f"kernel_size={kernel_size}")
    print(f"kernel_sha256={hashlib.sha256(kernel_payload).hexdigest()}")
    print(f"kernel_addr={kernel_addr:#010x}")
    print(f"ramdisk_size={ramdisk_size}")
    print(f"ramdisk_sha256={hashlib.sha256(ramdisk_payload).hexdigest()}")
    print(f"ramdisk_addr={ramdisk_addr:#010x}")
    print(f"second_size={second_size}")
    print(f"second_sha256={hashlib.sha256(second_payload).hexdigest()}")
    print(f"second_addr={second_addr:#010x}")
    print(f"tags_addr={tags_addr:#010x}")
    print(f"page_size={page_size}")
    print(f"dt_size={dt_size}")
    print(f"dt_sha256={hashlib.sha256(dt_payload).hexdigest()}")
    print(f"os_version_or_unused={os_version_or_unused:#010x}")
    print(f"name={name!r}")
    print(f"cmdline={cmdline!r}")
    print(f"image_id={image_id.hex()}")
    print(f"image_id_scheme={image_id_scheme}")
    print(f"calculated_image_id_conditional_dtb={conditional_dtb_image_id.hex()}")
    print(f"calculated_image_id_all_sections={all_sections_image_id.hex()}")
    print(f"ramdisk_magic={ramdisk_magic.hex()}")
    print(f"ramdisk_compression={ramdisk_compression}")
    for archive_path, file_size, actual_hash in inspected_ramdisk_files:
        print(f"ramdisk_file[{archive_path}].size={file_size}")
        print(f"ramdisk_file[{archive_path}].sha256={actual_hash}")
    for archive_path, actual_files in inspected_ramdisk_directories:
        print(
            f"ramdisk_directory[{archive_path}].files="
            f"{','.join(actual_files)}"
        )
    print(f"calculated_payload_size={packed_size}")
    print(f"trailing_size={image_size - packed_size if packed_size else 0}")

    if failures:
        for failure in failures:
            print(f"ERROR: {failure}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
