# M86 SITRIL libcutils compatibility shim

Flyme's 64-bit `libril_sitril.so` uses the legacy libcutils modified-UTF
conversion ABI removed after Android 10. This system library restores only
that ABI from AOSP Android 10 sources. The device linker configuration injects
it only while loading `/system/lib64/libril_sitril.so`; it must not replace or
augment Android 12's global `libcutils.so`.

The implementation mirrors the first-generation LineageOS 19.1 solution for
Samsung universal7420 devices.
