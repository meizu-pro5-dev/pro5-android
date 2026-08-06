/*
 * Copyright (C) 2016 faust93 <monumentum@gmail.com>
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 *
 * The sensor transport and image matcher are the last public m86 FPC1020
 * implementation. Matching and template storage occur in normal Android
 * userspace because no compatible m86 fingerprint trusted application is
 * available. The generated authentication token therefore has no TEE-backed
 * HMAC and must not be treated as a strong biometric or used for auth-bound
 * Keystore keys.
 */

#define LOG_TAG "m86-fingerprint-hal"

#include <endian.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#include <hardware/fingerprint.h>
#include <hardware/hardware.h>
#include <log/log.h>

#include "fprint.h"

#define MAX_TEMPLATES 5
#define METADATA_MAGIC UINT32_C(0x4d383646)
#define METADATA_VERSION UINT32_C(1)
#define METADATA_NAME ".m86-fingerprint-metadata"

enum worker_operation {
  OPERATION_IDLE = 0,
  OPERATION_ENROLL,
  OPERATION_AUTHENTICATE,
};

struct fingerprint_metadata {
  uint32_t magic;
  uint32_t version;
  uint64_t secure_user_id;
  uint64_t authenticator_id;
};

struct m86_fingerprint_device {
  fingerprint_device_t device;
  pthread_mutex_t lock;
  pthread_t worker;
  bool worker_active;
  bool worker_joinable;
  bool cancel_requested;
  enum worker_operation operation;
  uint32_t active_gid;
  uint32_t enroll_timeout_sec;
  uint64_t challenge;
  uint64_t operation_id;
  uint64_t secure_user_id;
  uint64_t authenticator_id;
  char store_path[PATH_MAX];
  struct fp_dev *sensor;
  /* libfprint identify galleries are NULL terminated. */
  struct fp_print_data *templates[MAX_TEMPLATES + 1];
  uint32_t template_ids[MAX_TEMPLATES];
  size_t template_count;
};

static int read_exact(int fd, void *buffer, size_t length) {
  uint8_t *cursor = buffer;

  while (length > 0) {
    ssize_t count = read(fd, cursor, length);
    if (count < 0 && errno == EINTR) {
      continue;
    }
    if (count <= 0) {
      return count == 0 ? -EIO : -errno;
    }
    cursor += count;
    length -= (size_t)count;
  }
  return 0;
}

static int write_exact(int fd, const void *buffer, size_t length) {
  const uint8_t *cursor = buffer;

  while (length > 0) {
    ssize_t count = write(fd, cursor, length);
    if (count < 0 && errno == EINTR) {
      continue;
    }
    if (count <= 0) {
      return count == 0 ? -EIO : -errno;
    }
    cursor += count;
    length -= (size_t)count;
  }
  return 0;
}

static uint64_t random_u64(void) {
  uint64_t value = 0;
  int fd = open("/dev/urandom", O_RDONLY | O_CLOEXEC);

  if (fd < 0) {
    ALOGE("Cannot open /dev/urandom: %s", strerror(errno));
    return 0;
  }
  int result = read_exact(fd, &value, sizeof(value));
  if (result < 0) {
    ALOGE("Cannot read /dev/urandom: %d", result);
    close(fd);
    return 0;
  }
  close(fd);
  return value == 0 ? UINT64_C(1) : value;
}

static int metadata_path(const struct m86_fingerprint_device *device,
                         char *path, size_t path_size) {
  int length;

  if (device->store_path[0] == '\0') {
    return -EINVAL;
  }
  length = snprintf(path, path_size, "%s/%s", device->store_path,
                    METADATA_NAME);
  return length < 0 || (size_t)length >= path_size ? -ENAMETOOLONG : 0;
}

