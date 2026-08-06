/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

#define LOG_TAG "lights.m86"

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <hardware/lights.h>
#include <log/log.h>

#define BACKLIGHT_FILE \
    "/sys/devices/13930000.decon_fb/backlight/pwm-backlight.0/brightness"
#define INDICATOR_FILE "/sys/class/leds/m86_led/brightness"

/*
 * The Meizu LP5562 driver encodes its operating mode in bits 8..11 and the
 * direct PWM value in bits 0..7. These values are defined by the maintained
 * m86 kernel's leds-lp5562.c, not by a Galaxy device.
 */
#define M86_LED_MODE_CURRENT 0x100
#define M86_LED_MODE_BREATH 0x200
#define M86_LED_MODE_TIMED_BLINK 0x400

static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static struct light_state_t g_attention;
static struct light_state_t g_battery;
static struct light_state_t g_notification;

static int write_int(const char *path, int value)
{
    char buffer[24];
    int fd;
    int length;
    int saved_errno;
    ssize_t written;

    length = snprintf(buffer, sizeof(buffer), "%d\n", value);
    if (length < 0 || (size_t)length >= sizeof(buffer)) {
        return -EINVAL;
    }

    fd = open(path, O_WRONLY | O_CLOEXEC);
    if (fd < 0) {
        saved_errno = errno;
        ALOGE("cannot open %s: %s", path, strerror(saved_errno));
        return -saved_errno;
    }

    written = write(fd, buffer, (size_t)length);
    saved_errno = errno;
    close(fd);
    if (written < 0) {
        ALOGE("cannot write %s: %s", path, strerror(saved_errno));
        return -saved_errno;
    }
    if (written != (ssize_t)length) {
        ALOGE("short write to %s: %zd of %d", path, written, length);
        return -EIO;
    }

    return 0;
}

static bool is_lit(const struct light_state_t *state)
{
    return (state->color & 0x00ffffff) != 0;
}

static int rgb_to_brightness(const struct light_state_t *state)
{
    int blue = state->color & 0xff;
    int green = (state->color >> 8) & 0xff;
    int red = (state->color >> 16) & 0xff;
    int brightness = (77 * red + 150 * green + 29 * blue) >> 8;

    /* Preserve a visible result for very dim nonzero colors. */
    if (brightness == 0 && is_lit(state)) {
        brightness = 1;
    }
    return brightness;
}

static int encode_indicator(const struct light_state_t *state, bool battery)
{
    int brightness;
    int mode = M86_LED_MODE_CURRENT;

    if (!is_lit(state)) {
        return 0;
    }

    brightness = rgb_to_brightness(state);
    if (state->flashMode != LIGHT_FLASH_NONE &&
            state->flashOnMS > 0 && state->flashOffMS > 0) {
        mode = M86_LED_MODE_TIMED_BLINK;
    } else if (battery) {
        /* Match the stock charging indication without a userspace daemon. */
        mode = M86_LED_MODE_BREATH;
    }

    return mode | brightness;
}

static int update_indicator_locked(void)
{
    const struct light_state_t *state = &g_battery;
    bool battery = true;

    /* A user-visible notification must not be hidden by the charging LED. */
    if (is_lit(&g_notification)) {
        state = &g_notification;
        battery = false;
    } else if (is_lit(&g_attention)) {
        state = &g_attention;
        battery = false;
    }

    return write_int(INDICATOR_FILE, encode_indicator(state, battery));
}

static int set_light_backlight(struct light_device_t *device,
        const struct light_state_t *state)
{
    int result;

    (void)device;
    pthread_mutex_lock(&g_lock);
    result = write_int(BACKLIGHT_FILE, rgb_to_brightness(state));
    pthread_mutex_unlock(&g_lock);
    return result;
}

static int set_light_attention(struct light_device_t *device,
        const struct light_state_t *state)
{
    int result;

    (void)device;
    pthread_mutex_lock(&g_lock);
    g_attention = *state;
    result = update_indicator_locked();
    pthread_mutex_unlock(&g_lock);
    return result;
}

static int set_light_battery(struct light_device_t *device,
        const struct light_state_t *state)
{
    int result;

    (void)device;
    pthread_mutex_lock(&g_lock);
    g_battery = *state;
    result = update_indicator_locked();
    pthread_mutex_unlock(&g_lock);
    return result;
}

static int set_light_notifications(struct light_device_t *device,
        const struct light_state_t *state)
{
    int result;

    (void)device;
    pthread_mutex_lock(&g_lock);
    g_notification = *state;
    result = update_indicator_locked();
    pthread_mutex_unlock(&g_lock);
    return result;
}

static int close_lights(struct hw_device_t *device)
{
    free(device);
    return 0;
}

static int open_lights(const struct hw_module_t *module, const char *name,
        struct hw_device_t **device)
{
    int (*set_light)(struct light_device_t *, const struct light_state_t *);
    struct light_device_t *light;

    if (strcmp(name, LIGHT_ID_BACKLIGHT) == 0) {
        set_light = set_light_backlight;
    } else if (strcmp(name, LIGHT_ID_ATTENTION) == 0) {
        set_light = set_light_attention;
    } else if (strcmp(name, LIGHT_ID_BATTERY) == 0) {
        set_light = set_light_battery;
    } else if (strcmp(name, LIGHT_ID_NOTIFICATIONS) == 0) {
        set_light = set_light_notifications;
    } else {
        return -EINVAL;
    }

    light = calloc(1, sizeof(*light));
    if (light == NULL) {
        return -ENOMEM;
    }

    light->common.tag = HARDWARE_DEVICE_TAG;
    light->common.version = LIGHTS_DEVICE_API_VERSION_2_0;
    light->common.module = (struct hw_module_t *)module;
    light->common.close = close_lights;
    light->set_light = set_light;
    *device = &light->common;
    return 0;
}

static struct hw_module_methods_t lights_module_methods = {
    .open = open_lights,
};

struct hw_module_t HAL_MODULE_INFO_SYM = {
    .tag = HARDWARE_MODULE_TAG,
    .version_major = 1,
    .version_minor = 0,
    .id = LIGHTS_HARDWARE_MODULE_ID,
    .name = "Meizu PRO 5 lights HAL",
    .author = "The LineageOS Project",
    .methods = &lights_module_methods,
};
