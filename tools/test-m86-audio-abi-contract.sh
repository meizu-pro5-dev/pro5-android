#!/usr/bin/env bash

set -euo pipefail

project_root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
compiler="${CXX:-}"
if [[ -z "$compiler" ]]; then
  compiler="$(command -v c++ || command -v clang++)"
fi
if [[ -z "$compiler" ]]; then
  printf 'A C++17 compiler is required for the m86 audio ABI contract test.\n' >&2
  exit 1
fi

test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
test_source="$test_root/audio-abi-contract-test.cpp"
test_binary="$test_root/audio-abi-contract-test"

printf '%s\n' \
  '#include "hardware/meizu/m86/audio/LegacyAudioAbiContract.h"' \
  '#include <cassert>' \
  'int main() {' \
  '  using namespace m86::audio;' \
  '  assert(kFlymeDeviceAllocationSize == 0x140);' \
  '  assert(kFlymeOutputAllocationSize == 0xe0);' \
  '  assert(kFlymeInputAllocationSize == 176);' \
  '  assert(kFlymeAudioDeviceVersion == 0x200);' \
  '  assert(kObservedOutputMetadataAlias == 0x2);' \
  '  return 0;' \
  '}' > "$test_source"

"$compiler" -std=c++17 -Wall -Wextra -Werror \
  -I"$project_root" "$test_source" -o "$test_binary"
"$test_binary"
printf 'm86 audio private ABI contract: PASS (%s)\n' "$compiler"
