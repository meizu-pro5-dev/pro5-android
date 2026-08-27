/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

#include "ExynosJpegApi.h"
#include "m2m1shot_m86.h"

#include <algorithm>
#include <cerrno>
#include <cstdint>
#include <cstring>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include <log/log.h>

namespace {

constexpr char kJpegNode[] = "/dev/m2m1shot_jpeg";

constexpr uint32_t fourcc(char a, char b, char c, char d) {
    return static_cast<uint32_t>(a) | (static_cast<uint32_t>(b) << 8) |
           (static_cast<uint32_t>(c) << 16) | (static_cast<uint32_t>(d) << 24);
}

constexpr uint32_t kYuyv = fourcc('Y', 'U', 'Y', 'V');
constexpr uint32_t kYuy2 = fourcc('Y', 'U', 'Y', '2');
constexpr uint32_t kNv12 = fourcc('N', 'V', '1', '2');
constexpr uint32_t kNv21 = fourcc('N', 'V', '2', '1');
constexpr uint32_t kNv12m = fourcc('N', 'M', '1', '2');
constexpr uint32_t kNv21m = fourcc('N', 'M', '2', '1');

int getInputPlaneCount(uint32_t format) {
    switch (format) {
        case kYuyv:
        case kYuy2:
        case kNv12:
        case kNv21:
            return 1;
        case kNv12m:
        case kNv21m:
            return 2;
        default:
            return 0;
    }
}

int processM2M1Shot(int fd, struct m2m1shot *task) {
    int result;
    do {
        result = ioctl(fd, M2M1SHOT_IOC_PROCESS, task);
    } while (result < 0 && errno == EINTR);
    return result;
}

}  // namespace

ExynosJpegEncoder::ExynosJpegEncoder()
    : m_created(false),
      m_width(0),
      m_height(0),
      m_crop_x(0),
      m_crop_y(0),
      m_crop_width(0),
      m_crop_height(0),
      m_color_format(0),
      m_jpeg_format(0),
      m_quality(90),
      m_input_type(0),
      m_output_type(0),
      m_output_fd(-1),
      m_output_size(0),
      m_output_offset(0),
      m_output_ptr(nullptr),
      m_jpeg_size(0) {
    std::fill_n(m_input_fds, kMaxPlanes, -1);
    std::fill_n(m_input_sizes, kMaxPlanes, 0);
    std::fill_n(m_input_ptrs, kMaxPlanes, nullptr);
}

ExynosJpegEncoder::~ExynosJpegEncoder() {
    destroy();
}

int ExynosJpegEncoder::flagCreate() const {
    return m_created ? 0 : -1;
}

int ExynosJpegEncoder::create() {
    int fd = open(kJpegNode, O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        ALOGE("open %s failed: %s", kJpegNode, strerror(errno));
        return -1;
    }
    close(fd);
    m_created = true;
    return 0;
}

int ExynosJpegEncoder::destroy() {
    m_created = false;
    return 0;
}

int ExynosJpegEncoder::updateConfig() {
    return 0;
}

int ExynosJpegEncoder::setCache(int) {
    return 0;
}

void *ExynosJpegEncoder::getJpegConfig() {
    return this;
}

int ExynosJpegEncoder::setJpegConfig(void *config) {
    if (config == nullptr)
        return -1;

    auto *source = static_cast<ExynosJpegEncoder *>(config);
    m_color_format = source->m_color_format;
    m_jpeg_format = source->m_jpeg_format;
    m_quality = source->m_quality;
    return 0;
}

int ExynosJpegEncoder::checkInBufType() const {
    return m_input_type;
}

int ExynosJpegEncoder::checkOutBufType() const {
    return m_output_type;
}

int ExynosJpegEncoder::getInBuf(int *fds, int *sizes, int count) {
    if (fds == nullptr || sizes == nullptr || count <= 0)
        return -1;

    for (int i = 0; i < std::min(count, static_cast<int>(kMaxPlanes)); ++i) {
        fds[i] = m_input_fds[i];
        sizes[i] = m_input_sizes[i];
    }
    return 0;
}

int ExynosJpegEncoder::getOutBuf(int *fd, int *size) {
    if (fd == nullptr || size == nullptr)
        return -1;
    *fd = m_output_fd;
    *size = m_output_size;
    return 0;
}

int ExynosJpegEncoder::getInBuf(char **buffers, int *sizes, int count) {
    if (buffers == nullptr || sizes == nullptr || count <= 0)
        return -1;

    for (int i = 0; i < std::min(count, static_cast<int>(kMaxPlanes)); ++i) {
        buffers[i] = m_input_ptrs[i];
        sizes[i] = m_input_sizes[i];
    }
    return 0;
}

int ExynosJpegEncoder::getOutBuf(char **buffer, int *size) {
    if (buffer == nullptr || size == nullptr)
        return -1;
    *buffer = m_output_ptr;
    *size = m_output_size;
    return 0;
}

