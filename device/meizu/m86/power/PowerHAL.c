/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

#define LOG_TAG "m86-power-hal"

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>

#include <hardware/hardware.h>
#include <hardware/power.h>
#include <log/log.h>

#define CPU0_BOOSTPULSE \
    "/sys/devices/system/cpu/cpu0/cpufreq/interactive/boostpulse"
#define CPU4_BOOSTPULSE \
    "/sys/devices/system/cpu/cpu4/cpufreq/interactive/boostpulse"
#define CPU0_BOOST_DURATION \
    "/sys/devices/system/cpu/cpu0/cpufreq/interactive/boostpulse_duration"
#define CPU4_BOOST_DURATION \
    "/sys/devices/system/cpu/cpu4/cpufreq/interactive/boostpulse_duration"
#define HOTPLUG_PROFILE \
    "/sys/module/exynos_march_cpu_hotplug/parameters/current_profile_no"
#define HOTPLUG_BIG_CLUSTER \
    "/sys/module/exynos_march_cpu_hotplug/parameters/cl1_booster"
#define HOTPLUG_BIG_MINIMUM \
    "/sys/module/exynos_march_cpu_hotplug/parameters/min_cpu_boosted"
#define NAVIGATION_SWITCH "/proc/nav_switch"

#define PROFILE_BALANCED "1"
#define PROFILE_ECO "2"
#define BOOST_DURATION_US "400000"

struct m86_power_module {
  struct power_module base;
  pthread_mutex_t lock;
  bool low_power;
};

static int write_node(const char *path, const char *value) {
  int fd;
  ssize_t expected;
  ssize_t written;

  fd = open(path, O_WRONLY | O_CLOEXEC);
  if (fd < 0) {
    ALOGV("Cannot open %s: %s", path, strerror(errno));
    return -errno;
  }

  expected = (ssize_t)strlen(value);
  do {
    written = write(fd, value, (size_t)expected);
  } while (written < 0 && errno == EINTR);

  if (written != expected) {
    int error = written < 0 ? errno : EIO;
    ALOGW("Cannot write %s: %s", path, strerror(error));
    close(fd);
    return -error;
  }

  close(fd);
  return 0;
}

static void m86_power_init(struct power_module *module) {
  struct m86_power_module *m86 = (struct m86_power_module *)module;

  pthread_mutex_lock(&m86->lock);
  m86->low_power = false;
  write_node(CPU0_BOOST_DURATION, BOOST_DURATION_US);
  write_node(CPU4_BOOST_DURATION, BOOST_DURATION_US);
  write_node(HOTPLUG_PROFILE, PROFILE_BALANCED);
  write_node(HOTPLUG_BIG_CLUSTER, "1");
  write_node(HOTPLUG_BIG_MINIMUM, "1");
  pthread_mutex_unlock(&m86->lock);
}

static void m86_set_interactive(struct power_module *module, int on) {
  (void)module;
  write_node(NAVIGATION_SWITCH, on ? "1" : "0");
}

static void m86_set_low_power(struct m86_power_module *m86, bool enabled) {
  if (m86->low_power == enabled) {
    return;
  }

  write_node(HOTPLUG_PROFILE, enabled ? PROFILE_ECO : PROFILE_BALANCED);
  write_node(HOTPLUG_BIG_CLUSTER, enabled ? "0" : "1");
  write_node(HOTPLUG_BIG_MINIMUM, enabled ? "0" : "1");
  m86->low_power = enabled;
}

static void m86_power_hint(struct power_module *module, power_hint_t hint,
                           void *data) {
  struct m86_power_module *m86 = (struct m86_power_module *)module;

  switch (hint) {
    case POWER_HINT_INTERACTION: {
      bool low_power;

      pthread_mutex_lock(&m86->lock);
      low_power = m86->low_power;
      pthread_mutex_unlock(&m86->lock);
      if (!low_power) {
        write_node(CPU0_BOOSTPULSE, "1");
        write_node(CPU4_BOOSTPULSE, "1");
      }
      break;
    }
    case POWER_HINT_LOW_POWER:
      pthread_mutex_lock(&m86->lock);
      m86_set_low_power(m86, data != NULL && *(int32_t *)data != 0);
      pthread_mutex_unlock(&m86->lock);
      break;
    default:
      break;
  }
}

static struct hw_module_methods_t power_module_methods = {
    .open = NULL,
};

struct m86_power_module HAL_MODULE_INFO_SYM = {
    .base =
        {
            .common =
                {
                    .tag = HARDWARE_MODULE_TAG,
                    .module_api_version = POWER_MODULE_API_VERSION_0_2,
                    .hal_api_version = HARDWARE_HAL_API_VERSION,
                    .id = POWER_HARDWARE_MODULE_ID,
                    .name = "Meizu PRO 5 Power HAL",
                    .author = "The LineageOS Project",
                    .methods = &power_module_methods,
                },
            .init = m86_power_init,
            .setInteractive = m86_set_interactive,
            .powerHint = m86_power_hint,
        },
    .lock = PTHREAD_MUTEX_INITIALIZER,
    .low_power = false,
};
