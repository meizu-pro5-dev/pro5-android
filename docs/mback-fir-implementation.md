# mBack and Flyme 5 FIR implementation

## mBack input path

The FPC1020 driver reports four logical gestures through its `fpc1020` input
device. The m86 key layout keeps these events distinct instead of exposing
hard-coded Back or Menu keys:

| Gesture | Linux scan codes | Android key |
| --- | --- | --- |
| Tap | 158 | F9 |
| Double tap | 139 | F10 |
| Swipe left | 191, 193 | F11 |
| Swipe right | 190, 192 | F12 |

Both the driver's slow-swipe and quick-swipe variants are mapped to the same
directional action. `PhoneWindowManager` accepts these F-keys only when the
event comes from the input device named `fpc1020`, consumes both down and up,
and performs the configured action on the uncancelled key-up event. Injected
Home and Back events therefore cannot recurse into the mBack handler.

The feature is gated by `ro.meizu.hardware.mback=true`. Its controls are in
LineageParts' official **System > Buttons > mBack** category and are stored in
`LineageSettings.System`. Defaults preserve the established PRO 5 behavior:

- tap: Back
- double tap: no action
- swipe left: Home
- swipe right: Recents

Each gesture can be assigned no action, Menu, Recents, search, voice search,
in-app search, camera, sleep, last app, split screen, Home, or Back. The
three-button navigation bar remains enabled as a fallback while device testing
is completed.

## Flyme 5.1.2.0A FIR path

The maintained copies of `stage1.txt` and `stage2.txt` come from the local
Flyme OS 5.1.2.0A extraction and are installed under `/vendor/firmware`.
Android 10 ueventd includes that directory in its standard firmware search
path. The same coefficient values are compiled into `es9018k2m.c`; the kernel
uses them if `request_firmware()` cannot obtain the files.

| File | Coefficients | SHA-256 |
| --- | ---: | --- |
| stage1.txt | 128 | `4706f3622459cd55d0f881f3fe1eea73fd465c28a266039efb6b6edc31b4ec2c` |
| stage2.txt | 16 | `2950bfd8c78d6f84acf3fa883e5901adae68c1bf10d216b0495648c8caa96772` |

The firmware parser now bounds the number of parsed values and rejects an
incomplete or malformed file before falling back to the compiled coefficients.

The complete package and static validation results are recorded in
`mback-fir-build-2026-08-09.md`.

## Device validation

After flashing, verify the input and audio paths with:

```bash
adb shell getprop ro.meizu.hardware.mback
adb shell getevent -lt /dev/input/eventX
adb shell settings get lineage_system mback_tap_action
adb shell settings get lineage_system mback_double_tap_action
adb shell settings get lineage_system mback_swipe_left_action
adb shell settings get lineage_system mback_swipe_right_action
adb shell dmesg | grep -i 'ess9018.*FIR'
```

Confirm all four mBack preferences update immediately, persist across reboot,
and do not turn unrelated external F9-F12 keyboard events into navigation.
With wired headphones attached, toggle HiFi and confirm the kernel either logs
successful `stage1.txt`/`stage2.txt` requests or applies the identical fallback
without an invalid-coefficient error.
