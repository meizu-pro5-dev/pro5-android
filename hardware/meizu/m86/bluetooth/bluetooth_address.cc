//
// Copyright 2016 The Android Open Source Project
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#include "bluetooth_address.h"

#include <cutils/properties.h>
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <unistd.h>
#include <utils/Log.h>

namespace android {
namespace hardware {
namespace bluetooth {
namespace V1_0 {
namespace implementation {

namespace {

bool read_m86_published_serial(char* serial) {
  const char path[] = "/sys/class/android_usb/android0/iSerial";
  int fd = open(path, O_RDONLY | O_CLOEXEC);
  if (fd < 0) {
    ALOGE("%s: unable to open %s: %s", __func__, path, strerror(errno));
    return false;
  }

  ssize_t result;
  do {
    result = read(fd, serial, PROPERTY_VALUE_MAX - 1);
  } while (result < 0 && errno == EINTR);
  close(fd);
  if (result <= 0) {
    ALOGE("%s: unable to read %s: %s", __func__, path,
          result < 0 ? strerror(errno) : "empty value");
    return false;
  }

  size_t length = static_cast<size_t>(result);
  while (length > 0 &&
         (serial[length - 1] == '\n' || serial[length - 1] == '\r' ||
          serial[length - 1] == ' ' || serial[length - 1] == '\t')) {
    --length;
  }
  serial[length] = '\0';
  if (length == 0) {
    ALOGE("%s: %s contains no serial", __func__, path);
    return false;
  }
  return true;
}

bool derive_m86_address_from_serial(uint8_t* local_addr) {
  char hardware[PROPERTY_VALUE_MAX] = {0};
  if (property_get("ro.hardware", hardware, nullptr) <= 0 ||
      strcmp(hardware, "m86") != 0) {
    return false;
  }

  // vendor.m86.identity.ready starts this service only after the identity
  // helper has validated and published the private-slot serial. Consume that
  // stable handoff directly and avoid probing platform serialno properties.
  char serial[PROPERTY_VALUE_MAX] = {0};
  if (!read_m86_published_serial(serial)) {
    ALOGE("%s: m86 identity is ready but has no published serial", __func__);
    return false;
  }

  // FNV-1a supplies a deterministic 40-bit device suffix. 0x02 marks the
  // result as a locally administered unicast address.
  uint64_t hash = 14695981039346656037ULL;
  for (const unsigned char* value =
           reinterpret_cast<const unsigned char*>(serial);
       *value != '\0'; ++value) {
    hash ^= *value;
    hash *= 1099511628211ULL;
  }
  local_addr[0] = 0x02;
  for (size_t index = 1; index < BluetoothAddress::kBytes; ++index) {
    local_addr[index] = static_cast<uint8_t>(hash >> ((index - 1) * 8));
  }

  char address[BluetoothAddress::kStringLength + 1] = {0};
  BluetoothAddress::bytes_to_string(local_addr, address);
  ALOGW("%s: derived stable m86 fallback BDA %s", __func__, address);
  return true;
}

}  // namespace

void BluetoothAddress::bytes_to_string(const uint8_t* addr, char* addr_str) {
  sprintf(addr_str, "%02x:%02x:%02x:%02x:%02x:%02x", addr[0], addr[1], addr[2],
          addr[3], addr[4], addr[5]);
}

bool BluetoothAddress::string_to_bytes(const char* addr_str, uint8_t* addr) {
  if (addr_str == NULL) return false;
  if (strnlen(addr_str, kStringLength) != kStringLength) return false;
  unsigned char trailing_char = '\0';

  return (sscanf(addr_str, "%02hhx:%02hhx:%02hhx:%02hhx:%02hhx:%02hhx%1c",
                 &addr[0], &addr[1], &addr[2], &addr[3], &addr[4], &addr[5],
                 &trailing_char) == kBytes);
}

bool BluetoothAddress::get_local_address(uint8_t* local_addr) {
  char property[PROPERTY_VALUE_MAX] = {0};

  // Get local bdaddr storage path from a system property.
  if (property_get(PROPERTY_BT_BDADDR_PATH, property, NULL)) {
    ALOGD("%s: Trying %s", __func__, property);

    int addr_fd = open(property, O_RDONLY);
    if (addr_fd != -1) {
      char address[kStringLength + 1] = {0};
      int bytes_read = read(addr_fd, address, kStringLength);
      if (bytes_read == -1) {
        ALOGE("%s: Error reading address from %s: %s", __func__, property,
              strerror(errno));
      }
      close(addr_fd);

      // Null terminate the string.
      address[kStringLength] = '\0';

      // If the address is not all zeros, then use it.
      const uint8_t zero_bdaddr[kBytes] = {0, 0, 0, 0, 0, 0};
      if ((string_to_bytes(address, local_addr)) &&
          (memcmp(local_addr, zero_bdaddr, kBytes) != 0)) {
        ALOGD("%s: Got Factory BDA %s", __func__, address);
        return true;
      } else {
        ALOGE("%s: Got Invalid BDA '%s' from %s", __func__, address, property);
      }
    }
  }

  // No BDADDR found in the file. Look for BDA in a factory property.
  if (property_get(FACTORY_BDADDR_PROPERTY, property, NULL) &&
      string_to_bytes(property, local_addr)) {
    return true;
  }

  // No factory BDADDR found. Look for a previously stored BDA.
  if (property_get(PERSIST_BDADDR_PROPERTY, property, NULL) &&
      string_to_bytes(property, local_addr)) {
    return true;
  }

  if (derive_m86_address_from_serial(local_addr)) return true;

  return false;
}

}  // namespace implementation
}  // namespace V1_0
}  // namespace bluetooth
}  // namespace hardware
}  // namespace android
