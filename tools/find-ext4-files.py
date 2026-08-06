#!/usr/bin/env python3

"""Find exact basenames in a read-only ext4 filesystem image."""

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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path, help="raw ext4 filesystem image")
    parser.add_argument("names", nargs="+", help="case-sensitive basenames")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    wanted = set(args.names)
    found: dict[str, list[str]] = {name: [] for name in wanted}

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
                if name in wanted:
                    found[name].append(str(path))
                if isinstance(inode, Directory) and inode_number not in visited:
                    visited.add(inode_number)
                    directories.append((inode, path))

    missing = False
    for name in sorted(wanted):
        if found[name]:
            for path in sorted(found[name]):
                print(f"found\t{name}\t{path}")
        else:
            print(f"missing\t{name}")
            missing = True
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
