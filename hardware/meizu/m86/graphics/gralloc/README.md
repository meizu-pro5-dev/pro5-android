# m86 gralloc adapter

This module compiles the `lineage-19.1-old-r15` Nougat gralloc contract
(samungexynos7420 `android_hardware_samsung_slsi-linaro_exynos` commit
`6e74c51a7f147794044c42db29f93d3700395ede`, Apache-2.0) instead of the newer
lineage-19.1 linaro layout. The old contract produces the private-handle ABI
required by the Flyme r15p0 `libGLES_mali.so` blob:

- `sizeof(private_handle_t) == 160`
- `numFds + numInts == 37`
- `magic == 0x3141592` at offset `0x18`
- `internal_format` at offset `0x90`

`a10-contract/` carries the imported allocator/mapper/chooser/header. The m86
fbdev post path is owned locally; the local framebuffer implementation is
derived from the same Nougat `framebuffer.cpp` and validates mapper results,
copy bounds, and the persistent framebuffer mapping established by `init_fb`.
