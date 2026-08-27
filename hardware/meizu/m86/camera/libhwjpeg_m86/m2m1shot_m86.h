/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Userspace copy of the Exynos 7420 m2m1shot ABI used by the m86 kernel.
 */

#ifndef M86_M2M1SHOT_H
#define M86_M2M1SHOT_H

#include <linux/ioctl.h>
#include <linux/types.h>
#include <linux/videodev2.h>

#define M2M1SHOT_MAX_PLANES 3

struct m2m1shot_pix_format {
    __u32 fmt;
    __u32 width;
    __u32 height;
    struct v4l2_rect crop;
};

enum m2m1shot_buffer_type {
    M2M1SHOT_BUFFER_NONE,
    M2M1SHOT_BUFFER_DMABUF,
    M2M1SHOT_BUFFER_USERPTR,
};

struct m2m1shot_buffer_plane {
    union {
        __s32 fd;
        unsigned long userptr;
    };
    size_t len;
};

struct m2m1shot_buffer {
    struct m2m1shot_buffer_plane plane[M2M1SHOT_MAX_PLANES];
    __u8 type;
    __u8 num_planes;
};

struct m2m1shot_operation {
    union {
        __s16 quality_level;
        __u16 restart_interval;
    };
    union {
        __s16 rotate;
        struct {
            unsigned short qtbl_comp1 : 2;
            unsigned short qtbl_comp2 : 2;
            unsigned short qtbl_comp3 : 2;
            unsigned short qtbl_comp4 : 2;
            unsigned short htbl_dccomp1 : 1;
            unsigned short htbl_accomp1 : 1;
            unsigned short htbl_dccomp2 : 1;
            unsigned short htbl_accomp2 : 1;
            unsigned short htbl_dccomp3 : 1;
            unsigned short htbl_accomp3 : 1;
        } jpeg_tbls;
    };
    __u32 op;
};

struct m2m1shot {
    struct m2m1shot_pix_format fmt_out;
    struct m2m1shot_pix_format fmt_cap;
    struct m2m1shot_buffer buf_out;
    struct m2m1shot_buffer buf_cap;
    struct m2m1shot_operation op;
    unsigned long reserved[2];
};

#define M2M1SHOT_IOC_PROCESS _IOWR('M', 0, struct m2m1shot)

#endif  // M86_M2M1SHOT_H
