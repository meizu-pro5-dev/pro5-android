# m86 gralloc adapter

This module compiles the unmodified LineageOS 17.1 Exynos gralloc allocator,
mapper, and format chooser, but owns the PRO 5 fbdev post path locally. The
local framebuffer implementation is derived from
`hardware/samsung_slsi/exynos/gralloc/framebuffer.cpp` at commit
`6dce0ba9f592d75ca5747464f09669cd76c8c81e` under Apache-2.0.

The local implementation validates mapper results and copy bounds and uses the
persistent framebuffer mapping established by `init_fb`. This replaces the
former patch applied directly to the Samsung project.