int ExynosJpegEncoder::setInBuf(int *fds, int *sizes) {
    if (fds == nullptr || sizes == nullptr)
        return -1;

    for (int i = 0; i < kMaxPlanes; ++i) {
        m_input_fds[i] = fds[i];
        m_input_sizes[i] = sizes[i];
        m_input_ptrs[i] = nullptr;
    }
    m_input_type = JPEG_BUF_TYPE_DMA_BUF;
    return 0;
}

int ExynosJpegEncoder::setOutBuf(int fd, int size, int offset) {
    if (fd < 0 || size <= 0 || offset < 0 || offset >= size)
        return -1;

    m_output_fd = fd;
    m_output_size = size;
    m_output_offset = offset;
    m_output_ptr = nullptr;
    m_output_type = JPEG_BUF_TYPE_DMA_BUF;
    return 0;
}

int ExynosJpegEncoder::setInBuf(char **buffers, int *sizes) {
    if (buffers == nullptr || sizes == nullptr)
        return -1;

    for (int i = 0; i < kMaxPlanes; ++i) {
        m_input_ptrs[i] = buffers[i];
        m_input_sizes[i] = sizes[i];
        m_input_fds[i] = -1;
    }
    m_input_type = JPEG_BUF_TYPE_USER_PTR;
    return 0;
}

int ExynosJpegEncoder::setOutBuf(char *buffer, int size) {
    if (buffer == nullptr || size <= 0)
        return -1;

    m_output_ptr = buffer;
    m_output_size = size;
    m_output_offset = 0;
    m_output_fd = -1;
    m_output_type = JPEG_BUF_TYPE_USER_PTR;
    return 0;
}

int ExynosJpegEncoder::getSize(int *width, int *height) const {
    if (width == nullptr || height == nullptr)
        return -1;
    *width = m_width;
    *height = m_height;
    return 0;
}

int ExynosJpegEncoder::setSize(int width, int height) {
    if (width <= 0 || height <= 0)
        return -1;

    m_width = width;
    m_height = height;
    m_crop_x = 0;
    m_crop_y = 0;
    m_crop_width = 0;
    m_crop_height = 0;
    return 0;
}

int ExynosJpegEncoder::setInputCrop(int x, int y, int width, int height) {
    if (x < 0 || y < 0 || width <= 0 || height <= 0)
        return -1;
    m_crop_x = x;
    m_crop_y = y;
    m_crop_width = width;
    m_crop_height = height;
    return 0;
}

int ExynosJpegEncoder::getInputCrop(int *x, int *y, int *width, int *height) const {
    if (x == nullptr || y == nullptr || width == nullptr || height == nullptr)
        return -1;
    *x = m_crop_x;
    *y = m_crop_y;
    *width = m_crop_width;
    *height = m_crop_height;
    return 0;
}

int ExynosJpegEncoder::setJpegFormat(int format) {
    m_jpeg_format = format;
    return 0;
}

int ExynosJpegEncoder::getColorFormat() const {
    return m_color_format;
}

int ExynosJpegEncoder::setColorFormat(int format) {
    m_color_format = format;
    return 0;
}

int ExynosJpegEncoder::setColorBufSize(int *sizes, int count) {
    if (sizes == nullptr || count <= 0 || m_width <= 0 || m_height <= 0)
        return -1;
    const uint32_t format = static_cast<uint32_t>(m_color_format);
    const int planeCount = getInputPlaneCount(format);
    if (planeCount == 0 || count < planeCount) {
        ALOGE("unsupported input format %#x/count %d for buffer sizing",
              static_cast<unsigned int>(m_color_format), count);
        return -1;
    }

    if (format == kYuyv || format == kYuy2) {
        sizes[0] = m_width * m_height * 2;
    } else {
        sizes[0] = m_width * m_height;
        if (format == kNv12 || format == kNv21)
            sizes[0] += sizes[0] / 2;
    }
    m_input_sizes[0] = sizes[0];
    int firstUnusedPlane = 1;
    if ((format == kNv12m || format == kNv21m) && count > 1) {
        sizes[1] = m_width * m_height / 2;
        m_input_sizes[1] = sizes[1];
        firstUnusedPlane = 2;
    }
    for (int i = firstUnusedPlane;
         i < std::min(count, static_cast<int>(kMaxPlanes)); ++i) {
        sizes[i] = 0;
        m_input_sizes[i] = 0;
    }
    return 0;
}

int ExynosJpegEncoder::setQuality(int quality) {
    if (quality < 1 || quality > 100)
        return -1;
    m_quality = quality;
    return 0;
}

int ExynosJpegEncoder::setQuality(const unsigned char[]) {
    ALOGW("custom JPEG quantization tables are not supported; using quality %d", m_quality);
    return 0;
}

int ExynosJpegEncoder::getJpegSize() const {
    return m_jpeg_size;
}

