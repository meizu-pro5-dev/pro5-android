#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
policy_source="$project_root/device/meizu/m86/parts/M86Parts/src/org/lineageos/settings/m86/mback/MbackKeyPolicy.java"
test_source="$project_root/device/meizu/m86/parts/M86Parts/tests/src/org/lineageos/settings/m86/mback/MbackKeyPolicyTest.java"
javac_bin="${JAVAC:-}"

if [[ -z "$javac_bin" ]]; then
  javac_bin="$(command -v javac || true)"
fi
if [[ -z "$javac_bin" || ! -x "$javac_bin" ]]; then
  printf 'Set JAVAC to an executable JDK javac path.\n' >&2
  exit 1
fi

test_root="$(mktemp -d "${TMPDIR:-/tmp}/m86-mback-policy.XXXXXX")"
trap 'rm -rf -- "$test_root"' EXIT

"$javac_bin" -d "$test_root" "$policy_source" "$test_source"
java_bin="$(dirname "$javac_bin")/java"
if [[ ! -x "$java_bin" ]]; then
  printf 'Matching java executable is missing beside %s.\n' "$javac_bin" >&2
  exit 1
fi
"$java_bin" -cp "$test_root" \
  org.lineageos.settings.m86.mback.MbackKeyPolicyTest
