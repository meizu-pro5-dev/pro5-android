#!/usr/bin/env python3
"""Copy, replace, or delete entries in compressed newc recovery ramdisks."""

from __future__ import annotations

import argparse
import dataclasses
import gzip
import hashlib
import lzma
import stat
import struct
from dataclasses import dataclass
from pathlib import Path


BOOT_MAGIC = b"ANDROID!"
BOOT_HEADER_FORMAT = "<8s10I16s512s32s1024s"
BOOT_HEADER_SIZE = struct.calcsize(BOOT_HEADER_FORMAT)
NEWC_HEADER_SIZE = 110


def align(value: int, boundary: int) -> int:
    return (value + boundary - 1) // boundary * boundary


def sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def checked_file(path: Path, expected_sha256: str | None) -> bytes:
    payload = path.read_bytes()
    actual_sha256 = sha256(payload)
    if expected_sha256 is not None and actual_sha256 != expected_sha256:
        raise ValueError(
            f"{path}: expected SHA-256 {expected_sha256}, found {actual_sha256}"
        )
    return payload


def ramdisk_from_boot_image(payload: bytes, source: Path) -> bytes:
    if len(payload) < BOOT_HEADER_SIZE:
        raise ValueError(f"{source}: truncated classic boot header")
    unpacked = struct.unpack_from(BOOT_HEADER_FORMAT, payload)
    if unpacked[0] != BOOT_MAGIC:
        raise ValueError(f"{source}: invalid classic boot magic")

    kernel_size = unpacked[1]
    ramdisk_size = unpacked[3]
    page_size = unpacked[8]
    if page_size < BOOT_HEADER_SIZE or page_size & (page_size - 1):
        raise ValueError(f"{source}: invalid page size {page_size}")

    ramdisk_offset = page_size + align(kernel_size, page_size)
    ramdisk_end = ramdisk_offset + ramdisk_size
    if ramdisk_end > len(payload):
        raise ValueError(f"{source}: truncated ramdisk component")
    return payload[ramdisk_offset:ramdisk_end]


def decompressed_ramdisk(payload: bytes) -> tuple[bytes, str]:
    if payload.startswith(b"\x1f\x8b"):
        return gzip.decompress(payload), "gzip"
    if payload.startswith((b"\x5d\x00\x00", b"\xfd7zXZ\x00")):
        return lzma.decompress(payload), "lzma"
    if payload.startswith((b"070701", b"070702")):
        return payload, "none"
    raise ValueError(f"unsupported ramdisk magic: {payload[:8].hex()}")


@dataclass(frozen=True)
class NewcEntry:
    magic: bytes
    hex_upper: bool
    inode: int
    mode: int
    uid: int
    gid: int
    links: int
    mtime: int
    dev_major: int
    dev_minor: int
    rdev_major: int
    rdev_minor: int
    name: bytes
    data: bytes

    @property
    def path(self) -> str:
        return self.name.decode("utf-8")

    def header(self) -> bytes:
        checksum = sum(self.data) & 0xFFFFFFFF if self.magic == b"070702" else 0
        fields = (
            self.inode,
            self.mode,
            self.uid,
            self.gid,
            self.links,
            self.mtime,
            len(self.data),
            self.dev_major,
            self.dev_minor,
            self.rdev_major,
            self.rdev_minor,
            len(self.name) + 1,
            checksum,
        )
        field_format = "08X" if self.hex_upper else "08x"
        return self.magic + b"".join(
            format(field, field_format).encode() for field in fields
        )


