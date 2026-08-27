/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

#include "ExynosJpegApi.h"

#include <algorithm>
#include <setjmp.h>
#include <stdint.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <vector>

#include <jpeglib.h>
#include <log/log.h>

namespace {

constexpr uint32_t fourcc(char a, char b, char c, char d) {
    return static_cast<uint32_t>(a) | (static_cast<uint32_t>(b) << 8) |
           (static_cast<uint32_t>(c) << 16) | (static_cast<uint32_t>(d) << 24);
}

constexpr uint32_t kYuyv = fourcc('Y', 'U', 'Y', 'V');
constexpr uint32_t kYuy2 = fourcc('Y', 'U', 'Y', '2');

struct ErrorManager {
    jpeg_error_mgr base;
    jmp_buf jump;
};

void onJpegError(j_common_ptr info) {
    auto *error = reinterpret_cast<ErrorManager *>(info->err);
    char message[JMSG_LENGTH_MAX];
    (*info->err->format_message)(info, message);
    ALOGE("libjpeg: %s", message);
    longjmp(error->jump, 1);
}

struct FixedDestination {
    jpeg_destination_mgr base;
    JOCTET *start;
    size_t capacity;
    bool overflow;
};

void initDestination(j_compress_ptr info) {
    auto *dest = reinterpret_cast<FixedDestination *>(info->dest);
    dest->base.next_output_byte = dest->start;
    dest->base.free_in_buffer = dest->capacity;
    dest->overflow = false;
}

boolean emptyDestination(j_compress_ptr info) {
    auto *dest = reinterpret_cast<FixedDestination *>(info->dest);
    dest->overflow = true;
    return FALSE;
}

void finishDestination(j_compress_ptr) {}

class Mapping {
public:
    Mapping(int fd, size_t size, int prot) : m_addr(MAP_FAILED), m_size(size) {
        if (fd >= 0 && size > 0)
            m_addr = mmap(nullptr, size, prot, MAP_SHARED, fd, 0);
    }
    ~Mapping() {
        if (m_addr != MAP_FAILED)
            munmap(m_addr, m_size);
    }
    void *get() const { return m_addr == MAP_FAILED ? nullptr : m_addr; }

private:
    void *m_addr;
    size_t m_size;
};

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

int ExynosJpegEncoder::flagCreate() const { return m_created ? 0 : -1; }
int ExynosJpegEncoder::create() { m_created = true; return 0; }
int ExynosJpegEncoder::destroy() { m_created = false; return 0; }
int ExynosJpegEncoder::updateConfig() { return 0; }
int ExynosJpegEncoder::setCache(int) { return 0; }
void *ExynosJpegEncoder::getJpegConfig() { return this; }

int ExynosJpegEncoder::setJpegConfig(void *config) {
    if (!config)
        return -1;
    auto *source = static_cast<ExynosJpegEncoder *>(config);
    m_color_format = source->m_color_format;
    m_jpeg_format = source->m_jpeg_format;
    m_quality = source->m_quality;
    return 0;
}

int ExynosJpegEncoder::checkInBufType() const { return m_input_type; }
int ExynosJpegEncoder::checkOutBufType() const { return m_output_type; }

int ExynosJpegEncoder::getInBuf(int *fds, int *sizes, int count) {
    if (!fds || !sizes || count <= 0)
        return -1;
    for (int i = 0; i < std::min(count, static_cast<int>(kMaxPlanes)); ++i) {
        fds[i] = m_input_fds[i];
        sizes[i] = m_input_sizes[i];
    }
    return 0;
}

int ExynosJpegEncoder::getOutBuf(int *fd, int *size) {
    if (!fd || !size)
        return -1;
    *fd = m_output_fd;
    *size = m_output_size;
    return 0;
}

int ExynosJpegEncoder::getInBuf(char **buffers, int *sizes, int count) {
    if (!buffers || !sizes || count <= 0)
        return -1;
    for (int i = 0; i < std::min(count, static_cast<int>(kMaxPlanes)); ++i) {
        buffers[i] = m_input_ptrs[i];
        sizes[i] = m_input_sizes[i];
    }
    return 0;
}

int ExynosJpegEncoder::getOutBuf(char **buffer, int *size) {
    if (!buffer || !size)
        return -1;
    *buffer = m_output_ptr;
    *size = m_output_size;
    return 0;
}

int ExynosJpegEncoder::setInBuf(int *fds, int *sizes) {
    if (!fds || !sizes)
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
    if (!buffers || !sizes)
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
    if (!buffer || size <= 0)
        return -1;
    m_output_ptr = buffer;
    m_output_size = size;
    m_output_offset = 0;
    m_output_fd = -1;
    m_output_type = JPEG_BUF_TYPE_USER_PTR;
    return 0;
}

int ExynosJpegEncoder::getSize(int *width, int *height) const {
    if (!width || !height)
        return -1;
    if (m_crop_width > 0 && m_crop_height > 0) {
        *width = m_crop_width;
        *height = m_crop_height;
    } else {
        *width = m_width;
        *height = m_height;
    }
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
    // The driver-reported output crop can be wider than the negotiated
    // picture size (for example 5312x2990 versus a requested 4608x3456)
    // because the capture plane is sensor-aligned. Validate the crop against
    // the plane geometry in encode(), once the real stride is known.
    if (x < 0 || y < 0 || width <= 0 || height <= 0) {
        ALOGE("invalid input crop (%d,%d %dx%d)", x, y, width, height);
        return -1;
    }
    m_crop_x = x;
    m_crop_y = y;
    m_crop_width = width;
    m_crop_height = height;
    return 0;
}

int ExynosJpegEncoder::getInputCrop(int *x, int *y, int *width, int *height) const {
    if (!x || !y || !width || !height)
        return -1;
    *x = m_crop_x;
    *y = m_crop_y;
    *width = m_crop_width;
    *height = m_crop_height;
    return 0;
}

int ExynosJpegEncoder::setJpegFormat(int format) { m_jpeg_format = format; return 0; }
int ExynosJpegEncoder::getColorFormat() const { return m_color_format; }
int ExynosJpegEncoder::setColorFormat(int format) { m_color_format = format; return 0; }

int ExynosJpegEncoder::setColorBufSize(int *sizes, int count) {
    if (!sizes || count <= 0)
        return -1;
    if (m_width <= 0 || m_height <= 0 ||
            (static_cast<uint32_t>(m_color_format) != kYuyv &&
             static_cast<uint32_t>(m_color_format) != kYuy2)) {
        return -1;
    }
    sizes[0] = m_width * m_height * 2;
    m_input_sizes[0] = sizes[0];
    for (int i = 1; i < std::min(count, static_cast<int>(kMaxPlanes)); ++i) {
        sizes[i] = 0;
        m_input_sizes[i] = 0;
    }
    return 0;
}

int ExynosJpegEncoder::setQuality(int quality) {
    m_quality = std::max(1, std::min(quality, 100));
    return 0;
}

int ExynosJpegEncoder::setQuality(const unsigned char[]) {
    m_quality = 90;
    return 0;
}

int ExynosJpegEncoder::getJpegSize() const { return m_jpeg_size; }

int ExynosJpegEncoder::encode() {
    m_jpeg_size = 0;
    if (!m_created || m_width <= 0 || m_height <= 0 || m_input_sizes[0] <= 0 ||
            m_output_size <= m_output_offset) {
        ALOGE("invalid state created=%d size=%dx%d in=%d out=%d offset=%d",
              m_created, m_width, m_height, m_input_sizes[0], m_output_size, m_output_offset);
        return -1;
    }
    if (static_cast<uint32_t>(m_color_format) != kYuyv &&
            static_cast<uint32_t>(m_color_format) != kYuy2) {
        ALOGE("unsupported input fourcc 0x%08x for %dx%d", m_color_format, m_width, m_height);
        return -1;
    }

    Mapping input_mapping(m_input_type == JPEG_BUF_TYPE_DMA_BUF ? m_input_fds[0] : -1,
                          m_input_sizes[0], PROT_READ);
    Mapping output_mapping(m_output_type == JPEG_BUF_TYPE_DMA_BUF ? m_output_fd : -1,
                           m_output_size, PROT_READ | PROT_WRITE);
    auto *input = reinterpret_cast<const uint8_t *>(
            m_input_type == JPEG_BUF_TYPE_DMA_BUF ? input_mapping.get() : m_input_ptrs[0]);
    auto *output_base = reinterpret_cast<uint8_t *>(
            m_output_type == JPEG_BUF_TYPE_DMA_BUF ? output_mapping.get() : m_output_ptr);
    if (!input || !output_base) {
        ALOGE("failed to map JPEG buffers inFd=%d outFd=%d", m_input_fds[0], m_output_fd);
        return -1;
    }

    const size_t tight_stride = static_cast<size_t>(m_width) * 2;
    const size_t needed = tight_stride * m_height;
    if (needed > static_cast<size_t>(m_input_sizes[0])) {
        ALOGE("YUYV buffer too small: need=%zu have=%d", needed, m_input_sizes[0]);
        return -1;
    }
    const size_t crop_stride =
            m_crop_width > 0 ? static_cast<size_t>(m_crop_width) * 2 : tight_stride;

    // The 7420 capture buffers are allocated at the sensor's aligned maximum
    // (rear 5344x4016, front 2592x1944), even when the active JPEG size is
    // smaller.  yuvBuf.size therefore includes both row padding and unused
    // bottom rows.  Recover the allocated row stride from the plane size;
    // treating the plane as tightly packed shifts every following scanline.
    size_t input_stride = tight_stride;
    size_t allocated_height = static_cast<size_t>(m_height);
    size_t best_width_padding = SIZE_MAX;
    const size_t plane_size = static_cast<size_t>(m_input_sizes[0]);
    for (size_t candidate_height = static_cast<size_t>(m_height);
         candidate_height <= 8192; ++candidate_height) {
        if (plane_size % candidate_height != 0)
            continue;
        const size_t candidate_stride = plane_size / candidate_height;
        if ((candidate_stride & 1) != 0 ||
                candidate_stride < std::max(tight_stride, crop_stride))
            continue;
        const size_t candidate_width = candidate_stride / 2;
        // A constrained SCC target (4608) can still live in the rear sensor's
        // 5344-pixel-wide allocation, so horizontal padding may be 736 pixels.
        if ((candidate_width & 15) != 0 || candidate_width > static_cast<size_t>(m_width) + 1024)
            continue;
        const size_t width_padding = candidate_width - static_cast<size_t>(m_width);
        if (width_padding < best_width_padding ||
                (width_padding == best_width_padding && candidate_height < allocated_height)) {
            best_width_padding = width_padding;
            input_stride = candidate_stride;
            allocated_height = candidate_height;
        }
    }

    if (m_crop_width > 0 && m_crop_height > 0) {
        const size_t plane_width = input_stride / 2;
        if (static_cast<size_t>(m_crop_x) + static_cast<size_t>(m_crop_width) > plane_width ||
                static_cast<size_t>(m_crop_y) + static_cast<size_t>(m_crop_height) >
                        allocated_height) {
            ALOGE("input crop (%d,%d %dx%d) outside plane %zux%zu stride=%zu",
                  m_crop_x, m_crop_y, m_crop_width, m_crop_height,
                  plane_width, allocated_height, input_stride);
            return -1;
        }
    }

    const int image_width = m_crop_width > 0 ? m_crop_width : m_width;
    const int image_height = m_crop_height > 0 ? m_crop_height : m_height;
    const uint8_t *active_input = input +
            static_cast<size_t>(m_crop_y) * input_stride +
            static_cast<size_t>(m_crop_x) * 2;

    jpeg_compress_struct compressor = {};
    ErrorManager error = {};
    compressor.err = jpeg_std_error(&error.base);
    error.base.error_exit = onJpegError;
    if (setjmp(error.jump)) {
        jpeg_destroy_compress(&compressor);
        return -1;
    }

    jpeg_create_compress(&compressor);
    FixedDestination destination = {};
    destination.start = output_base + m_output_offset;
    destination.capacity = static_cast<size_t>(m_output_size - m_output_offset);
    destination.base.init_destination = initDestination;
    destination.base.empty_output_buffer = emptyDestination;
    destination.base.term_destination = finishDestination;
    compressor.dest = &destination.base;
    compressor.image_width = image_width;
    compressor.image_height = image_height;
    compressor.input_components = 3;
    compressor.in_color_space = JCS_YCbCr;
    jpeg_set_defaults(&compressor);
    compressor.comp_info[0].h_samp_factor = 2;
    compressor.comp_info[0].v_samp_factor = 1;
    compressor.comp_info[1].h_samp_factor = 1;
    compressor.comp_info[1].v_samp_factor = 1;
    compressor.comp_info[2].h_samp_factor = 1;
    compressor.comp_info[2].v_samp_factor = 1;
    jpeg_set_quality(&compressor, m_quality, TRUE);
    jpeg_start_compress(&compressor, TRUE);

    std::vector<JSAMPLE> row(static_cast<size_t>(image_width) * 3);
    while (compressor.next_scanline < compressor.image_height) {
        const uint8_t *source = active_input +
                static_cast<size_t>(compressor.next_scanline) * input_stride;
        for (int x = 0; x < image_width; x += 2) {
            const uint8_t y0 = source[0];
            const uint8_t cb = source[1];
            const uint8_t y1 = source[2];
            const uint8_t cr = source[3];
            row[3 * x] = y0;
            row[3 * x + 1] = cb;
            row[3 * x + 2] = cr;
            if (x + 1 < image_width) {
                row[3 * (x + 1)] = y1;
                row[3 * (x + 1) + 1] = cb;
                row[3 * (x + 1) + 2] = cr;
            }
            source += 4;
        }
        JSAMPROW rows[] = { row.data() };
        jpeg_write_scanlines(&compressor, rows, 1);
    }
    jpeg_finish_compress(&compressor);
    if (!destination.overflow)
        m_jpeg_size = static_cast<int>(destination.capacity - destination.base.free_in_buffer);
    jpeg_destroy_compress(&compressor);

    if (destination.overflow || m_jpeg_size <= 0) {
        ALOGE("JPEG output overflow capacity=%zu", destination.capacity);
        m_jpeg_size = 0;
        return -1;
    }
    ALOGI("encoded YUYV %dx%d quality=%d size=%d input=%d stride=%zu allocHeight=%zu crop=(%d,%d %dx%d)",
          image_width, image_height, m_quality, m_jpeg_size, m_input_sizes[0],
          input_stride, allocated_height, m_crop_x, m_crop_y, m_crop_width, m_crop_height);
    return 0;
}
