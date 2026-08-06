#!/usr/bin/env bash

set -euo pipefail

dump_root="${1:-}"
if [[ -z "$dump_root" ]] || [[ ! -d "$dump_root" ]]; then
  printf 'Usage: %s EXPANDED_SYSTEM_ROOT\n' "$0" >&2
  exit 2
fi
if ! command -v readelf >/dev/null 2>&1; then
  printf 'readelf is required.\n' >&2
  exit 1
fi

audit_root="$(mktemp -d)"
trap 'rm -rf -- "$audit_root"' EXIT
needed_file="$audit_root/needed.tsv"
provided_file="$audit_root/provided.txt"
unprovided_file="$audit_root/unprovided.txt"
: > "$needed_file"

find "$dump_root" -type f -printf '%f\n' | sort -u > "$provided_file"

elf32=0
elf64=0
while IFS= read -r -d '' file; do
  if ! header="$(readelf -h "$file" 2>/dev/null)"; then
    continue
  fi

  elf_class="$(
    printf '%s\n' "$header" |
      sed -n 's/.*Class:[[:space:]]*//p'
  )"
  case "$elf_class" in
    ELF32) elf32=$((elf32 + 1)) ;;
    ELF64) elf64=$((elf64 + 1)) ;;
  esac

  relative_path="${file#"$dump_root"/}"
  readelf -d "$file" 2>/dev/null |
    sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' |
    while IFS= read -r soname; do
      printf '%s\t%s\t%s\n' \
        "$soname" "$elf_class" "$relative_path" >> "$needed_file"
    done
done < <(find "$dump_root" -type f -print0)

cut -f1 "$needed_file" | sort -u |
  comm -23 - "$provided_file" > "$unprovided_file"

printf 'elf32\t%d\nelf64\t%d\nneeded_sonames\t%d\nunprovided_sonames\t%d\n' \
  "$elf32" \
  "$elf64" \
  "$(cut -f1 "$needed_file" | sort -u | wc -l)" \
  "$(wc -l < "$unprovided_file")"

while IFS= read -r soname; do
  [[ -n "$soname" ]] || continue
  callers="$(awk -F '\t' -v soname="$soname" '$1 == soname {count++} END {print count + 0}' "$needed_file")"
  printf 'unprovided\t%s\tcallers=%s\n' "$soname" "$callers"
done < "$unprovided_file"