@dataclass(frozen=True)
class NewcArchive:
    entries: tuple[NewcEntry, ...]
    tail: bytes

    @classmethod
    def parse(cls, payload: bytes) -> "NewcArchive":
        entries: list[NewcEntry] = []
        paths: set[str] = set()
        offset = 0

        while True:
            header_end = offset + NEWC_HEADER_SIZE
            if header_end > len(payload):
                raise ValueError("truncated newc header")
            header = payload[offset:header_end]
            magic = header[:6]
            if magic not in (b"070701", b"070702"):
                raise ValueError(
                    f"unsupported newc magic at offset {offset}: {magic!r}"
                )
            try:
                fields = tuple(
                    int(header[field_offset : field_offset + 8], 16)
                    for field_offset in range(6, NEWC_HEADER_SIZE, 8)
                )
            except ValueError as error:
                raise ValueError(f"invalid newc header at offset {offset}") from error

            file_size = fields[6]
            name_size = fields[11]
            if name_size < 1:
                raise ValueError(f"invalid newc name size at offset {offset}")
            name_start = header_end
            name_end = name_start + name_size
            if name_end > len(payload) or payload[name_end - 1] != 0:
                raise ValueError(f"truncated newc name at offset {offset}")
            name = payload[name_start : name_end - 1]
            try:
                path = name.decode("utf-8")
            except UnicodeDecodeError as error:
                raise ValueError(f"non-UTF-8 newc name at offset {offset}") from error

            data_start = align(name_end, 4)
            data_end = data_start + file_size
            if data_end > len(payload):
                raise ValueError(f"truncated newc data for {path!r}")
            data = payload[data_start:data_end]
            offset = align(data_end, 4)

            entry = NewcEntry(
                magic=magic,
                hex_upper=any(byte in b"ABCDEF" for byte in header[6:]),
                inode=fields[0],
                mode=fields[1],
                uid=fields[2],
                gid=fields[3],
                links=fields[4],
                mtime=fields[5],
                dev_major=fields[7],
                dev_minor=fields[8],
                rdev_major=fields[9],
                rdev_minor=fields[10],
                name=name,
                data=data,
            )
            entries.append(entry)
            if path == "TRAILER!!!":
                return cls(tuple(entries), payload[offset:])
            if path in paths:
                raise ValueError(f"duplicate newc path: {path!r}")
            paths.add(path)

    def serialize(self) -> bytes:
        output = bytearray()
        for entry in self.entries:
            output.extend(entry.header())
            output.extend(entry.name)
            output.append(0)
            output.extend(b"\0" * (align(len(output), 4) - len(output)))
            output.extend(entry.data)
            output.extend(b"\0" * (align(len(output), 4) - len(output)))
        output.extend(self.tail)
        return bytes(output)


def safe_archive_path(value: str) -> str:
    path = value.removeprefix("/").removeprefix("./")
    parts = path.split("/")
    if not path or any(part in ("", ".", "..") for part in parts):
        raise argparse.ArgumentTypeError(f"invalid archive path: {value!r}")
    return path


def replacement_argument(value: str) -> tuple[str, Path]:
    archive_path, separator, source_path = value.partition("=")
    if not separator or not source_path:
        raise argparse.ArgumentTypeError(
            "replacement must use RAMDISK_PATH=HOST_FILE"
        )
    return safe_archive_path(archive_path), Path(source_path)


def copied_archive(
    base: NewcArchive, donor: NewcArchive, paths: list[str]
) -> tuple[NewcArchive, list[tuple[str, str]]]:
    base_entries = list(base.entries)
    donor_by_path = {entry.path: entry for entry in donor.entries}
    base_index = {entry.path: index for index, entry in enumerate(base_entries)}
    trailer_index = base_index.get("TRAILER!!!")
    if trailer_index is None:
        raise ValueError("base newc archive has no trailer")

    next_inode = max(entry.inode for entry in base_entries) + 1
    actions: list[tuple[str, str]] = []
    for path in paths:
        donor_entry = donor_by_path.get(path)
        if donor_entry is None:
            raise ValueError(f"donor newc path is absent: {path!r}")
        target_index = base_index.get(path)
        if target_index is None:
            added_entry = dataclasses.replace(donor_entry, inode=next_inode)
            next_inode += 1
            base_entries.insert(trailer_index, added_entry)
            base_index = {
                entry.path: index for index, entry in enumerate(base_entries)
            }
            trailer_index += 1
            actions.append((path, "added"))
            continue

        target_entry = base_entries[target_index]
        base_entries[target_index] = dataclasses.replace(
            target_entry,
            mode=donor_entry.mode,
            uid=donor_entry.uid,
            gid=donor_entry.gid,
            links=donor_entry.links,
            mtime=donor_entry.mtime,
            rdev_major=donor_entry.rdev_major,
            rdev_minor=donor_entry.rdev_minor,
            data=donor_entry.data,
        )
        actions.append((path, "replaced"))

    return NewcArchive(tuple(base_entries), base.tail), actions


