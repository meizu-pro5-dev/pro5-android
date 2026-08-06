#!/usr/bin/env python3

"""Extract a proprietary-files list from a read-only ext4 system image."""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path, PurePosixPath
import stat
import sys

try:
    from ext4 import File, SymbolicLink, Volume
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
    normalized = PurePosixPath(entry)
    if not entry or normalized.is_absolute() or ".." in normalized.parts:
        raise ValueError(f"Unsafe proprietary path: {line.rstrip()}")
    return str(normalized)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path, help="raw ext4 system image")
    parser.add_argument("proprietary_list", type=Path)
    parser.add_argument(
        "output",
        type=Path,
        help="expanded-ROM root; files are written below output/system",
    )
    return parser.parse_args()


def extract_file(inode: File, destination: Path) -> tuple[str, int]:
    temporary = destination.with_name(f".{destination.name}.part")
    digest = hashlib.sha256()
    size = 0
    try:
        with inode.open() as source, temporary.open("wb") as target:
            while chunk := source.read(1024 * 1024):
                target.write(chunk)
                digest.update(chunk)
                size += len(chunk)
        os.chmod(temporary, stat.S_IMODE(int(inode.i_mode)))
        os.replace(temporary, destination)
    finally:
        if temporary.exists():
            temporary.unlink()
    return digest.hexdigest(), size


def main() -> int:
    args = parse_args()
    output = args.output.resolve()
    if output == Path(output.anchor):
        raise SystemExit(f"Refusing unsafe output root: {output}")

    entries: list[str] = []
    for line in args.proprietary_list.read_text(encoding="utf-8").splitlines():
        path = source_path(line)
        if path is not None:
            entries.append(path)

    if len(entries) != len(set(entries)):
        raise SystemExit("The proprietary list contains duplicate source paths.")

    system_root = output / "system"
    system_root.mkdir(parents=True, exist_ok=True)
    records: list[tuple[str, str, int]] = []

    with args.image.open("rb") as stream:
        volume = Volume(stream)
        for relative in entries:
            inode = volume.inode_at(f"/{relative}")
            destination = system_root.joinpath(*PurePosixPath(relative).parts)
            destination.parent.mkdir(parents=True, exist_ok=True)
            if destination.is_symlink() or destination.exists():
                destination.unlink()

            if isinstance(inode, File):
                digest, size = extract_file(inode, destination)
                records.append((digest, relative, size))
            elif isinstance(inode, SymbolicLink):
                link_target = os.fsdecode(inode.readlink())
                destination.symlink_to(link_target)
                digest = hashlib.sha256(os.fsencode(link_target)).hexdigest()
                records.append((digest, relative, len(link_target)))
            else:
                raise SystemExit(f"Unsupported inode type for {relative}")

    manifest = output / "PROPRIETARY_SHA256SUMS"
    manifest.write_text(
        "".join(f"{digest}  system/{path}\n" for digest, path, _ in records),
        encoding="utf-8",
    )
    total_bytes = sum(size for _, _, size in records)
    print(f"files\t{len(records)}")
    print(f"bytes\t{total_bytes}")
    print(f"manifest\t{manifest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