int ExynosJpegEncoder::encode() {
    m_jpeg_size = 0;

    if (!m_created || m_width <= 0 || m_height <= 0 || m_input_sizes[0] <= 0 ||
            m_output_size <= 0) {
        ALOGE("invalid JPEG state: created=%d size=%dx%d input=%d output=%d",
              m_created, m_width, m_height, m_input_sizes[0], m_output_size);
        return -1;
    }
    if (m_output_offset != 0) {
        ALOGE("m2m1shot JPEG does not support output offset %d", m_output_offset);
        return -1;
    }
    const uint32_t inputFormat = static_cast<uint32_t>(m_color_format);
    const int inputPlaneCount = getInputPlaneCount(inputFormat);
    if (inputPlaneCount == 0) {
        ALOGE("unsupported m2m1shot input format %#x",
              static_cast<unsigned int>(m_color_format));
        return -1;
    }
    if (m_crop_width > 0 && (m_crop_x != 0 || m_crop_y != 0 ||
            m_crop_width != m_width || m_crop_height != m_height)) {
        ALOGE("hardware JPEG requires tightly packed input; unsupported crop (%d,%d %dx%d) for %dx%d",
              m_crop_x, m_crop_y, m_crop_width, m_crop_height, m_width, m_height);
        return -1;
    }

    struct m2m1shot task = {};
    // YUY2 is a userspace synonym; the Exynos driver registers YUYV.
    task.fmt_out.fmt = static_cast<__u32>(inputFormat == kYuy2 ? kYuyv : inputFormat);
    task.fmt_out.width = static_cast<__u32>(m_width);
    task.fmt_out.height = static_cast<__u32>(m_height);
    task.fmt_out.crop.width = static_cast<__u32>(m_width);
    task.fmt_out.crop.height = static_cast<__u32>(m_height);
    task.fmt_cap.fmt = static_cast<__u32>(m_jpeg_format);
    task.fmt_cap.width = static_cast<__u32>(m_width);
    task.fmt_cap.height = static_cast<__u32>(m_height);
    task.fmt_cap.crop.width = static_cast<__u32>(m_width);
    task.fmt_cap.crop.height = static_cast<__u32>(m_height);
    task.op.quality_level = static_cast<__s16>(m_quality);

    task.buf_out.num_planes = static_cast<__u8>(inputPlaneCount);
    if (m_input_type == JPEG_BUF_TYPE_DMA_BUF) {
        task.buf_out.type = M2M1SHOT_BUFFER_DMABUF;
        for (int i = 0; i < inputPlaneCount; ++i) {
            if (m_input_fds[i] < 0 || m_input_sizes[i] <= 0)
                return -1;
            task.buf_out.plane[i].fd = m_input_fds[i];
            task.buf_out.plane[i].len = static_cast<size_t>(m_input_sizes[i]);
        }
    } else if (m_input_type == JPEG_BUF_TYPE_USER_PTR) {
        task.buf_out.type = M2M1SHOT_BUFFER_USERPTR;
        for (int i = 0; i < inputPlaneCount; ++i) {
            if (m_input_ptrs[i] == nullptr || m_input_sizes[i] <= 0)
                return -1;
            task.buf_out.plane[i].userptr =
                    reinterpret_cast<unsigned long>(m_input_ptrs[i]);
            task.buf_out.plane[i].len = static_cast<size_t>(m_input_sizes[i]);
        }
    } else {
        return -1;
    }

    task.buf_cap.num_planes = 1;
    task.buf_cap.plane[0].len = static_cast<size_t>(m_output_size);
    if (m_output_type == JPEG_BUF_TYPE_DMA_BUF) {
        if (m_output_fd < 0)
            return -1;
        task.buf_cap.type = M2M1SHOT_BUFFER_DMABUF;
        task.buf_cap.plane[0].fd = m_output_fd;
    } else if (m_output_type == JPEG_BUF_TYPE_USER_PTR) {
        if (m_output_ptr == nullptr)
            return -1;
        task.buf_cap.type = M2M1SHOT_BUFFER_USERPTR;
        task.buf_cap.plane[0].userptr =
                reinterpret_cast<unsigned long>(m_output_ptr);
    } else {
        return -1;
    }

    int fd = open(kJpegNode, O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        ALOGE("open %s failed: %s", kJpegNode, strerror(errno));
        return -1;
    }
    int result = processM2M1Shot(fd, &task);
    int saved_errno = errno;
    close(fd);
    if (result < 0) {
        ALOGE("M2M1SHOT_IOC_PROCESS failed for %dx%d: %s",
              m_width, m_height, strerror(saved_errno));
        return -1;
    }

    if (task.buf_cap.plane[0].len == 0 ||
            task.buf_cap.plane[0].len > static_cast<size_t>(m_output_size)) {
        ALOGE("invalid hardware JPEG size %zu (capacity %d)",
              task.buf_cap.plane[0].len, m_output_size);
        return -1;
    }

    m_jpeg_size = static_cast<int>(task.buf_cap.plane[0].len);
    ALOGI("hardware JPEG encoded %dx%d input=%#x output=%#x quality=%d size=%d",
          m_width, m_height, static_cast<unsigned int>(m_color_format),
          static_cast<unsigned int>(m_jpeg_format), m_quality, m_jpeg_size);
    return 0;
}