def deleted_archive(
    base: NewcArchive, paths: list[str]
) -> tuple[NewcArchive, list[tuple[str, str]]]:
    delete_paths = set(paths)
    if "TRAILER!!!" in delete_paths:
        raise ValueError("refusing to delete the newc trailer")

    entries_by_path = {entry.path: entry for entry in base.entries}
    for path in paths:
        entry = entries_by_path.get(path)
        if entry is None:
            raise ValueError(f"base newc path is absent: {path!r}")
        # Legacy Android mkbootfs archives may encode zero links and reuse
        # inode zero for every entry. Only a positive multi-link count carries
        # hard-link semantics that deletion could corrupt.
        if entry.links > 1:
            raise ValueError(
                f"refusing to delete multiply-linked newc path: {path!r}"
            )
        prefix = f"{path}/"
        surviving_children = [
            candidate
            for candidate in entries_by_path
            if candidate.startswith(prefix) and candidate not in delete_paths
        ]
        if surviving_children:
            raise ValueError(
                f"refusing to delete nonempty newc directory: {path!r}"
            )

    remaining = tuple(
        entry for entry in base.entries if entry.path not in delete_paths
    )
    return NewcArchive(remaining, base.tail), [
        (path, "removed") for path in paths
    ]


def data_replaced_archive(
    base: NewcArchive, replacements: list[tuple[str, Path]]
) -> tuple[NewcArchive, list[tuple[str, Path, int, str]]]:
    base_entries = list(base.entries)
    base_index = {entry.path: index for index, entry in enumerate(base_entries)}
    actions: list[tuple[str, Path, int, str]] = []

    for path, source in replacements:
        target_index = base_index.get(path)
        if target_index is None:
            raise ValueError(f"base newc path is absent: {path!r}")
        target_entry = base_entries[target_index]
        if path == "TRAILER!!!" or not stat.S_ISREG(target_entry.mode):
            raise ValueError(
                f"replacement target is not a regular newc file: {path!r}"
            )
        if not source.is_file():
            raise ValueError(f"replacement source is not a file: {source}")

        payload = source.read_bytes()
        base_entries[target_index] = dataclasses.replace(
            target_entry, data=payload
        )
        actions.append((path, source, len(payload), sha256(payload)))

    return NewcArchive(tuple(base_entries), base.tail), actions


def compressed_ramdisk(payload: bytes, compression: str) -> bytes:
    if compression == "none":
        return payload
    if compression == "gzip":
        return gzip.compress(payload, compresslevel=9, mtime=0)
    filters = [
        {
            "id": lzma.FILTER_LZMA1,
            "dict_size": 8 * 1024 * 1024,
            "lc": 3,
            "lp": 0,
            "pb": 2,
            "mode": lzma.MODE_NORMAL,
            "nice_len": 128,
            "mf": lzma.MF_BT4,
        }
    ]
    return lzma.compress(payload, format=lzma.FORMAT_ALONE, filters=filters)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    base_source = parser.add_mutually_exclusive_group(required=True)
    base_source.add_argument("--base-ramdisk", type=Path)
    base_source.add_argument("--base-boot-image", type=Path)
    donor_source = parser.add_mutually_exclusive_group()
    donor_source.add_argument("--donor-ramdisk", type=Path)
    donor_source.add_argument("--donor-boot-image", type=Path)
    parser.add_argument("--expect-base-sha256")
    parser.add_argument("--expect-donor-sha256")
    parser.add_argument(
        "--copy",
        action="append",
        default=[],
        type=safe_archive_path,
        metavar="RAMDISK_PATH",
    )
    parser.add_argument(
        "--delete",
        action="append",
        default=[],
        type=safe_archive_path,
        metavar="RAMDISK_PATH",
    )
    parser.add_argument(
        "--replace-data",
        action="append",
        default=[],
        type=replacement_argument,
        metavar="RAMDISK_PATH=HOST_FILE",
        help="replace only file data while preserving the base cpio metadata",
    )
    parser.add_argument(
        "--compression", choices=("gzip", "lzma", "none"), required=True
    )
    parser.add_argument("--output", type=Path, required=True)
    return parser


def input_ramdisk(
    ramdisk_path: Path | None,
    boot_image_path: Path | None,
    expected_sha256: str | None,
) -> tuple[bytes, Path, str]:
    source = ramdisk_path if ramdisk_path is not None else boot_image_path
    assert source is not None
    container = checked_file(source, expected_sha256)
    if boot_image_path is not None:
        return ramdisk_from_boot_image(container, source), source, sha256(container)
    return container, source, sha256(container)


