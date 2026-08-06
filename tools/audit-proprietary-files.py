#!/usr/bin/env python3

"""Check a LineageOS proprietary-files list against a read-only ext4 image."""

from __future__ import annotations

import argparse
from pathlib import Path, PurePosixPath
import sys

try:
    from ext4 import Directory, Volume
except ImportError as error:
    raise SystemExit(
        "Unable to import ext4. Add the verified read-only ext4 package to "
        "PYTHONPATH."
    ) from error


def source_path(line: str) -> str | None:
    entry = line.strip()
    if not entry or entry.startswith("#"):
        return None

    entry = entry.lstrip("-")
    entry = entry.split("|", 1)[0]
    entry = entry.split(";", 1)[0]
    entry = entry.split(":", 1)[0]
    entry = entry.removeprefix("/")
    entry = entry.removeprefix("system/")
    if not entry:
        return None

    normalized = PurePosixPath("/", entry)
    if ".." in normalized.parts:
        raise ValueError(f"Unsafe proprietary path: {line.rstrip()}")
    return str(normalized)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path, help="raw ext4 system image")
    parser.add_argument("proprietary_list", type=Path)
    parser.add_argument(
        "--show-present",
        action="store_true",
        help="print present entries as well as missing entries",
    )
    parser.add_argument(
        "--show-relocated",
        action="store_true",
        help="search the image for matching basenames of missing entries",
    )
    return parser.parse_args()


def relocated_candidates(volume: Volume, missing: list[str]) -> list[tuple[str, str]]:
    wanted = {PurePosixPath(path).name for path in missing}
    missing_by_name: dict[str, list[str]] = {}
    for path in missing:
        missing_by_name.setdefault(PurePosixPath(path).name, []).append(path)

    candidates: list[tuple[str, str]] = []
    directories: list[tuple[Directory, PurePosixPath]] = [
        (volume.root, PurePosixPath("/"))
    ]
    visited = {volume.root.i_no}
    while directories:
        directory, parent = directories.pop()
        for dirent, _ in directory.opendir():
            name = dirent.name_str
            if name in {".", ".."}:
                continue

            inode_number = int(dirent.inode)
            inode = volume.inodes[inode_number]
            path = parent / name
            if name in wanted:
                for original in missing_by_name[name]:
                    candidates.append((original, str(path)))
            if isinstance(inode, Directory) and inode_number not in visited:
                visited.add(inode_number)
                directories.append((inode, path))

    return sorted(candidates)


def main() -> int:
    args = parse_args()
    entries: list[str] = []
    for line in args.proprietary_list.read_text(encoding="utf-8").splitlines():
        path = source_path(line)
        if path is not None:
            entries.append(path)

    duplicates = len(entries) - len(set(entries))
    missing: list[str] = []
    with args.image.open("rb") as stream:
        volume = Volume(stream)
        for path in entries:
            try:
                volume.inode_at(path)
            except FileNotFoundError:
                missing.append(path)
                print(f"missing\t{path}")
            else:
                if args.show_present:
                    print(f"present\t{path}")

        if args.show_relocated and missing:
            for original, candidate in relocated_candidates(volume, missing):
                print(f"candidate\t{original}\t{candidate}")

        print(f"image_uuid\t{volume.uuid}")

    print(f"entries\t{len(entries)}")
    print(f"unique_entries\t{len(set(entries))}")
    print(f"duplicates\t{duplicates}")
    print(f"present\t{len(entries) - len(missing)}")
    print(f"missing\t{len(missing)}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
