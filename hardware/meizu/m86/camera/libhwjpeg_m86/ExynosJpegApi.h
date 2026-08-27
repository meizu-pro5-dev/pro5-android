/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef M86_EXYNOS_JPEG_API_H
#define M86_EXYNOS_JPEG_API_H

#include <stddef.h>

#define JPEG_CACHE_ON 1
#define JPEG_BUF_TYPE_USER_PTR 1
#define JPEG_BUF_TYPE_DMA_BUF 2

class ExynosJpegEncoder {
public:
    ExynosJpegEncoder();
    virtual ~ExynosJpegEncoder();

    int flagCreate() const;
    virtual int create();
    virtual int destroy();
    int updateConfig();
    int setCache(int value);

    void *getJpegConfig();
    int setJpegConfig(void *config);

    int checkInBufType() const;
    int checkOutBufType() const;

    int getInBuf(int *fds, int *sizes, int count);
    int getOutBuf(int *fd, int *size);
    int getInBuf(char **buffers, int *sizes, int count);
    int getOutBuf(char **buffer, int *size);

    int setInBuf(int *fds, int *sizes);
    int setOutBuf(int fd, int size, int offset = 0);
    int setInBuf(char **buffers, int *sizes);
    int setOutBuf(char *buffer, int size);

    int getSize(int *width, int *height) const;
    int setSize(int width, int height);
    // Record the source crop contract. The Exynos JPEG block has no encoder
    // crop/stride registers, so non-trivial crops are rejected and must be
    // resolved by the capture GSC before encode().
    int setInputCrop(int x, int y, int width, int height);
    int getInputCrop(int *x, int *y, int *width, int *height) const;
    int setJpegFormat(int format);
    int getColorFormat() const;
    int setColorFormat(int format);
    int setColorBufSize(int *sizes, int count);
    int setQuality(int quality);
    int setQuality(const unsigned char table[]);
    int getJpegSize() const;
    int encode();

private:
    enum { kMaxPlanes = 3 };

    bool m_created;
    int m_width;
    int m_height;
    int m_crop_x;
    int m_crop_y;
    int m_crop_width;
    int m_crop_height;
    int m_color_format;
    int m_jpeg_format;
    int m_quality;
    int m_input_type;
    int m_output_type;
    int m_input_fds[kMaxPlanes];
    int m_input_sizes[kMaxPlanes];
    char *m_input_ptrs[kMaxPlanes];
    int m_output_fd;
    int m_output_size;
    int m_output_offset;
    char *m_output_ptr;
    int m_jpeg_size;
};

#endif
