#!/usr/bin/env python3

"""Find byte strings inside regular files in a read-only ext4 image."""

from __future__ import annotations

import argparse
from pathlib import Path, PurePosixPath
import sys

try:
    from ext4 import Directory, File, SymbolicLink, Volume
except ImportError as error:
    raise SystemExit(
        "Unable to import ext4. Add the verified read-only ext4 package to "
        "PYTHONPATH."
    ) from error


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path, help="raw ext4 filesystem image")
    parser.add_argument("needles", nargs="+", help="UTF-8 strings to locate")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    needles = {value: value.encode("utf-8") for value in args.needles}
    if any(not value for value in needles.values()):
        raise SystemExit("Search strings must not be empty.")

    matches: dict[str, list[str]] = {value: [] for value in needles}
    overlap = max(len(value) for value in needles.values()) - 1
    files_scanned = 0
    bytes_scanned = 0

    with args.image.open("rb") as stream:
        volume = Volume(stream)
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
                if isinstance(inode, Directory):
                    if inode_number not in visited:
                        visited.add(inode_number)
                        directories.append((inode, path))
                    continue
                if isinstance(inode, SymbolicLink) or not isinstance(inode, File):
                    continue

                files_scanned += 1
                found_here: set[str] = set()
                tail = b""
                try:
                    with inode.open() as source:
                        while chunk := source.read(1024 * 1024):
                            bytes_scanned += len(chunk)
                            candidate = tail + chunk
                            for label, needle in needles.items():
                                if label not in found_here and needle in candidate:
                                    found_here.add(label)
                            tail = candidate[-overlap:] if overlap else b""
                except (OSError, ValueError) as error:
                    raise SystemExit(f"Unable to read {path}: {error}") from error

                for label in found_here:
                    matches[label].append(str(path))

    missing = False
    for label in args.needles:
        if matches[label]:
            for path in sorted(matches[label]):
                print(f"found\t{label}\t{path}")
        else:
            print(f"missing\t{label}")
            missing = True
    print(f"files\t{files_scanned}")
    print(f"bytes\t{bytes_scanned}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