def main() -> int:
    args = build_parser().parse_args()
    if args.output.exists():
        raise ValueError(f"refusing to overwrite output: {args.output}")
    if len(set(args.copy)) != len(args.copy):
        raise ValueError("copy list contains duplicate paths")
    if len(set(args.delete)) != len(args.delete):
        raise ValueError("delete list contains duplicate paths")
    replace_paths = [path for path, _source in args.replace_data]
    if len(set(replace_paths)) != len(replace_paths):
        raise ValueError("replace-data list contains duplicate paths")
    overlap = (
        (set(args.copy) & set(args.delete))
        | (set(args.copy) & set(replace_paths))
        | (set(args.delete) & set(replace_paths))
    )
    if overlap:
        raise ValueError(
            "paths cannot have multiple mutation actions: "
            f"{sorted(overlap)!r}"
        )
    if not args.copy and not args.delete and not args.replace_data:
        raise ValueError(
            "at least one --copy, --delete, or --replace-data action is required"
        )
    if args.copy and args.donor_ramdisk is None and args.donor_boot_image is None:
        raise ValueError("--copy requires a donor ramdisk or boot image")
    if (
        args.expect_donor_sha256 is not None
        and args.donor_ramdisk is None
        and args.donor_boot_image is None
    ):
        raise ValueError("--expect-donor-sha256 requires a donor source")

    base_ramdisk, base_source, base_container_sha256 = input_ramdisk(
        args.base_ramdisk, args.base_boot_image, args.expect_base_sha256
    )
    base_cpio, base_compression = decompressed_ramdisk(base_ramdisk)
    base_archive = NewcArchive.parse(base_cpio)

    if base_archive.serialize() != base_cpio:
        raise ValueError("base newc archive does not round-trip byte-identically")

    donor_details: tuple[bytes, Path, str, bytes, str, NewcArchive] | None = None
    if args.donor_ramdisk is not None or args.donor_boot_image is not None:
        donor_ramdisk, donor_path, donor_container_sha256 = input_ramdisk(
            args.donor_ramdisk, args.donor_boot_image, args.expect_donor_sha256
        )
        donor_cpio, donor_compression = decompressed_ramdisk(donor_ramdisk)
        donor_archive = NewcArchive.parse(donor_cpio)
        if donor_archive.serialize() != donor_cpio:
            raise ValueError(
                "donor newc archive does not round-trip byte-identically"
            )
        donor_details = (
            donor_ramdisk,
            donor_path,
            donor_container_sha256,
            donor_cpio,
            donor_compression,
            donor_archive,
        )

    copy_actions: list[tuple[str, str]] = []
    rewritten_archive = base_archive
    if args.copy:
        assert donor_details is not None
        rewritten_archive, copy_actions = copied_archive(
            rewritten_archive, donor_details[5], args.copy
        )
    rewritten_archive, replace_actions = data_replaced_archive(
        rewritten_archive, args.replace_data
    )
    rewritten_archive, delete_actions = deleted_archive(
        rewritten_archive, args.delete
    )
    rewritten_cpio = rewritten_archive.serialize()
    rewritten_ramdisk = compressed_ramdisk(rewritten_cpio, args.compression)
    args.output.write_bytes(rewritten_ramdisk)

    print(f"base_source={base_source}")
    print(f"base_container_sha256={base_container_sha256}")
    print(f"base_ramdisk_compression={base_compression}")
    print(f"base_ramdisk_size={len(base_ramdisk)}")
    print(f"base_ramdisk_sha256={sha256(base_ramdisk)}")
    print(f"base_cpio_size={len(base_cpio)}")
    print(f"base_cpio_sha256={sha256(base_cpio)}")
    if donor_details is not None:
        (
            donor_ramdisk,
            donor_path,
            donor_container_sha256,
            donor_cpio,
            donor_compression,
            _,
        ) = donor_details
        print(f"donor_source={donor_path}")
        print(f"donor_container_sha256={donor_container_sha256}")
        print(f"donor_ramdisk_compression={donor_compression}")
        print(f"donor_cpio_size={len(donor_cpio)}")
        print(f"donor_cpio_sha256={sha256(donor_cpio)}")
    for path, action in copy_actions:
        print(f"copy[{path}]={action}")
    for path, source, size, digest in replace_actions:
        print(f"replace_data[{path}].source={source}")
        print(f"replace_data[{path}].size={size}")
        print(f"replace_data[{path}].sha256={digest}")
    for path, action in delete_actions:
        print(f"delete[{path}]={action}")
    print(f"output={args.output}")
    print(f"output_compression={args.compression}")
    print(f"output_ramdisk_size={len(rewritten_ramdisk)}")
    print(f"output_ramdisk_sha256={sha256(rewritten_ramdisk)}")
    print(f"output_cpio_size={len(rewritten_cpio)}")
    print(f"output_cpio_sha256={sha256(rewritten_cpio)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
