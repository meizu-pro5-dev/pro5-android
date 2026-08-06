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

Every stage has a build-only gate before a device-flashing gate. Device backup
and flashing remain paused until explicitly resumed.
