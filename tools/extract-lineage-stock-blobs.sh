#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -ne 3 ]]; then
  printf 'Usage: %s <lineage-source-root> <stock-ota-or-image-or-dir> <stock-dump>\n' \
    "${0##*/}" >&2
  exit 2
fi

source_root="$(realpath "$1")"
stock_source="$(realpath "$2")"
stock_dump="$(realpath -m "$3")"
device_root="$source_root/device/meizu/m86"
vendor_root="$source_root/vendor/meizu/m86"
vendor_proprietary="$vendor_root/proprietary"
extract_utils="$source_root/tools/extract-utils"

for required in \
  "$source_root/.repo" \
  "$device_root/extract-files.sh" \
  "$device_root/setup-makefiles.sh" \
  "$device_root/proprietary-files.txt" \
  "$extract_utils/extract_utils.sh" \
  "$stock_source"; do
  if [[ ! -e "$required" ]]; then
    printf 'Missing extraction input: %s\n' "$required" >&2
    exit 1
  fi
done

case "$vendor_proprietary" in
  "$source_root"/vendor/meizu/m86/proprietary) ;;
  *)
    printf 'Refusing unexpected vendor destination: %s\n' "$vendor_proprietary" >&2
    exit 1
    ;;
esac

work_parent="$(dirname "$stock_dump")"
mkdir -p "$work_parent"
work_root="$(mktemp -d "$work_parent/.m86-blob-extract.XXXXXX")"
shadow_root="$work_root/lineage-shadow"
helper_tmp="$work_root/helper-tmp"
expected_list="$work_root/expected-paths.txt"
actual_list="$work_root/actual-paths.txt"
new_stock_dump="$work_root/new-stock-dump"
old_vendor="$work_root/old-vendor-proprietary"
old_stock_dump="$work_root/old-stock-dump"
commit_started=false
commit_complete=false

cleanup() {
  if [[ "$commit_started" == true && "$commit_complete" != true ]]; then
    if [[ -d "$old_vendor" ]]; then
      if [[ -d "$vendor_proprietary" ]]; then
        mv "$vendor_proprietary" "$work_root/failed-new-vendor"
      fi
      mv "$old_vendor" "$vendor_proprietary"
    fi
    if [[ -d "$old_stock_dump" ]]; then
      if [[ -d "$stock_dump" ]]; then
        mv "$stock_dump" "$work_root/failed-new-stock-dump"
      fi
      mv "$old_stock_dump" "$stock_dump"
    fi
  fi
  rm -rf -- "$work_root"
}
trap cleanup EXIT HUP INT TERM

mkdir -p \
  "$shadow_root/device/meizu/m86" \
  "$shadow_root/tools" \
  "$shadow_root/vendor/meizu/m86" \
  "$helper_tmp"
cp -a \
  "$device_root/extract-files.sh" \
  "$device_root/setup-makefiles.sh" \
  "$device_root/proprietary-files.txt" \
  "$shadow_root/device/meizu/m86/"
ln -s "$extract_utils" "$shadow_root/tools/extract-utils"

normalized_source="$stock_source"
if [[ -f "$stock_source" && "$stock_source" != *.zip ]]; then
  mkdir -p "$work_root/image-input"
  if ! ln "$stock_source" "$work_root/image-input/system.img" 2>/dev/null; then
    cp --reflink=auto "$stock_source" "$work_root/image-input/system.img"
  fi
  normalized_source="$work_root/image-input"
fi

SKIP_CLEANUP=1 TMPDIR="$helper_tmp" \
  "$shadow_root/device/meizu/m86/extract-files.sh" "$normalized_source"

staged_proprietary="$shadow_root/vendor/meizu/m86/proprietary"
if [[ ! -d "$staged_proprietary" ]]; then
  printf 'Extraction did not produce a proprietary directory.\n' >&2
  exit 1
fi

awk '
  /^[[:space:]]*($|#)/ { next }
  {
    entry=$0
    sub(/^[[:space:]]*-/, "", entry)
    sub(/[|;].*$/, "", entry)
    split(entry, parts, ":")
    entry=parts[1]
    sub(/^\//, "", entry)
    sub(/^system\//, "", entry)
    print entry
  }
' "$device_root/proprietary-files.txt" | LC_ALL=C sort -u > "$expected_list"

(
  cd "$staged_proprietary"
  find . \( -type f -o -type l \) -printf '%P\n' | LC_ALL=C sort
) > "$actual_list"

if ! cmp --quiet "$expected_list" "$actual_list"; then
  printf 'Extracted file set does not match proprietary-files.txt:\n' >&2
  diff -u "$expected_list" "$actual_list" >&2 || true
  exit 1
fi

expanded_system=""
for candidate in \
  "$helper_tmp/system_dump/system" \
  "$normalized_source/system" \
  "$normalized_source"; do
  if [[ -d "$candidate" ]] && \
      [[ -e "$candidate/$(head -n 1 "$expected_list")" ]]; then
    expanded_system="$candidate"
    break
  fi
done
if [[ -z "$expanded_system" ]]; then
  printf 'Unable to locate the expanded official system tree.\n' >&2
  exit 1
fi

while IFS= read -r relative_path; do
  official_file="$expanded_system/$relative_path"
  staged_file="$staged_proprietary/$relative_path"
  if [[ -L "$official_file" || -L "$staged_file" ]]; then
    if [[ ! -L "$official_file" || ! -L "$staged_file" ]] || \
        [[ "$(readlink "$official_file")" != "$(readlink "$staged_file")" ]]; then
      printf 'Symlink mismatch for %s\n' "$relative_path" >&2
      exit 1
    fi
  elif [[ ! -f "$official_file" ]] || ! cmp --quiet "$official_file" "$staged_file"; then
    printf 'Official-image content mismatch for %s\n' "$relative_path" >&2
    exit 1
  fi
done < "$expected_list"

mkdir -p "$new_stock_dump/system"
cp -a "$staged_proprietary/." "$new_stock_dump/system/"
(
  cd "$new_stock_dump"
  find system -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum \
    > PROPRIETARY_SHA256SUMS
  find system -type f -printf '%s  %p\n' | LC_ALL=C sort -k2 \
    > PROPRIETARY_FILE_SIZES
  sha256sum -c PROPRIETARY_SHA256SUMS >/dev/null
  while read -r expected_size relative_path; do
    actual_size="$(stat -c '%s' "$relative_path")"
    if [[ "$actual_size" != "$expected_size" ]]; then
      printf 'Size manifest mismatch for %s\n' "$relative_path" >&2
      exit 1
    fi
  done < PROPRIETARY_FILE_SIZES
)

mkdir -p "$vendor_root"
commit_started=true
if [[ -d "$vendor_proprietary" ]]; then
  mv "$vendor_proprietary" "$old_vendor"
fi
if [[ -d "$stock_dump" ]]; then
  mv "$stock_dump" "$old_stock_dump"
fi
mv "$staged_proprietary" "$vendor_proprietary"
mv "$new_stock_dump" "$stock_dump"
commit_complete=true

printf 'files\t%s\n' "$(wc -l < "$expected_list")"
printf 'bytes\t%s\n' "$(du -sb "$vendor_proprietary" | cut -f1)"
printf 'vendor\t%s\n' "$vendor_proprietary"
printf 'stock_dump\t%s\n' "$stock_dump"
