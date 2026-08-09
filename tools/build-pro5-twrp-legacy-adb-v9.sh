#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Usage: %s BASE_V7_RECOVERY_IMG NO_BLANK_DONOR_IMG OUTPUT_DIRECTORY\n' \
    "$(basename "$0")" >&2
}

if (( $# != 3 )); then
  usage
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
boot_image_inspector="$script_dir/inspect-android-boot-image.py"
boot_image_repacker="$script_dir/repack-android-boot-image.py"
ramdisk_rewriter="$script_dir/rewrite-newc-ramdisk.py"
reboot_property_patcher="$script_dir/patch-twrp-reboot-property.py"
v9_init="$project_root/patches/twrp-diagnostics/recovery-legacy-adb-v9.rc"
artifact_generation=v9
artifact_description='legacy-ADB and no-screen-blank diagnostic'
adb_serial=PRO5TWRPV9
donor_role='pre-v8 full-source build containing TW_NO_SCREEN_BLANK recovery ELF'
usb_mode='property-triggered legacy ADB-only'
direct_adb_v10="${PRO5_TWRP_DIRECT_ADB_V10:-0}"

expected_base_sha256=26c98728539ab21d723a67906e8250a78be633cdb481cdaa93f2ecdee2e7d43e
expected_base_size=29335552
expected_base_ramdisk_sha256=7c46b84170ccd2c108816b936105a961ba2907969d892fae2c65b69b6b04d725
expected_donor_sha256=433d10bc1acffc66521530fc13f439fd94b20e9849e17e1eec83738e98f23a04
expected_donor_size=27303936
expected_kernel_sha256=5df2fd06a58635c0299f10686c715a35fbc7ba0169bf9ffccdb292bba42c7d04
expected_base_init_sha256=f1e17f7d93dad91efa607098495debda771429a8ba326c0ab6ba9e883811ee70
expected_v9_init_sha256=2f0c3f3236c269401e109829d06ed82634c76241fe37ed615aedb150785b009d
expected_device_init_sha256=2550cabe02e6c711f905e180729ba5760b2cb9a608a8363a16e1ed02d4da2ded
expected_wrapper_sha256=136b881e587df48ddb9e272d41beb888a05c36fce0c5cc3bd00d5885ed6d864f
expected_base_recovery_sha256=0b31d94944fe11b1bf2ead63753b0ad2bfd3358073755150b3a6c900b6179e51
expected_donor_recovery_sha256=99b6dbad23532c505f1e244e76cfc00534e955dc8e87c040c5990a931e530724
expected_v9_recovery_sha256=d1f1f6af440acda2929d99aae4e5877d03a1bdaf4e2934800a018629b1eea80d
expected_recovery_size=935192
expected_minui_sha256=d59012dd3491f0dc12b542a09648b1a1fdeba410cf360fca608f96abbc848cfe
expected_adbd_sha256=881013de700ebba49ca8d9dd5670601b140e61a6365770ac0a7226b0f74de08f
expected_adbd_size=598600
expected_default_prop_sha256=527525283a0fa42d074e0d48f78b00c50b9a0cf24246f2765fe942ee49ba331e
expected_busybox_sha256=2cb28c8935e3218ed3559bf4b50f89beaa113751f40459ee2f059c1e6324199f
expected_shell_sha256=831ff2fa3b4f4e30e676a7a9130f3576e27ab293538a0298eb71e3e120778781
expected_recovery_fstab_sha256=e493296b929734453dce9740503c66070f7cdf911b88df3e89a049bf0e062e48
expected_stock_dtb_sha256=b45054fa87a5ffe114843953172d48d36408e1f93db35a6cbdfb0a8fc58a2165
conservative_image_limit=33550336
recovery_partition_size=33554432

if [[ "$direct_adb_v10" != "0" && "$direct_adb_v10" != "1" ]]; then
  printf 'Invalid PRO5_TWRP_DIRECT_ADB_V10 value: %s\n' \
    "$direct_adb_v10" >&2
  exit 2
fi
if [[ "$direct_adb_v10" == "1" ]]; then
  artifact_generation=v10
  artifact_description='direct-ADB and no-screen-timeout diagnostic'
  adb_serial=PRO5TWRPV10
  donor_role='full-source donor built with TW_NO_SCREEN_TIMEOUT and TW_NO_SCREEN_BLANK'
  usb_mode='direct on-boot legacy ADB-only; no USB property actions'
  v9_init="$project_root/patches/twrp-diagnostics/recovery-direct-adb-v10.rc"
  expected_donor_sha256=faff297b31eab8aa1a6b85b31e801d72d0bc512cdee6850bd6d0451749013d31
  expected_v9_init_sha256=f6ec000ea794e94da89258a9aa2912fcb8075938e89f04537b7b5afd0588b589
  expected_donor_recovery_sha256=fb86468df29070d51ec2ce63466cfb49249fac94d4c5a1e59b84fff127968678
  expected_v9_recovery_sha256=ee950be58363bd499c43af37464453ed6af8d3a50cf102855cc1b8ca5b63f079
  expected_recovery_size=935160
fi

sha256_of() {
  sha256sum "$1" | awk '{ print $1 }'
}

require_sha256() {
  local expected="$1"
  local source_file="$2"
  local actual

  actual="$(sha256_of "$source_file")"
  if [[ "$actual" != "$expected" ]]; then
    printf 'SHA-256 mismatch for %s: expected %s, found %s\n' \
      "$source_file" "$expected" "$actual" >&2
    exit 1
  fi
}

require_line() {
  local expected="$1"
  local source_file="$2"

  if ! grep -Fqx -- "$expected" "$source_file"; then
    printf 'Required audit line is absent from %s: %s\n' \
      "$source_file" "$expected" >&2
    exit 1
  fi
}

require_text() {
  local expected="$1"
  local source_file="$2"

  if ! grep -Fq -- "$expected" "$source_file"; then
    printf 'Required text is absent from %s: %s\n' \
      "$source_file" "$expected" >&2
    exit 1
  fi
}

require_absent_line() {
  local rejected="$1"
  local source_file="$2"

  if grep -Fqx -- "$rejected" "$source_file"; then
    printf 'Rejected audit line is present in %s: %s\n' \
      "$source_file" "$rejected" >&2
    exit 1
  fi
}

for required_file in \
  "$boot_image_inspector" \
  "$boot_image_repacker" \
  "$ramdisk_rewriter" \
  "$reboot_property_patcher" \
  "$v9_init"; do
  if [[ ! -s "$required_file" ]]; then
    printf 'Required %s build input is absent: %s\n' \
      "$artifact_generation" "$required_file" >&2
    exit 1
  fi
done
if ! command -v objdump >/dev/null 2>&1; then
  printf 'objdump is required for the recovery ELF ABI comparison.\n' >&2
  exit 1
fi

base_input="$1"
donor_input="$2"
for image_spec in "base:$base_input" "donor:$donor_input"; do
  image_role="${image_spec%%:*}"
  image_path="${image_spec#*:}"
  if [[ ! -f "$image_path" ]]; then
    printf 'The %s image is absent: %s\n' "$image_role" "$image_path" >&2
    exit 1
  fi
done
base_dir="$(cd "$(dirname "$base_input")" && pwd -P)"
base_image="$base_dir/$(basename "$base_input")"
donor_dir="$(cd "$(dirname "$donor_input")" && pwd -P)"
donor_image="$donor_dir/$(basename "$donor_input")"

output_input="$3"
output_parent_input="$(dirname "$output_input")"
if [[ ! -d "$output_parent_input" ]]; then
  printf 'The output parent directory is absent: %s\n' \
    "$output_parent_input" >&2
  exit 1
fi
output_parent="$(cd "$output_parent_input" && pwd -P)"
output_name="$(basename "$output_input")"
if [[ -z "$output_name" || "$output_name" == "." || \
    "$output_name" == ".." ]]; then
  printf 'Invalid output directory name: %s\n' "$output_name" >&2
  exit 1
fi
artifact_dir="$output_parent/$output_name"
if [[ -e "$artifact_dir" ]]; then
  printf 'Refusing to overwrite artifact directory: %s\n' \
    "$artifact_dir" >&2
  exit 1
fi

require_sha256 "$expected_base_sha256" "$base_image"
require_sha256 "$expected_donor_sha256" "$donor_image"
require_sha256 "$expected_v9_init_sha256" "$v9_init"

require_line '    setenforce permissive' "$v9_init"
require_line '    setprop mtp.crash_check 1' "$v9_init"
require_line \
  '    write /sys/class/android_usb/android0/idVendor 18D1' "$v9_init"
require_line \
  '    write /sys/class/android_usb/android0/idProduct 4EE7' "$v9_init"
require_line \
  '    write /sys/class/android_usb/android0/functions adb' "$v9_init"
require_line \
  '    write /sys/class/android_usb/android0/enable 1' "$v9_init"
require_line '    start adbd' "$v9_init"
require_line '    setprop sys.usb.state adb' "$v9_init"
require_line 'service recovery /sbin/sh /sbin/permissive.sh' "$v9_init"
require_line 'service adbd /sbin/adbd' "$v9_init"
if [[ "$direct_adb_v10" == "1" ]]; then
  require_line \
    '    write /sys/class/android_usb/android0/iSerial PRO5TWRPV10' "$v9_init"
  require_line '    write /dev/kmsg pro5_twrp_v10_usb_begin' "$v9_init"
  require_line '    write /dev/kmsg pro5_twrp_v10_usb_end' "$v9_init"
  if grep -Eq '^[[:space:]]*on property:sys\.usb\.config=' "$v9_init"; then
    printf 'The v10 init still contains a USB property action.\n' >&2
    exit 1
  fi
else
  require_line '    setprop sys.usb.config none' "$v9_init"
  require_line 'on property:sys.usb.config=mtp,adb' "$v9_init"
  require_line 'on property:sys.usb.config=adb' "$v9_init"
  require_line \
    '    write /sys/class/android_usb/android0/iSerial PRO5TWRPV9' "$v9_init"
fi
require_absent_line 'import /init.recovery.m86.rc' "$v9_init"
require_absent_line 'on property:ro.debuggable=1' "$v9_init"
require_absent_line 'on property:service.adb.root=1' "$v9_init"
require_absent_line \
  '    write /sys/class/android_usb/android0/idProduct 4EE2' "$v9_init"
require_absent_line '    restart adbd' "$v9_init"
if grep -Eq \
    '^[[:space:]]*(mkdir|mount)[[:space:]].*/dev/usb-ffs' "$v9_init"; then
  printf 'The %s init unexpectedly enables a FunctionFS directory.\n' \
    "$artifact_generation" >&2
  exit 1
fi
if grep -Eq '^[[:space:]]*mount[[:space:]]+functionfs' "$v9_init"; then
  printf 'The %s init unexpectedly mounts FunctionFS.\n' \
    "$artifact_generation" >&2
  exit 1
fi
if grep -Fq -- '${ro.serialno}' "$v9_init"; then
  printf 'The %s init still expands the absent recovery serial property.\n' \
    "$artifact_generation" >&2
  exit 1
fi

inspector_sha256="$(sha256_of "$boot_image_inspector")"
repacker_sha256="$(sha256_of "$boot_image_repacker")"
rewriter_sha256="$(sha256_of "$ramdisk_rewriter")"
patcher_sha256="$(sha256_of "$reboot_property_patcher")"
builder_sha256="$(sha256_of "${BASH_SOURCE[0]}")"

stage_root="$(mktemp -d \
  "$output_parent/.pro5-twrp-$artifact_generation.XXXXXX")"
cleanup() {
  if [[ -n "${stage_root:-}" && -d "$stage_root" && \
      "$stage_root" == \
        "$output_parent/.pro5-twrp-$artifact_generation."* ]]; then
    rm -r -- "$stage_root"
  fi
}
trap cleanup EXIT

work_dir="$stage_root/work"
pass_one="$work_dir/pass-one"
pass_two="$work_dir/pass-two"
diff_root="$work_dir/init-diff"
base_init="$work_dir/init-v7.rc"
base_recovery="$work_dir/recovery-v7"
base_adbd="$work_dir/adbd-v7"
base_default_prop="$work_dir/default-v7.prop"
donor_recovery="$work_dir/recovery-no-screen-blank"
patched_recovery="$work_dir/recovery-no-screen-blank-loghold"
staged_artifact="$stage_root/artifact"
mkdir -p "$pass_one" "$pass_two" "$diff_root" \
  "$staged_artifact/provenance"

base_header="$staged_artifact/BASE-RECOVERY-HEADER.txt"
python3 "$boot_image_inspector" "$base_image" \
  --expect-page-size 4096 \
  --expect-kernel-addr 0x40080000 \
  --expect-ramdisk-addr 0x42000000 \
  --expect-second-addr 0x40f78000 \
  --expect-tags-addr 0x40000100 \
  --expect-second-size 0 \
  --expect-dt-size 0 \
  --expect-valid-image-id \
  --expect-empty-cmdline \
  --expect-ramdisk-compression gzip \
  --expect-ramdisk-file-sha256 \
    "init.rc=$expected_base_init_sha256" \
  --expect-ramdisk-file-sha256 \
    "init.recovery.m86.rc=$expected_device_init_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/permissive.sh=$expected_wrapper_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/recovery=$expected_base_recovery_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/libminuitwrp.so=$expected_minui_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/adbd=$expected_adbd_sha256" \
  --expect-ramdisk-file-sha256 \
    "default.prop=$expected_default_prop_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/busybox=$expected_busybox_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/sh=$expected_shell_sha256" \
  --expect-ramdisk-file-sha256 \
    "etc/recovery.fstab=$expected_recovery_fstab_sha256" \
  --expect-ramdisk-elf sbin/recovery \
  --expect-ramdisk-elf sbin/libminuitwrp.so \
  --expect-ramdisk-elf sbin/adbd \
  --expect-ramdisk-elf sbin/busybox \
  --expect-ramdisk-elf sbin/sh \
  --extract-ramdisk-file "init.rc=$base_init" \
  --extract-ramdisk-file "sbin/recovery=$base_recovery" \
  --extract-ramdisk-file "sbin/adbd=$base_adbd" \
  --extract-ramdisk-file "default.prop=$base_default_prop" \
  --max-size "$conservative_image_limit" >"$base_header"
require_line "file_size=$expected_base_size" "$base_header"
require_line "kernel_sha256=$expected_kernel_sha256" "$base_header"
require_line "ramdisk_sha256=$expected_base_ramdisk_sha256" "$base_header"
require_line 'image_id_scheme=conditional-dtb' "$base_header"
require_sha256 "$expected_base_init_sha256" "$base_init"
require_sha256 "$expected_base_recovery_sha256" "$base_recovery"
require_sha256 "$expected_adbd_sha256" "$base_adbd"
require_sha256 "$expected_default_prop_sha256" "$base_default_prop"
if [[ "$(wc -c <"$base_adbd" | tr -d ' ')" != "$expected_adbd_size" ]]; then
  printf 'Unexpected v7 adbd size.\n' >&2
  exit 1
fi
if ! strings -a "$base_adbd" | grep -Fx '/dev/android_adb' >/dev/null; then
  printf 'The v7 adbd omits the native android_adb transport.\n' >&2
  exit 1
fi
require_text 'ro.adb.secure=0' "$base_default_prop"
require_text 'ro.secure=0' "$base_default_prop"

donor_header="$staged_artifact/DONOR-RECOVERY-HEADER.txt"
python3 "$boot_image_inspector" "$donor_image" \
  --expect-page-size 4096 \
  --expect-second-size 0 \
  --expect-dt-size 0 \
  --expect-valid-image-id \
  --expect-ramdisk-compression lzma \
  --expect-ramdisk-file-sha256 \
    "sbin/recovery=$expected_donor_recovery_sha256" \
  --expect-ramdisk-elf sbin/recovery \
  --extract-ramdisk-file "sbin/recovery=$donor_recovery" \
  >"$donor_header"
require_line "file_size=$expected_donor_size" "$donor_header"
require_sha256 "$expected_donor_recovery_sha256" "$donor_recovery"
if [[ "$(wc -c <"$donor_recovery" | tr -d ' ')" != \
    "$expected_recovery_size" ]]; then
  printf 'Unexpected %s donor recovery ELF size.\n' \
    "$artifact_generation" >&2
  exit 1
fi
if [[ "$(strings -a "$donor_recovery" | grep -Fxc 'sys.powerctl')" != "1" ]]; then
  printf 'The donor recovery does not contain one sys.powerctl literal.\n' >&2
  exit 1
fi
if ! strings -a "$donor_recovery" | \
    grep -Fx 'TW_SCREEN_BLANK_ON_BOOT := true' >/dev/null; then
  printf 'The donor recovery omits the screen-blank-on-boot provenance marker.\n' >&2
  exit 1
fi
if [[ "$direct_adb_v10" == "1" ]]; then
  for rejected_timeout_hook in \
    /sbin/postscreenblank.sh \
    /sbin/postscreenunblank.sh; do
    if strings -a "$donor_recovery" | \
        grep -Fx "$rejected_timeout_hook" >/dev/null; then
      printf 'The v10 donor still contains timeout hook %s.\n' \
        "$rejected_timeout_hook" >&2
      exit 1
    fi
  done
fi

python3 "$reboot_property_patcher" "$donor_recovery" \
  --expect-input-sha256 "$expected_donor_recovery_sha256" \
  --output "$patched_recovery" \
  >"$staged_artifact/RECOVERY-PROPERTY-PATCH.txt"
require_sha256 "$expected_v9_recovery_sha256" "$patched_recovery"
require_line "output_size=$expected_recovery_size" \
  "$staged_artifact/RECOVERY-PROPERTY-PATCH.txt"
require_line "output_sha256=$expected_v9_recovery_sha256" \
  "$staged_artifact/RECOVERY-PROPERTY-PATCH.txt"
if strings -a "$patched_recovery" | grep -Fx 'sys.powerctl' >/dev/null; then
  printf 'The %s recovery still contains the automatic reboot property.\n' \
    "$artifact_generation" >&2
  exit 1
fi
if [[ "$(strings -a "$patched_recovery" | \
    grep -Fxc 'twrp.loghold')" != "1" ]]; then
  printf 'The %s recovery does not contain one inert reboot property.\n' \
    "$artifact_generation" >&2
  exit 1
fi

objdump -p "$base_recovery" | \
  awk '$1 == "NEEDED" { print $2 }' >"$work_dir/base-needed.txt"
objdump -p "$donor_recovery" | \
  awk '$1 == "NEEDED" { print $2 }' >"$work_dir/donor-needed.txt"
objdump -T "$base_recovery" | \
  awk 'NF >= 2 { print $NF }' | LC_ALL=C sort -u \
  >"$work_dir/base-dynamic-symbols.txt"
objdump -T "$donor_recovery" | \
  awk 'NF >= 2 { print $NF }' | LC_ALL=C sort -u \
  >"$work_dir/donor-dynamic-symbols.txt"
if ! cmp --silent "$work_dir/base-needed.txt" \
    "$work_dir/donor-needed.txt"; then
  printf 'The donor recovery changes the shared-library dependency set.\n' >&2
  exit 1
fi
if [[ "$(grep -Fxc '_Z11gr_fb_blankb' \
    "$work_dir/base-dynamic-symbols.txt")" != "1" ]] || \
    grep -Fx '_Z11gr_fb_blankb' \
      "$work_dir/donor-dynamic-symbols.txt" >/dev/null; then
  printf 'The donor recovery has an unexpected gr_fb_blank import state.\n' >&2
  exit 1
fi
grep -Fxv '_Z11gr_fb_blankb' "$work_dir/base-dynamic-symbols.txt" \
  >"$work_dir/expected-donor-dynamic-symbols.txt"
if ! cmp --silent "$work_dir/expected-donor-dynamic-symbols.txt" \
    "$work_dir/donor-dynamic-symbols.txt"; then
  printf 'The donor recovery has dynamic-symbol changes beyond gr_fb_blank.\n' >&2
  exit 1
fi
{
  printf 'dependency_set_identical=yes\n'
  printf 'dynamic_symbol_difference=removed undefined _Z11gr_fb_blankb import only\n'
  printf 'donor_dynamic_symbol_surface_sha256=%s\n' \
    "$(sha256_of "$work_dir/donor-dynamic-symbols.txt")"
  printf 'needed_libraries:\n'
  sed 's/^/  /' "$work_dir/base-needed.txt"
} >"$staged_artifact/RECOVERY-ABI-COMPARE.txt"

cp "$base_init" "$diff_root/init.rc"
(
  cd "$diff_root"
  git init -q
  git add init.rc
  cp "$v9_init" init.rc
  git diff --check
  if [[ "$(git diff --name-only)" != "init.rc" ]]; then
    printf 'The %s init comparison changed an unexpected path.\n' \
      "$artifact_generation" >&2
    exit 1
  fi
  git diff --no-ext-diff -- init.rc > \
    "$staged_artifact/INIT-RC-DIFF.patch"
)

for pass_spec in "ONE:$pass_one" "TWO:$pass_two"; do
  pass_name="${pass_spec%%:*}"
  pass_dir="${pass_spec#*:}"
  rewrite_log="$staged_artifact/RAMDISK-REWRITE-PASS-$pass_name.txt"

  python3 "$ramdisk_rewriter" \
    --base-boot-image "$base_image" \
    --expect-base-sha256 "$expected_base_sha256" \
    --replace-data "init.rc=$v9_init" \
    --replace-data "sbin/recovery=$patched_recovery" \
    --compression gzip \
    --output "$pass_dir/ramdisk.gzip" >"$rewrite_log"
  require_line 'base_entry_count_including_trailer=489' "$rewrite_log"
  require_line 'output_entry_count_including_trailer=489' "$rewrite_log"
  require_line 'added_paths=' "$rewrite_log"
  require_line 'removed_paths=' "$rewrite_log"
  require_line 'changed_data_paths=init.rc,sbin/recovery' "$rewrite_log"
  require_line 'changed_metadata_paths=' "$rewrite_log"
  require_line 'entry_order_identical=yes' "$rewrite_log"
  require_line 'archive_tail_identical=yes' "$rewrite_log"

  python3 "$boot_image_repacker" "$base_image" \
    --ramdisk "$pass_dir/ramdisk.gzip" \
    --image-id-scheme conditional-dtb \
    --output "$pass_dir/recovery.img"
done

if ! cmp --silent "$pass_one/ramdisk.gzip" "$pass_two/ramdisk.gzip" || \
    ! cmp --silent "$pass_one/recovery.img" "$pass_two/recovery.img"; then
  printf 'The two clean %s repacks are not byte-identical.\n' \
    "$artifact_generation" >&2
  exit 1
fi

cp "$pass_one/ramdisk.gzip" "$staged_artifact/ramdisk.gzip"
cp "$pass_one/recovery.img" "$staged_artifact/recovery.img"
cp "$v9_init" "$staged_artifact/init.rc"
cp "$donor_recovery" \
  "$staged_artifact/provenance/recovery-no-screen-blank"
cp "$patched_recovery" \
  "$staged_artifact/provenance/recovery-no-screen-blank-loghold"
cp "$v9_init" \
  "$staged_artifact/provenance/recovery-$artifact_generation.rc"
cp "$reboot_property_patcher" \
  "$staged_artifact/provenance/patch-twrp-reboot-property.py"
cp "$boot_image_inspector" \
  "$staged_artifact/provenance/inspect-android-boot-image.py"
cp "$boot_image_repacker" \
  "$staged_artifact/provenance/repack-android-boot-image.py"
cp "$ramdisk_rewriter" \
  "$staged_artifact/provenance/rewrite-newc-ramdisk.py"
cp "${BASH_SOURCE[0]}" \
  "$staged_artifact/provenance/build-pro5-twrp-legacy-adb-v9.sh"

output_header="$staged_artifact/RECOVERY-HEADER.txt"
python3 "$boot_image_inspector" "$staged_artifact/recovery.img" \
  --expect-page-size 4096 \
  --expect-kernel-addr 0x40080000 \
  --expect-ramdisk-addr 0x42000000 \
  --expect-second-addr 0x40f78000 \
  --expect-tags-addr 0x40000100 \
  --expect-second-size 0 \
  --expect-dt-size 0 \
  --expect-valid-image-id \
  --expect-empty-cmdline \
  --expect-ramdisk-compression gzip \
  --expect-ramdisk-file-sha256 \
    "init.rc=$expected_v9_init_sha256" \
  --expect-ramdisk-file-sha256 \
    "init.recovery.m86.rc=$expected_device_init_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/permissive.sh=$expected_wrapper_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/recovery=$expected_v9_recovery_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/libminuitwrp.so=$expected_minui_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/adbd=$expected_adbd_sha256" \
  --expect-ramdisk-file-sha256 \
    "default.prop=$expected_default_prop_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/busybox=$expected_busybox_sha256" \
  --expect-ramdisk-file-sha256 \
    "sbin/sh=$expected_shell_sha256" \
  --expect-ramdisk-file-sha256 \
    "etc/recovery.fstab=$expected_recovery_fstab_sha256" \
  --expect-ramdisk-elf sbin/recovery \
  --expect-ramdisk-elf sbin/libminuitwrp.so \
  --expect-ramdisk-elf sbin/adbd \
  --expect-ramdisk-elf sbin/busybox \
  --expect-ramdisk-elf sbin/sh \
  --max-size "$conservative_image_limit" >"$output_header"
require_line "kernel_sha256=$expected_kernel_sha256" "$output_header"
require_line 'image_id_scheme=conditional-dtb' "$output_header"
require_line 'dt_size=0' "$output_header"

require_sha256 "$inspector_sha256" "$boot_image_inspector"
require_sha256 "$repacker_sha256" "$boot_image_repacker"
require_sha256 "$rewriter_sha256" "$ramdisk_rewriter"
require_sha256 "$patcher_sha256" "$reboot_property_patcher"
require_sha256 "$builder_sha256" "${BASH_SOURCE[0]}"
require_sha256 "$expected_v9_init_sha256" "$v9_init"
require_sha256 "$expected_base_sha256" "$base_image"
require_sha256 "$expected_donor_sha256" "$donor_image"
require_sha256 "$expected_v9_recovery_sha256" "$patched_recovery"

artifact_size="$(wc -c <"$staged_artifact/recovery.img" | tr -d ' ')"
artifact_sha256="$(sha256_of "$staged_artifact/recovery.img")"
ramdisk_size="$(wc -c <"$staged_artifact/ramdisk.gzip" | tr -d ' ')"
ramdisk_sha256="$(sha256_of "$staged_artifact/ramdisk.gzip")"
conservative_margin=$((conservative_image_limit - artifact_size))
partition_margin=$((recovery_partition_size - artifact_size))
source_revision="$(git -C "$project_root" rev-parse HEAD)"
source_state=clean
if [[ -n "$(git -C "$project_root" \
    status --porcelain --untracked-files=normal)" ]]; then
  source_state=dirty
fi
built_at="$(date '+%Y-%m-%dT%H:%M:%S%z')"

{
  printf 'artifact_role=test-only PRO 5 TWRP %s %s\n' \
    "$artifact_generation" "$artifact_description"
  printf 'artifact_generation=%s\n' "$artifact_generation"
  printf 'artifact_file=recovery.img\n'
  printf 'artifact_size=%s\n' "$artifact_size"
  printf 'artifact_sha256=%s\n' "$artifact_sha256"
  printf 'built_at=%s\n' "$built_at"
  printf 'source_revision=%s\n' "$source_revision"
  printf 'source_worktree=%s\n' "$source_state"
  printf 'base_image=%s\n' "$base_image"
  printf 'base_recovery_sha256=%s\n' "$expected_base_sha256"
  printf 'base_device_result=v7 reaches full TWRP GUI and touch; display blanks after about one minute; ADB launch races\n'
  printf 'donor_image=%s\n' "$donor_image"
  printf 'donor_recovery_sha256=%s\n' "$expected_donor_sha256"
  printf 'donor_role=%s\n' "$donor_role"
  printf 'changed_data_paths=init.rc,sbin/recovery\n'
  printf 'changed_metadata_paths=none\n'
  printf 'ramdisk_entry_count_including_trailer=489\n'
  printf 'ramdisk_order=byte-identical path order\n'
  printf 'ramdisk_compression=gzip\n'
  printf 'ramdisk_size=%s\n' "$ramdisk_size"
  printf 'ramdisk_sha256=%s\n' "$ramdisk_sha256"
  printf 'kernel_sha256=%s\n' "$expected_kernel_sha256"
  printf 'minuitwrp_sha256=%s\n' "$expected_minui_sha256"
  printf 'base_recovery_elf_sha256=%s\n' "$expected_base_recovery_sha256"
  printf 'donor_recovery_elf_sha256=%s\n' "$expected_donor_recovery_sha256"
  printf '%s_recovery_elf_sha256=%s\n' \
    "$artifact_generation" "$expected_v9_recovery_sha256"
  printf 'recovery_abi=needed libraries identical; only gr_fb_blank undefined import removed from v7 surface\n'
  printf '%s_init_sha256=%s\n' \
    "$artifact_generation" "$expected_v9_init_sha256"
  printf 'adbd_sha256=%s\n' "$expected_adbd_sha256"
  printf 'adb_transport=native /dev/android_adb; no FunctionFS mount\n'
  printf 'adb_usb_identity=18D1:4EE7 serial %s\n' "$adb_serial"
  printf 'adb_usb_mode=%s\n' "$usb_mode"
  printf 'mtp=disabled with mtp.crash_check=1\n'
  if [[ "$direct_adb_v10" == "1" ]]; then
    printf 'screen_timeout=compiled out with TW_NO_SCREEN_TIMEOUT; timeout hook literals absent\n'
  else
    printf 'screen_timeout=active; only gr_fb_blank compiled out with TW_NO_SCREEN_BLANK\n'
  fi
  printf 'wrapper_sha256=%s\n' "$expected_wrapper_sha256"
  printf 'image_id_scheme=conditional-dtb\n'
  printf 'embedded_dtb_size=0\n'
  printf 'required_external_dtb=Flyme 8.0.5.0A stock DTB\n'
  printf 'required_external_dtb_sha256=%s\n' "$expected_stock_dtb_sha256"
  printf 'conservative_image_limit=%s\n' "$conservative_image_limit"
  printf 'conservative_image_margin=%s\n' "$conservative_margin"
  printf 'recovery_partition_size=%s\n' "$recovery_partition_size"
  printf 'recovery_partition_margin=%s\n' "$partition_margin"
  printf 'reproducibility=two byte-identical ramdisk and recovery repacks\n'
  printf 'persistent_write=unchanged v4 wrapper mounts cache rw,sync and writes pro5-twrp-diag-v4 files\n'
  printf 'final_acceptance=no; one controlled device test required\n'
} >"$staged_artifact/METADATA.txt"

{
  printf 'source_revision=%s\n' "$source_revision"
  printf 'source_worktree=%s\n' "$source_state"
  printf 'inspector_sha256=%s\n' "$inspector_sha256"
  printf 'repacker_sha256=%s\n' "$repacker_sha256"
  printf 'rewriter_sha256=%s\n' "$rewriter_sha256"
  printf 'reboot_property_patcher_sha256=%s\n' "$patcher_sha256"
  printf 'builder_sha256=%s\n' "$builder_sha256"
  printf '%s_init_sha256=%s\n' \
    "$artifact_generation" "$expected_v9_init_sha256"
  printf 'base_recovery_sha256=%s\n' "$expected_base_sha256"
  printf 'donor_recovery_sha256=%s\n' "$expected_donor_sha256"
  printf '\nworktree_status:\n'
  git -C "$project_root" status --short --untracked-files=normal
} >"$staged_artifact/SOURCE-STATE.txt"

{
  printf 'pass_one_ramdisk_sha256=%s\n' \
    "$(sha256_of "$pass_one/ramdisk.gzip")"
  printf 'pass_two_ramdisk_sha256=%s\n' \
    "$(sha256_of "$pass_two/ramdisk.gzip")"
  printf 'ramdisk_byte_identical=yes\n'
  printf 'pass_one_recovery_sha256=%s\n' \
    "$(sha256_of "$pass_one/recovery.img")"
  printf 'pass_two_recovery_sha256=%s\n' \
    "$(sha256_of "$pass_two/recovery.img")"
  printf 'recovery_byte_identical=yes\n'
} >"$staged_artifact/REPRODUCIBILITY.txt"

if [[ "$direct_adb_v10" == "1" ]]; then
  cat >"$staged_artifact/README.md" <<EOF
# PRO 5 TWRP direct ADB and no-screen-timeout diagnostic v10

V10 returns to the exact v7 image that reached the complete TWRP GUI and had
working touch. The v9 handset result showed that removing gr_fb_blank alone is
insufficient: TWRP's remaining timer still dims the panel and writes brightness
zero. This build uses a reproducible recovery ELF compiled with
TW_NO_SCREEN_TIMEOUT as well as TW_NO_SCREEN_BLANK. The donor contains neither
/sbin/postscreenblank.sh nor /sbin/postscreenunblank.sh, confirming that the
whole timeout action path is absent.

Only two ramdisk data payloads change:

1. init.rc configures the legacy android_usb gadget directly in the boot action
   as ADB-only 18D1:4EE7, serial PRO5TWRPV10. It has no sys.usb.config action,
   no FunctionFS mount and no restart sequence; retained old adbd therefore
   uses /dev/android_adb. MTP remains disabled.
2. sbin/recovery is the no-screen-timeout donor with the exact
   sys.powerctl-to-twrp.loghold diagnostic patch re-applied. Its dependency set
   matches v7, and its dynamic-symbol surface differs only by removal of the
   gr_fb_blank import.

The kernel, display library, old adbd, every other ramdisk payload, all 489
cpio paths, path order, metadata, archive tail and boot geometry remain v7.

## Exact artifact

- size: $artifact_size bytes
- SHA-256: $artifact_sha256
- embedded DTB: none
- required external DTB: unchanged Flyme 8.0.5.0A stock DTB,
  SHA-256 $expected_stock_dtb_sha256

## Controlled test

Connect USB before requesting recovery. Do not press Power and leave the TWRP
main screen untouched for at least five minutes. It should not dim or turn
black. The host should enumerate 18D1:4EE7 and adb devices should report
PRO5TWRPV10. If ADB appears, collect only read-only evidence from
/tmp/recovery.log, dmesg and getprop.

No flash command is included. The retained diagnostic wrapper mounts cache
read-write with synchronous I/O and creates /cache/recovery/pro5-twrp-diag-v4-*
files. Do not mount, wipe, format, install, restore, or write boot, DTB,
firmware, parameter or identity partitions.
EOF
else
  cat >"$staged_artifact/README.md" <<EOF
# PRO 5 TWRP legacy ADB and no-screen-blank diagnostic v9

V9 returns to the exact v7 image that reached the complete TWRP GUI and had
working touch on the handset. It does not use the v8 kernel, lzma ramdisk, new
init, new minadbd, FunctionFS or MTP path.

Only two ramdisk data payloads change:

1. init.rc removes the proven early-adbd/restart race. After properties load it
   configures the legacy android_usb gadget once as ADB-only 18D1:4EE7 with
   serial PRO5TWRPV9. It leaves FunctionFS unmounted, so the retained old adbd
   uses /dev/android_adb. MTP remains disabled.
2. sbin/recovery comes from the exact reproducible pre-v8 source build made
   after TW_NO_SCREEN_BLANK was enabled. Its dependency set matches v7 and its
   dynamic-symbol surface differs only by removal of the gr_fb_blank import.
   The existing exact sys.powerctl-to-twrp.loghold
   diagnostic patch is re-applied so an ordinary GUI-return request cannot
   erase the live logs.

The kernel, display library, old adbd, every other ramdisk payload, all 489
cpio paths, path order, metadata, archive tail and boot geometry remain v7.

## Exact artifact

- size: $artifact_size bytes
- SHA-256: $artifact_sha256
- embedded DTB: none
- required external DTB: unchanged Flyme 8.0.5.0A stock DTB,
  SHA-256 $expected_stock_dtb_sha256

## Controlled test

Connect USB before requesting recovery. On the host, the recovery should
enumerate as 18D1:4EE7 and adb devices should report PRO5TWRPV9. Leave the
TWRP main screen untouched for at least three minutes; it should neither blank
nor return to the Meizu framebuffer. If ADB appears, only collect read-only
evidence from /tmp/recovery.log, dmesg and getprop.

No flash command is included in this diagnostic bundle. The retained wrapper
mounts cache read-write with synchronous I/O and creates
/cache/recovery/pro5-twrp-diag-v4-* files. Do not mount, wipe, format, install,
restore, or write boot, DTB, firmware, parameter or identity partitions.
EOF
fi

(
  cd "$staged_artifact"
  find . -type f ! -name SHA256SUMS -print | LC_ALL=C sort | \
    while IFS= read -r artifact_file; do
      sha256sum "$artifact_file"
    done | sed 's#  \./#  #' >SHA256SUMS
  sha256sum --quiet -c SHA256SUMS
)

mv "$staged_artifact" "$artifact_dir"
trap - EXIT
cleanup

printf 'Built PRO 5 TWRP %s %s.\n' \
  "$artifact_generation" "$artifact_description"
printf 'artifact_dir=%s\n' "$artifact_dir"
printf 'recovery_size=%s\n' "$artifact_size"
printf 'recovery_sha256=%s\n' "$artifact_sha256"
printf 'changed_data_paths=init.rc,sbin/recovery\n'
printf 'adb_usb_identity=18D1:4EE7 %s\n' "$adb_serial"
printf 'persistent_device_write=/cache/recovery/pro5-twrp-diag-v4-*\n'
printf 'flash_authorized=no\n'
