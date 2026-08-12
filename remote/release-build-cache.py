#!/usr/bin/env python3
"""Release clean build-output page cache without changing file contents."""

import argparse
import os
import stat
import sys


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("root")
    parser.add_argument("--min-size", type=int, default=1024 * 1024)
    args = parser.parse_args()

    root = os.path.abspath(args.root)
    if not os.path.isdir(root):
        print("cache_release_files=0")
        print("cache_release_bytes=0")
        print("cache_release_errors=0")
        return 0
    if not hasattr(os, "posix_fadvise"):
        print("POSIX_FADV_DONTNEED is unavailable on this builder.", file=sys.stderr)
        return 1

    advised_files = 0
    advised_bytes = 0
    errors = 0
    open_flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0)
    if hasattr(os, "O_NOFOLLOW"):
        open_flags |= os.O_NOFOLLOW

    for directory, dirnames, filenames in os.walk(root, followlinks=False):
        dirnames[:] = [
            name for name in dirnames
            if not os.path.islink(os.path.join(directory, name))
        ]
        for filename in filenames:
            path = os.path.join(directory, filename)
            try:
                metadata = os.stat(path, follow_symlinks=False)
                if not stat.S_ISREG(metadata.st_mode) or \
                        metadata.st_size < args.min_size:
                    continue
                descriptor = os.open(path, open_flags)
                try:
                    os.posix_fadvise(
                        descriptor, 0, 0, os.POSIX_FADV_DONTNEED
                    )
                finally:
                    os.close(descriptor)
                advised_files += 1
                advised_bytes += metadata.st_size
            except OSError:
                errors += 1

    print(f"cache_release_files={advised_files}")
    print(f"cache_release_bytes={advised_bytes}")
    print(f"cache_release_errors={errors}")
    return 0 if errors == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