static int load_metadata_locked(struct m86_fingerprint_device *device) {
  struct fingerprint_metadata metadata;
  char path[PATH_MAX];
  int fd;
  int result;

  device->secure_user_id = 0;
  device->authenticator_id = 0;
  result = metadata_path(device, path, sizeof(path));
  if (result < 0) {
    return result;
  }

  fd = open(path, O_RDONLY | O_CLOEXEC);
  if (fd < 0) {
    return errno == ENOENT ? 0 : -errno;
  }
  result = read_exact(fd, &metadata, sizeof(metadata));
  close(fd);
  if (result < 0 || metadata.magic != METADATA_MAGIC ||
      metadata.version != METADATA_VERSION) {
    ALOGW("Ignoring invalid fingerprint metadata: %s", path);
    return result < 0 ? result : -EINVAL;
  }

  device->secure_user_id = metadata.secure_user_id;
  device->authenticator_id = metadata.authenticator_id;
  return 0;
}

static int save_metadata_locked(const struct m86_fingerprint_device *device) {
  const struct fingerprint_metadata metadata = {
      .magic = METADATA_MAGIC,
      .version = METADATA_VERSION,
      .secure_user_id = device->secure_user_id,
      .authenticator_id = device->authenticator_id,
  };
  char path[PATH_MAX];
  char temporary[PATH_MAX];
  int fd;
  int length;
  int result;

  result = metadata_path(device, path, sizeof(path));
  if (result < 0) {
    return result;
  }
  length = snprintf(temporary, sizeof(temporary), "%s.tmp", path);
  if (length < 0 || (size_t)length >= sizeof(temporary)) {
    return -ENAMETOOLONG;
  }

  fd = open(temporary, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
  if (fd < 0) {
    return -errno;
  }
  result = write_exact(fd, &metadata, sizeof(metadata));
  if (result == 0 && fsync(fd) < 0) {
    result = -errno;
  }
  if (close(fd) < 0 && result == 0) {
    result = -errno;
  }
  if (result == 0 && rename(temporary, path) < 0) {
    result = -errno;
  }
  if (result < 0) {
    unlink(temporary);
  }
  return result;
}

static void free_templates_locked(struct m86_fingerprint_device *device) {
  size_t index;

  for (index = 0; index < device->template_count; ++index) {
    fp_print_data_free(device->templates[index]);
    device->templates[index] = NULL;
    device->template_ids[index] = 0;
  }
  device->template_count = 0;
}

static int load_templates_locked(struct m86_fingerprint_device *device) {
  struct fp_dscv_print **discovered;
  size_t index;

  free_templates_locked(device);
  discovered = fp_discover_prints(device->store_path);
  if (discovered == NULL) {
    return 0;
  }

  for (index = 0; discovered[index] != NULL; ++index) {
    struct fp_print_data *data = NULL;
    uint32_t fid = (uint32_t)fp_dscv_print_get_finger(discovered[index]);

    if (fid == 0 || fid > 10 || device->template_count >= MAX_TEMPLATES) {
      continue;
    }
    if (fp_print_data_from_dscv_print(discovered[index], &data) != 0 ||
        data == NULL || !fp_dev_supports_print_data(device->sensor, data)) {
      fp_print_data_free(data);
      ALOGW("Skipping invalid FPC template %u", fid);
      continue;
    }
    device->templates[device->template_count] = data;
    device->template_ids[device->template_count] = fid;
    ++device->template_count;
  }
  fp_dscv_prints_free(discovered);
  return 0;
}

static int rotate_authenticator_locked(struct m86_fingerprint_device *device) {
  if (device->template_count == 0) {
    device->authenticator_id = 0;
  } else {
    device->authenticator_id = random_u64();
    if (device->authenticator_id == 0) {
      return -EIO;
    }
  }
  return save_metadata_locked(device);
}

static void notify_message(struct m86_fingerprint_device *device,
                           const fingerprint_msg_t *message) {
  fingerprint_notify_t callback;

  pthread_mutex_lock(&device->lock);
  callback = device->device.notify;
  pthread_mutex_unlock(&device->lock);
  if (callback != NULL) {
    callback(message);
  }
}

static void notify_error(struct m86_fingerprint_device *device,
                         fingerprint_error_t error) {
  fingerprint_msg_t message = {0};
  message.type = FINGERPRINT_ERROR;
  message.data.error = error;
  notify_message(device, &message);
}

static bool operation_cancelled(struct m86_fingerprint_device *device) {
  bool cancelled;
  pthread_mutex_lock(&device->lock);
  cancelled = device->cancel_requested;
  pthread_mutex_unlock(&device->lock);
  return cancelled;
}

static void finish_worker(struct m86_fingerprint_device *device) {
  fp_dev_mode(device->sensor, 0);
  pthread_mutex_lock(&device->lock);
  device->operation = OPERATION_IDLE;
  device->worker_active = false;
  pthread_mutex_unlock(&device->lock);
}

static uint32_t find_free_fid_locked(
    const struct m86_fingerprint_device *device) {
  uint32_t candidate;

  for (candidate = 1; candidate <= MAX_TEMPLATES; ++candidate) {
    size_t index;
    bool used = false;
    for (index = 0; index < device->template_count; ++index) {
      if (device->template_ids[index] == candidate) {
        used = true;
        break;
      }
    }
    if (!used) {
      return candidate;
    }
  }
  return 0;
}

static void *enroll_worker(void *argument) {
  struct m86_fingerprint_device *device = argument;
  struct fp_print_data *enrolled = NULL;
  uint32_t remaining = fp_dev_get_nr_enroll_stages(device->sensor);
  time_t deadline;
  bool completed = false;

  pthread_mutex_lock(&device->lock);
  deadline = time(NULL) + device->enroll_timeout_sec;
  pthread_mutex_unlock(&device->lock);
  fp_dev_mode(device->sensor, 1);

  while (!operation_cancelled(device) && time(NULL) < deadline) {
    int status = fp_enroll_finger(device->sensor, &enrolled);
    fingerprint_msg_t message = {0};

    if (operation_cancelled(device)) {
      break;
    }
    if (status < 0) {
      notify_error(device, FINGERPRINT_ERROR_HW_UNAVAILABLE);
      break;
    }

    switch (status) {
      case FP_ENROLL_RETRY:
      case FP_ENROLL_RETRY_TOO_SHORT:
      case FP_ENROLL_RETRY_CENTER_FINGER:
      case FP_ENROLL_RETRY_REMOVE_FINGER:
        message.type = FINGERPRINT_ACQUIRED;
        message.data.acquired.acquired_info =
            FINGERPRINT_ACQUIRED_INSUFFICIENT;
        notify_message(device, &message);
        break;
      case FP_ENROLL_PASS:
        if (remaining > 1) {
          --remaining;
        }
        pthread_mutex_lock(&device->lock);
        message.type = FINGERPRINT_TEMPLATE_ENROLLING;
        message.data.enroll.finger.gid = device->active_gid;
        message.data.enroll.finger.fid = 0;
        message.data.enroll.samples_remaining = remaining;
        pthread_mutex_unlock(&device->lock);
        notify_message(device, &message);
        break;
      case FP_ENROLL_COMPLETE: {
        uint32_t fid;
        int result;

        pthread_mutex_lock(&device->lock);
        fid = find_free_fid_locked(device);
        pthread_mutex_unlock(&device->lock);
        if (fid == 0 || enrolled == NULL) {
          notify_error(device, FINGERPRINT_ERROR_NO_SPACE);
          goto done;
        }

        result = fp_print_data_save(enrolled, (enum fp_finger)fid,
                                    device->store_path);
        if (result < 0) {
          notify_error(device, FINGERPRINT_ERROR_UNABLE_TO_PROCESS);
          goto done;
        }

        pthread_mutex_lock(&device->lock);
        load_templates_locked(device);
        result = rotate_authenticator_locked(device);
        message.type = FINGERPRINT_TEMPLATE_ENROLLING;
        message.data.enroll.finger.gid = device->active_gid;
        message.data.enroll.finger.fid = fid;
        message.data.enroll.samples_remaining = 0;
        pthread_mutex_unlock(&device->lock);
        if (result < 0) {
          ALOGW("Could not persist fingerprint authenticator metadata: %d",
                result);
        }
        notify_message(device, &message);
        completed = true;
        goto done;
      }
      case FP_ENROLL_FAIL:
      default:
        notify_error(device, FINGERPRINT_ERROR_UNABLE_TO_PROCESS);
        goto done;
    }
  }

  if (!completed && !operation_cancelled(device) && time(NULL) >= deadline) {
    notify_error(device, FINGERPRINT_ERROR_TIMEOUT);
  }

done:
  fp_enroll_reset(device->sensor);
  fp_print_data_free(enrolled);
  finish_worker(device);
  return NULL;
}

static void send_authentication_failure(
    struct m86_fingerprint_device *device) {
  fingerprint_msg_t message = {0};
  pthread_mutex_lock(&device->lock);
  message.type = FINGERPRINT_AUTHENTICATED;
  message.data.authenticated.finger.gid = device->active_gid;
  pthread_mutex_unlock(&device->lock);
  notify_message(device, &message);
}

static void send_authentication_success(
    struct m86_fingerprint_device *device, size_t match_index) {
  fingerprint_msg_t acquired = {0};
  fingerprint_msg_t authenticated = {0};
  struct timespec timestamp;

  acquired.type = FINGERPRINT_ACQUIRED;
  acquired.data.acquired.acquired_info = FINGERPRINT_ACQUIRED_GOOD;

  pthread_mutex_lock(&device->lock);
  authenticated.type = FINGERPRINT_AUTHENTICATED;
  authenticated.data.authenticated.finger.gid = device->active_gid;
  authenticated.data.authenticated.finger.fid =
      device->template_ids[match_index];
  authenticated.data.authenticated.hat.version = HW_AUTH_TOKEN_VERSION;
  authenticated.data.authenticated.hat.challenge = device->operation_id;
  authenticated.data.authenticated.hat.user_id = device->secure_user_id;
  authenticated.data.authenticated.hat.authenticator_id =
      device->authenticator_id;
  authenticated.data.authenticated.hat.authenticator_type =
      htobe32(HW_AUTH_FINGERPRINT);
  pthread_mutex_unlock(&device->lock);

  clock_gettime(CLOCK_MONOTONIC, &timestamp);
  authenticated.data.authenticated.hat.timestamp = htobe64(
      (uint64_t)timestamp.tv_sec * UINT64_C(1000) +
      (uint64_t)timestamp.tv_nsec / UINT64_C(1000000));
  memset(authenticated.data.authenticated.hat.hmac, 0,
         sizeof(authenticated.data.authenticated.hat.hmac));

  notify_message(device, &acquired);
  notify_message(device, &authenticated);
}

static void *authenticate_worker(void *argument) {
  struct m86_fingerprint_device *device = argument;

  fp_dev_mode(device->sensor, 1);
  while (!operation_cancelled(device)) {
    int match_index = -1;
    int status = fp_identify_finger(device->sensor, device->templates,
                                    &match_index);

    if (operation_cancelled(device)) {
      break;
    }
    if (status < 0) {
      notify_error(device, FINGERPRINT_ERROR_HW_UNAVAILABLE);
      break;
    }
    if (status == FP_VERIFY_MATCH) {
      if (match_index < 0 || (size_t)match_index >= device->template_count) {
        notify_error(device, FINGERPRINT_ERROR_UNABLE_TO_PROCESS);
      } else {
        send_authentication_success(device, (size_t)match_index);
      }
      break;
    }
    if (status == FP_VERIFY_NO_MATCH) {
      send_authentication_failure(device);
    } else {
      fingerprint_msg_t message = {0};
      message.type = FINGERPRINT_ACQUIRED;
      message.data.acquired.acquired_info =
          FINGERPRINT_ACQUIRED_INSUFFICIENT;
      notify_message(device, &message);
    }
  }

  finish_worker(device);
  return NULL;
}

static void reap_finished_worker(struct m86_fingerprint_device *device) {
  pthread_t worker;
  bool join = false;

  pthread_mutex_lock(&device->lock);
  if (device->worker_joinable && !device->worker_active) {
    worker = device->worker;
    device->worker_joinable = false;
    join = true;
  }
  pthread_mutex_unlock(&device->lock);
  if (join) {
    pthread_join(worker, NULL);
  }
}

/* The caller holds device->lock and has already reaped any previous worker. */
static int start_worker_locked(struct m86_fingerprint_device *device,
                               enum worker_operation operation,
                               void *(*worker_function)(void *)) {
  int result;

  if (device->worker_active || device->worker_joinable) {
    return -EBUSY;
  }
  device->cancel_requested = false;
  device->operation = operation;
  device->worker_active = true;
  result = pthread_create(&device->worker, NULL, worker_function, device);
  if (result != 0) {
    device->worker_active = false;
    device->operation = OPERATION_IDLE;
    return -result;
  }
  device->worker_joinable = true;
  return 0;
}

static int stop_worker(struct m86_fingerprint_device *device,
                       bool send_cancel) {
  pthread_t worker;
  bool join = false;
  bool cancelled_active_worker = false;

  reap_finished_worker(device);
  pthread_mutex_lock(&device->lock);
  if (device->worker_joinable) {
    if (device->worker_active) {
      device->cancel_requested = true;
      cancelled_active_worker = true;
    }
    worker = device->worker;
    device->worker_joinable = false;
    join = true;
  }
  pthread_mutex_unlock(&device->lock);

  if (join) {
    pthread_join(worker, NULL);
    if (send_cancel && cancelled_active_worker) {
      notify_error(device, FINGERPRINT_ERROR_CANCELED);
    }
  }
  return 0;
}

static int fingerprint_close(hw_device_t *hardware_device) {
  struct m86_fingerprint_device *device =
      (struct m86_fingerprint_device *)hardware_device;

  if (device == NULL) {
    return 0;
  }
  stop_worker(device, false);
  pthread_mutex_lock(&device->lock);
  free_templates_locked(device);
  pthread_mutex_unlock(&device->lock);
  fp_dev_close(device->sensor);
  fp_exit();
  pthread_mutex_destroy(&device->lock);
  free(device);
  return 0;
}

static int fingerprint_set_notify(fingerprint_device_t *fingerprint_device,
                                  fingerprint_notify_t callback) {
  struct m86_fingerprint_device *device =
      (struct m86_fingerprint_device *)fingerprint_device;
  if (device == NULL || callback == NULL) {
    return -EINVAL;
  }
  pthread_mutex_lock(&device->lock);
  device->device.notify = callback;
  pthread_mutex_unlock(&device->lock);
  return 0;
}

static uint64_t fingerprint_pre_enroll(
    fingerprint_device_t *fingerprint_device) {
  struct m86_fingerprint_device *device =
      (struct m86_fingerprint_device *)fingerprint_device;
  uint64_t challenge = random_u64();
  pthread_mutex_lock(&device->lock);
  device->challenge = challenge;
  pthread_mutex_unlock(&device->lock);
  return challenge;
}

static int fingerprint_enroll(fingerprint_device_t *fingerprint_device,
                              const hw_auth_token_t *token, uint32_t gid,
                              uint32_t timeout_sec) {
  struct m86_fingerprint_device *device =
      (struct m86_fingerprint_device *)fingerprint_device;

  if (token == NULL || token->version != HW_AUTH_TOKEN_VERSION) {
    return -EPERM;
  }
  reap_finished_worker(device);
  pthread_mutex_lock(&device->lock);
  if (device->worker_active || device->worker_joinable) {
    pthread_mutex_unlock(&device->lock);
    return -EBUSY;
  }
  if (device->store_path[0] == '\0' || gid != device->active_gid ||
      token->challenge != device->challenge ||
      (be32toh(token->authenticator_type) & HW_AUTH_PASSWORD) == 0) {
    pthread_mutex_unlock(&device->lock);
    return -EPERM;
  }
  if (device->template_count >= MAX_TEMPLATES) {
    pthread_mutex_unlock(&device->lock);
    return -ENOSPC;
  }
  device->secure_user_id = token->user_id;
  device->enroll_timeout_sec = timeout_sec == 0 ? 60 : timeout_sec;
  int result = start_worker_locked(device, OPERATION_ENROLL, enroll_worker);
  pthread_mutex_unlock(&device->lock);
  return result;
}

static int fingerprint_post_enroll(
    fingerprint_device_t *fingerprint_device) {
  struct m86_fingerprint_device *device =
      (struct m86_fingerprint_device *)fingerprint_device;
  pthread_mutex_lock(&device->lock);
  device->challenge = 0;
  pthread_mutex_unlock(&device->lock);
  return 0;
}

static uint64_t fingerprint_get_authenticator_id(
    fingerprint_device_t *fingerprint_device) {
  struct m86_fingerprint_device *device =
      (struct m86_fingerprint_device *)fingerprint_device;
  uint64_t authenticator_id;
  pthread_mutex_lock(&device->lock);
  authenticator_id = device->authenticator_id;
  pthread_mutex_unlock(&device->lock);
  return authenticator_id;
}

static int fingerprint_cancel(fingerprint_device_t *fingerprint_device) {
  return stop_worker((struct m86_fingerprint_device *)fingerprint_device,
                     true);
}

static int fingerprint_enumerate(fingerprint_device_t *fingerprint_device) {
  struct m86_fingerprint_device *device =
      (struct m86_fingerprint_device *)fingerprint_device;
  uint32_t ids[MAX_TEMPLATES] = {0};
  uint32_t gid;
  size_t count;
  size_t index;

  reap_finished_worker(device);
  pthread_mutex_lock(&device->lock);
  if (device->worker_active) {
    pthread_mutex_unlock(&device->lock);
    return -EBUSY;
  }
  count = device->template_count;
  gid = device->active_gid;
  memcpy(ids, device->template_ids, count * sizeof(ids[0]));
  pthread_mutex_unlock(&device->lock);

  if (count == 0) {
    fingerprint_msg_t message = {0};
    message.type = FINGERPRINT_TEMPLATE_ENUMERATING;
    notify_message(device, &message);
    return 0;
  }
  for (index = 0; index < count; ++index) {
    fingerprint_msg_t message = {0};
    message.type = FINGERPRINT_TEMPLATE_ENUMERATING;
    message.data.enumerated.finger.gid = gid;
    message.data.enumerated.finger.fid = ids[index];
    message.data.enumerated.remaining_templates =
        (uint32_t)(count - index - 1);
    notify_message(device, &message);
  }
  return 0;
}

static int fingerprint_remove(fingerprint_device_t *fingerprint_device,
                              uint32_t gid, uint32_t fid) {
  struct m86_fingerprint_device *device =
      (struct m86_fingerprint_device *)fingerprint_device;
  uint32_t removed[MAX_TEMPLATES] = {0};
  size_t removed_count = 0;
  size_t index;
  int metadata_result;
  int state_error = 0;

  reap_finished_worker(device);
  pthread_mutex_lock(&device->lock);
  if (device->worker_active || gid != device->active_gid) {
    state_error = device->worker_active ? -EBUSY : -EINVAL;
    pthread_mutex_unlock(&device->lock);
    return state_error;
  }
  for (index = 0; index < device->template_count; ++index) {
    uint32_t stored_fid = device->template_ids[index];
    if ((fid == 0 || fid == stored_fid) &&
        fp_print_data_delete(device->sensor,
                             (enum fp_finger)stored_fid) == 0) {
      removed[removed_count++] = stored_fid;
    }
  }
  load_templates_locked(device);
  metadata_result = rotate_authenticator_locked(device);
  pthread_mutex_unlock(&device->lock);
  if (metadata_result < 0) {
    ALOGW("Could not update fingerprint metadata after removal: %d",
          metadata_result);
  }

  if (removed_count == 0) {
    fingerprint_msg_t message = {0};
    message.type = FINGERPRINT_TEMPLATE_REMOVED;
    message.data.removed.finger.gid = gid;
    notify_message(device, &message);
    return 0;
  }
  for (index = 0; index < removed_count; ++index) {
    fingerprint_msg_t message = {0};
    message.type = FINGERPRINT_TEMPLATE_REMOVED;
    message.data.removed.finger.gid = gid;
    message.data.removed.finger.fid = removed[index];
    message.data.removed.remaining_templates =
        (uint32_t)(removed_count - index - 1);
    notify_message(device, &message);
  }
  return 0;
}

static int fingerprint_set_active_group(
    fingerprint_device_t *fingerprint_device, uint32_t gid,
    const char *store_path) {
  struct m86_fingerprint_device *device =
      (struct m86_fingerprint_device *)fingerprint_device;
  int length;
  int result;

  if (store_path == NULL || store_path[0] != '/') {
    return -EINVAL;
  }
  reap_finished_worker(device);
  pthread_mutex_lock(&device->lock);
  if (device->worker_active) {
    pthread_mutex_unlock(&device->lock);
    return -EBUSY;
  }
  length = snprintf(device->store_path, sizeof(device->store_path), "%s",
                    store_path);
  if (length < 0 || (size_t)length >= sizeof(device->store_path)) {
    device->store_path[0] = '\0';
    pthread_mutex_unlock(&device->lock);
    return -ENAMETOOLONG;
  }
  device->active_gid = gid;
  result = load_templates_locked(device);
  if (result == 0) {
    result = load_metadata_locked(device);
  }
  if (result == 0 && device->template_count == 0) {
    device->authenticator_id = 0;
  } else if (result == 0 && device->authenticator_id == 0) {
    result = rotate_authenticator_locked(device);
  }
  pthread_mutex_unlock(&device->lock);
  return result;
}

static int fingerprint_authenticate(fingerprint_device_t *fingerprint_device,
                                    uint64_t operation_id, uint32_t gid) {
  struct m86_fingerprint_device *device =
      (struct m86_fingerprint_device *)fingerprint_device;

  reap_finished_worker(device);
  pthread_mutex_lock(&device->lock);
  if (device->worker_active || device->worker_joinable) {
    pthread_mutex_unlock(&device->lock);
    return -EBUSY;
  }
  if (gid != device->active_gid || device->template_count == 0) {
    pthread_mutex_unlock(&device->lock);
    return -ENOENT;
  }
  device->operation_id = operation_id;
  int result = start_worker_locked(device, OPERATION_AUTHENTICATE,
                                   authenticate_worker);
  pthread_mutex_unlock(&device->lock);
  return result;
}

static int fingerprint_open(const hw_module_t *module, const char *id,
                            hw_device_t **hardware_device) {
  struct m86_fingerprint_device *device;
  struct fp_dscv_dev **discovered;

  (void)id;
  if (hardware_device == NULL) {
    return -EINVAL;
  }
  if (fp_init() < 0) {
    return -ENODEV;
  }
  discovered = fp_discover_devs();
  if (discovered == NULL || discovered[0] == NULL) {
    fp_dscv_devs_free(discovered);
    fp_exit();
    return -ENODEV;
  }

  device = calloc(1, sizeof(*device));
  if (device == NULL) {
    fp_dscv_devs_free(discovered);
    fp_exit();
    return -ENOMEM;
  }
  device->sensor = fp_dev_open(discovered[0]);
  fp_dscv_devs_free(discovered);
  if (device->sensor == NULL) {
    free(device);
    fp_exit();
    return -ENODEV;
  }

  int result = pthread_mutex_init(&device->lock, NULL);
  if (result != 0) {
    fp_dev_close(device->sensor);
    free(device);
    fp_exit();
    return -result;
  }
  device->device.common.tag = HARDWARE_DEVICE_TAG;
  device->device.common.version = FINGERPRINT_MODULE_API_VERSION_2_1;
  device->device.common.module = (hw_module_t *)module;
  device->device.common.close = fingerprint_close;
  device->device.set_notify = fingerprint_set_notify;
  device->device.pre_enroll = fingerprint_pre_enroll;
  device->device.enroll = fingerprint_enroll;
  device->device.post_enroll = fingerprint_post_enroll;
  device->device.get_authenticator_id = fingerprint_get_authenticator_id;
  device->device.cancel = fingerprint_cancel;
  device->device.enumerate = fingerprint_enumerate;
  device->device.remove = fingerprint_remove;
  device->device.set_active_group = fingerprint_set_active_group;
  device->device.authenticate = fingerprint_authenticate;
  fp_dev_mode(device->sensor, 0);
  *hardware_device = &device->device.common;
  return 0;
}

static struct hw_module_methods_t fingerprint_module_methods = {
    .open = fingerprint_open,
};

fingerprint_module_t HAL_MODULE_INFO_SYM = {
    .common =
        {
            .tag = HARDWARE_MODULE_TAG,
            .module_api_version = FINGERPRINT_MODULE_API_VERSION_2_1,
            .hal_api_version = HARDWARE_HAL_API_VERSION,
            .id = FINGERPRINT_HARDWARE_MODULE_ID,
            .name = "Meizu PRO 5 FPC1020 Fingerprint HAL",
            .author = "The LineageOS Project",
            .methods = &fingerprint_module_methods,
        },
};
