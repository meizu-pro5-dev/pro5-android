# Android 10 bring-up stages

1. Lock the verified Flyme 8.0.5.0A base, partition layout, boot parameters,
   firmware interfaces, and proprietary-file inventory.
2. Rebase the historical `m86` device/kernel configuration onto the maintained
   Exynos 7420 LineageOS 17.1 common platform. Track kernel work against the
   exact donor commits and gates in `docs/kernel-port.md`.
3. Build the kernel alone, then recovery and boot images without touching user
   data. Validate image sizes and boot-header/DTB layout against stock.
4. Reach recovery display plus adb; collect kernel, init, SELinux, and mount
   evidence before attempting a system boot.
5. Reach Android UI with permissive bring-up policy; stabilize storage,
   graphics, radio, Wi-Fi/Bluetooth, audio, sensors/GPS, and camera in that
   order of dependency.
6. Replace temporary compatibility workarounds, close SELinux policy, test
   encryption and upgrade paths, and produce a reproducible release manifest.

For stages R1 through U1, the maintained kernel extends the DT boot arguments
with `androidboot.hardware=m86 androidboot.selinux=permissive`. Extending is
required because the separate current DTB supplies a non-empty `bootargs`, so
the arm64 default `CMDLINE_FROM_BOOTLOADER` mode would otherwise discard the
compiled Android hardware selector. The boot-image v0 header remains empty.
`androidboot.selinux=permissive` is a named bring-up gate, not an acceptance
condition: it must be removed and the kernel rebuilt reproducibly before S1.

The root image contains empty `/custom` and `/mnv` directories because the
stock partition layout mounts Meizu auxiliary partitions there. Device-local
`file_contexts` labels only those two mountpoints as `rootfs`, which is needed
for deterministic `system.img` construction. It does not authorize or prove
runtime access to either partition; mount contents and denials remain device
tests, and the complete policy must still reach enforcing for S1.

The paused GPT backup also means no PRO 5 cache capacity is claimed. A reviewed
releasetools patch permits only a full block OTA with an empty source image in
that state; it contains no diff transfers or stashes. Incremental OTA creation
without a verified cache size fails explicitly. Record the handset GPT value
and remove this gate before incremental-update acceptance.

Every stage has a build-only gate before a device-flashing gate. Device backup
and flashing remain paused until explicitly resumed.
