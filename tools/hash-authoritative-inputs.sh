#!/usr/bin/env bash

set -euo pipefail

project_root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

if [[ ! -d "$project_root" ]]; then
  printf 'Authoritative input root is missing: %s\n' "$project_root" >&2
  exit 1
fi

command -v python3 >/dev/null 2>&1 || {
  printf 'python3 is required to seal authoritative inputs.\n' >&2
  exit 1
}

# Hash the same path/type/content records in one process. The former shell loop
# spawned sha256sum once per file, which was slow enough for the builder SSH
# endpoint to close an otherwise healthy preflight connection.
python3 - "$project_root" <<'PY'
import fnmatch
import hashlib
import os
import sys

root = os.path.abspath(sys.argv[1])
pruned_roots = {
    "artifacts",
    "backups",
    "evidence",
    "out",
    "outputs",
    "work",
    "vendor/meizu/m86/proprietary",
}


def include(relative: str) -> bool:
    basename = os.path.basename(relative)
    if basename == ".DS_Store" or basename.endswith(".pyc"):
        return False
    if fnmatch.fnmatch(basename, "*.tar") or \
            fnmatch.fnmatch(basename, "*.tar.*") or \
            fnmatch.fnmatch(basename, "*.zip"):
        return False
    if relative.startswith("legacy/"):
        return relative == "legacy/device-meizu-m86-cm14/UPSTREAM.md" or \
            relative.startswith("legacy/device-meizu-m86-cm14/libfprint/")
    return True


entries = []
for directory, dirnames, filenames in os.walk(root, followlinks=False):
    relative_directory = os.path.relpath(directory, root)
    if relative_directory == ".":
        relative_directory = ""

    retained_directories = []
    for dirname in dirnames:
        relative = os.path.join(relative_directory, dirname).replace(os.sep, "/")
        absolute = os.path.join(directory, dirname)
        if dirname in {".git", "__pycache__"} or relative in pruned_roots:
            continue
        if os.path.islink(absolute):
            if include(relative):
                entries.append((relative, absolute, True))
            continue
        retained_directories.append(dirname)
    dirnames[:] = retained_directories

    for filename in filenames:
        relative = os.path.join(relative_directory, filename).replace(os.sep, "/")
        if not include(relative):
            continue
        absolute = os.path.join(directory, filename)
        entries.append((relative, absolute, os.path.islink(absolute)))

manifest_hash = hashlib.sha256()
for relative, absolute, is_link in sorted(entries, key=lambda item: item[0]):
    display_path = "./" + relative
    if is_link:
        record = f"link\t{display_path}\t{os.readlink(absolute)}\n".encode()
    else:
        file_hash = hashlib.sha256()
        with open(absolute, "rb") as source:
            while True:
                block = source.read(1024 * 1024)
                if not block:
                    break
                file_hash.update(block)
        record = f"file\t{display_path}\t{file_hash.hexdigest()}\n".encode()
    manifest_hash.update(record)

print(manifest_hash.hexdigest())
PY
