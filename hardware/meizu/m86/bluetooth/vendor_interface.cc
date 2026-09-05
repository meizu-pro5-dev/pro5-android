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

#include "vendor_interface.h"

#define LOG_TAG "android.hardware.bluetooth@1.0-impl.m86"
#include <cutils/properties.h>
#include <utils/Log.h>

#include <dlfcn.h>
#include <fcntl.h>

#include "bluetooth_address.h"
#include "h4_protocol.h"
#include "mct_protocol.h"

static const char* VENDOR_LIBRARY_NAME = "libbt-vendor.so";
static const char* VENDOR_LIBRARY_SYMBOL_NAME =
    "BLUETOOTH_VENDOR_LIB_INTERFACE";

static const int INVALID_FD = -1;

namespace {

using android::hardware::hidl_vec;
using android::hardware::bluetooth::V1_0::implementation::VendorInterface;

struct {
  tINT_CMD_CBACK cb;
  uint16_t opcode;
} internal_command;

// True when LPM is not enabled yet or wake is not asserted.
bool lpm_wake_deasserted;
uint32_t lpm_timeout_ms;
bool recent_activity_flag;
enum class StartupPhase { Firmware, Sco, LowPower, Complete };
StartupPhase startup_phase = StartupPhase::Complete;
int startup_result = -1;
unsigned vendor_callback_depth;
bool h4_transport;
std::recursive_mutex startup_mutex;

void AdvanceStartupIfIdle() {
  if (startup_phase != StartupPhase::Complete && startup_result != -1 &&
      vendor_callback_depth == 0 && internal_command.cb == nullptr) {
    VendorInterface::get()->OnFirmwareConfigured(startup_result);
  }
}

void StartupCallback(StartupPhase phase, bt_vendor_op_result_t result) {
  std::lock_guard<std::recursive_mutex> lock(startup_mutex);
  if (startup_phase != phase) return;
  // A later success must not hide an allocation, transmit, or controller error.
  if (startup_result != BT_VND_OP_RESULT_FAIL) startup_result = result;
  AdvanceStartupIfIdle();
}

VendorInterface* g_vendor_interface = nullptr;
std::mutex wakeup_mutex_;

HC_BT_HDR* WrapPacketAndCopy(uint16_t event, const hidl_vec<uint8_t>& data) {
  size_t packet_size = data.size() + sizeof(HC_BT_HDR);
  HC_BT_HDR* packet = reinterpret_cast<HC_BT_HDR*>(new uint8_t[packet_size]);
  packet->offset = 0;
  packet->len = data.size();
  packet->layer_specific = 0;
  packet->event = event;
  // TODO(eisenbach): Avoid copy here; if BT_HDR->data can be ensured to
  // be the only way the data is accessed, a pointer could be passed here...
  memcpy(packet->data, data.data(), data.size());
  return packet;
}

bool internal_command_event_match(const hidl_vec<uint8_t>& packet) {
  uint8_t event_code = packet[0];
  if (event_code != HCI_COMMAND_COMPLETE_EVENT) {
    ALOGE("%s: Unhandled event type %02X", __func__, event_code);
    return false;
  }

  size_t opcode_offset = HCI_EVENT_PREAMBLE_SIZE + 1;  // Skip num packets.

  uint16_t opcode = packet[opcode_offset] | (packet[opcode_offset + 1] << 8);

  ALOGV("%s internal_command.opcode = %04X opcode = %04x", __func__,
        internal_command.opcode, opcode);
  return opcode == internal_command.opcode;
}

uint8_t transmit_cb(uint16_t opcode, void* buffer, tINT_CMD_CBACK callback) {
  std::lock_guard<std::recursive_mutex> lock(startup_mutex);
  ALOGV("%s opcode: 0x%04x, ptr: %p, cb: %p", __func__, opcode, buffer,
        callback);
  if (internal_command.cb != nullptr) {
    ALOGE("%s: command %04x still pending; rejecting %04x", __func__,
          internal_command.opcode, opcode);
    if (startup_phase != StartupPhase::Complete)
      startup_result = BT_VND_OP_RESULT_FAIL;
    return false;  // The vendor retains ownership of a rejected buffer.
  }
  internal_command.cb = callback;
  internal_command.opcode = opcode;
  uint8_t type = HCI_PACKET_TYPE_COMMAND;
  HC_BT_HDR* bt_hdr = reinterpret_cast<HC_BT_HDR*>(buffer);
  const size_t expected = bt_hdr->len + (h4_transport ? 1 : 0);
  const size_t sent = VendorInterface::get()->Send(type, bt_hdr->data, bt_hdr->len);
  if (sent != expected) {
    ALOGE("%s: command %04x write failed (%zu/%zu)", __func__, opcode,
          sent, expected);
    internal_command = {};
    if (startup_phase != StartupPhase::Complete)
      startup_result = BT_VND_OP_RESULT_FAIL;
    return false;  // Rejected buffers are freed by the vendor, not this shim.
  }
  delete[] reinterpret_cast<uint8_t*>(buffer);
  return true;
}

void firmware_config_cb(bt_vendor_op_result_t result) {
  ALOGV("%s result: %d", __func__, result);
  StartupCallback(StartupPhase::Firmware, result);
}

void sco_config_cb(bt_vendor_op_result_t result) {
  ALOGD("%s result: %d", __func__, result);
  StartupCallback(StartupPhase::Sco, result);
}

void low_power_mode_cb(bt_vendor_op_result_t result) {
  ALOGD("%s result: %d", __func__, result);
  StartupCallback(StartupPhase::LowPower, result);
}

void sco_audiostate_cb(bt_vendor_op_result_t result) {
  ALOGD("%s result: %d", __func__, result);
  // Flyme reports actual I2SPCM completion (and allocation/transmit failure)
  // here; scocfg_cb only acknowledges that configuration was requested.
  StartupCallback(StartupPhase::Sco, result);
}

void* buffer_alloc_cb(int size) {
  void* p = new uint8_t[size];
  ALOGV("%s pts: %p, size: %d", __func__, p, size);
  return p;
}

void buffer_free_cb(void* buffer) {
  ALOGV("%s ptr: %p", __func__, buffer);
  delete[] reinterpret_cast<uint8_t*>(buffer);
}

void epilog_cb(bt_vendor_op_result_t result) {
  ALOGD("%s result: %d", __func__, result);
}

void a2dp_offload_cb(bt_vendor_op_result_t result, bt_vendor_opcode_t op,
                     uint8_t av_handle) {
  ALOGD("%s result: %d, op: %d, handle: %d", __func__, result, op, av_handle);
}

const bt_vendor_callbacks_t lib_callbacks = {
    sizeof(lib_callbacks), firmware_config_cb, sco_config_cb,
    low_power_mode_cb,     sco_audiostate_cb,  buffer_alloc_cb,
    buffer_free_cb,        transmit_cb,        epilog_cb,
    a2dp_offload_cb};

}  // namespace

namespace android {
namespace hardware {
namespace bluetooth {
namespace V1_0 {
namespace implementation {

class FirmwareStartupTimer {
 public:
  FirmwareStartupTimer() : start_time_(std::chrono::steady_clock::now()) {}

  ~FirmwareStartupTimer() {
    std::chrono::duration<double> duration =
        std::chrono::steady_clock::now() - start_time_;
    double s = duration.count();
    if (s == 0) return;
    ALOGI("Firmware configured in %.3fs", s);
  }

 private:
  std::chrono::steady_clock::time_point start_time_;
};

bool VendorInterface::Initialize(
    InitializeCompleteCallback initialize_complete_cb,
    PacketReadCallback event_cb, PacketReadCallback acl_cb,
    PacketReadCallback sco_cb, PacketReadCallback iso_cb) {
  if (g_vendor_interface) {
    ALOGE("%s: No previous Shutdown()?", __func__);
    return false;
  }
  g_vendor_interface = new VendorInterface();
  return g_vendor_interface->Open(initialize_complete_cb, event_cb, acl_cb,
                                  sco_cb, iso_cb);
}

void VendorInterface::Shutdown() {
  LOG_ALWAYS_FATAL_IF(!g_vendor_interface, "%s: No Vendor interface!",
                      __func__);
  g_vendor_interface->Close();
  delete g_vendor_interface;
  g_vendor_interface = nullptr;
}

VendorInterface* VendorInterface::get() { return g_vendor_interface; }

bool VendorInterface::Open(InitializeCompleteCallback initialize_complete_cb,
                           PacketReadCallback event_cb,
                           PacketReadCallback acl_cb,
                           PacketReadCallback sco_cb,
                           PacketReadCallback iso_cb) {
  std::lock_guard<std::recursive_mutex> lock(startup_mutex);
  initialize_complete_cb_ = initialize_complete_cb;

  // Initialize vendor interface

  lib_handle_ = dlopen(VENDOR_LIBRARY_NAME, RTLD_NOW);
  if (!lib_handle_) {
    ALOGE("%s unable to open %s (%s)", __func__, VENDOR_LIBRARY_NAME,
          dlerror());
    return false;
  }

  lib_interface_ = reinterpret_cast<bt_vendor_interface_t*>(
      dlsym(lib_handle_, VENDOR_LIBRARY_SYMBOL_NAME));
  if (!lib_interface_) {
    ALOGE("%s unable to find symbol %s in %s (%s)", __func__,
          VENDOR_LIBRARY_SYMBOL_NAME, VENDOR_LIBRARY_NAME, dlerror());
    return false;
  }

  // Get the local BD address

  uint8_t local_bda[BluetoothAddress::kBytes];
  if (!BluetoothAddress::get_local_address(local_bda)) {
    LOG_ALWAYS_FATAL("%s: No Bluetooth Address!", __func__);
  }
  int status = lib_interface_->init(&lib_callbacks, (unsigned char*)local_bda);
  if (status) {
    ALOGE("%s unable to initialize vendor library: %d", __func__, status);
    return false;
  }

  ALOGD("%s vendor library loaded", __func__);

  // Power on the controller

  int power_state = BT_VND_PWR_ON;
  lib_interface_->op(BT_VND_OP_POWER_CTRL, &power_state);

  // Get the UART socket(s)

  int fd_list[CH_MAX] = {0};
  int fd_count = lib_interface_->op(BT_VND_OP_USERIAL_OPEN, &fd_list);

  if (fd_count < 1 || fd_count > CH_MAX - 1) {
    ALOGE("%s: fd_count %d is invalid!", __func__, fd_count);
    return false;
  }

  for (int i = 0; i < fd_count; i++) {
    if (fd_list[i] == INVALID_FD) {
      ALOGE("%s: fd %d is invalid!", __func__, fd_list[i]);
      return false;
    }
  }

  event_cb_ = event_cb;
  PacketReadCallback intercept_events = [this](const hidl_vec<uint8_t>& event) {
    HandleIncomingEvent(event);
  };

  h4_transport = fd_count == 1;
  if (h4_transport) {
    hci::H4Protocol* h4_hci = new hci::H4Protocol(
        fd_list[0], intercept_events, acl_cb, sco_cb, iso_cb);
    fd_watcher_.WatchFdForNonBlockingReads(
        fd_list[0], [h4_hci](int fd) { h4_hci->OnDataReady(fd); });
    hci_ = h4_hci;
  } else {
    hci::MctProtocol* mct_hci =
        new hci::MctProtocol(fd_list, intercept_events, acl_cb);
    fd_watcher_.WatchFdForNonBlockingReads(
        fd_list[CH_EVT], [mct_hci](int fd) { mct_hci->OnEventDataReady(fd); });
    fd_watcher_.WatchFdForNonBlockingReads(
        fd_list[CH_ACL_IN], [mct_hci](int fd) { mct_hci->OnAclDataReady(fd); });
    hci_ = mct_hci;
  }

  // Initially, the power management is off.
  lpm_wake_deasserted = true;
  internal_command = {};
  startup_phase = StartupPhase::Firmware;
  startup_result = -1;
  vendor_callback_depth = 0;

  // Start configuring the firmware
  firmware_startup_timer_ = new FirmwareStartupTimer();
  ++vendor_callback_depth;
  const int fw_status = lib_interface_->op(BT_VND_OP_FW_CFG, nullptr);
  --vendor_callback_depth;
  if (fw_status != 0) startup_result = BT_VND_OP_RESULT_FAIL;
  AdvanceStartupIfIdle();

  return true;
}

void VendorInterface::Close() {
  {
    std::lock_guard<std::recursive_mutex> lock(startup_mutex);
    startup_phase = StartupPhase::Complete;
  }
  // These callbacks may send HCI events (vendor-dependent), so make sure to
  // StopWatching the file descriptor after this.
  if (lib_interface_ != nullptr) {
    bt_vendor_lpm_mode_t mode = BT_VND_LPM_DISABLE;
    lib_interface_->op(BT_VND_OP_LPM_SET_MODE, &mode);
  }

  fd_watcher_.StopWatchingFileDescriptors();
  internal_command = {};

  if (hci_ != nullptr) {
    delete hci_;
    hci_ = nullptr;
  }

  if (lib_interface_ != nullptr) {
    lib_interface_->op(BT_VND_OP_USERIAL_CLOSE, nullptr);

    int power_state = BT_VND_PWR_OFF;
    lib_interface_->op(BT_VND_OP_POWER_CTRL, &power_state);

    lib_interface_->cleanup();
    lib_interface_ = nullptr;
  }

  if (lib_handle_ != nullptr) {
    dlclose(lib_handle_);
    lib_handle_ = nullptr;
  }

  if (firmware_startup_timer_ != nullptr) {
    delete firmware_startup_timer_;
    firmware_startup_timer_ = nullptr;
  }
}

size_t VendorInterface::Send(uint8_t type, const uint8_t* data, size_t length) {
  std::unique_lock<std::mutex> lock(wakeup_mutex_);
  recent_activity_flag = true;

  if (lpm_wake_deasserted == true) {
    // Restart the timer.
    fd_watcher_.ConfigureTimeout(std::chrono::milliseconds(lpm_timeout_ms),
                                 [this]() { OnTimeout(); });
    // Assert wake.
    lpm_wake_deasserted = false;
    bt_vendor_lpm_wake_state_t wakeState = BT_VND_LPM_WAKE_ASSERT;
    lib_interface_->op(BT_VND_OP_LPM_WAKE_SET_STATE, &wakeState);
    ALOGV("%s: Sent wake before (%02x)", __func__, data[0] | (data[1] << 8));
  }

  return hci_->Send(type, data, length);
}

void VendorInterface::OnFirmwareConfigured(uint8_t result) {
  ALOGD("%s result: %d", __func__, result);
  if (startup_phase == StartupPhase::Complete) return;

  // Wait for both the phase result and the entire internal command callback
  // to return. In particular, Flyme's synchronous scocfg success must not
  // publish initialization or overwrite the outstanding 0xfc6d callback.
  if (result == BT_VND_OP_RESULT_SUCCESS &&
      startup_phase == StartupPhase::Firmware) {
    startup_phase = StartupPhase::Sco;
    startup_result = -1;
    ++vendor_callback_depth;
    const int status = lib_interface_->op(BT_VND_OP_SCO_CFG, nullptr);
    --vendor_callback_depth;
    if (status != 0) startup_result = BT_VND_OP_RESULT_FAIL;
    AdvanceStartupIfIdle();
    return;
  }
  if (result == BT_VND_OP_RESULT_SUCCESS && startup_phase == StartupPhase::Sco) {
    startup_phase = StartupPhase::LowPower;
    startup_result = -1;
    lib_interface_->op(BT_VND_OP_GET_LPM_IDLE_TIMEOUT, &lpm_timeout_ms);
    ALOGI("%s: lpm_timeout_ms %d", __func__, lpm_timeout_ms);
    bt_vendor_lpm_mode_t mode = BT_VND_LPM_ENABLE;
    ++vendor_callback_depth;
    // Flyme's LPM op returns hw_lpm_enable's boolean transmit result.
    const int status = lib_interface_->op(BT_VND_OP_LPM_SET_MODE, &mode);
    --vendor_callback_depth;
    if (status <= 0) startup_result = BT_VND_OP_RESULT_FAIL;
    AdvanceStartupIfIdle();
    return;
  }
  startup_phase = StartupPhase::Complete;

  if (firmware_startup_timer_ != nullptr) {
    delete firmware_startup_timer_;
    firmware_startup_timer_ = nullptr;
  }

  const bool initialize_success = result == BT_VND_OP_RESULT_SUCCESS;
  if (initialize_success) {
    fd_watcher_.ConfigureTimeout(std::chrono::milliseconds(lpm_timeout_ms),
                                 [this]() { OnTimeout(); });
  }
  auto initialize_complete = std::move(initialize_complete_cb_);
  initialize_complete_cb_ = nullptr;
  if (initialize_complete) initialize_complete(initialize_success);
}

void VendorInterface::OnTimeout() {
  ALOGV("%s", __func__);
  std::unique_lock<std::mutex> lock(wakeup_mutex_);
  if (recent_activity_flag == false) {
    lpm_wake_deasserted = true;
    bt_vendor_lpm_wake_state_t wakeState = BT_VND_LPM_WAKE_DEASSERT;
    lib_interface_->op(BT_VND_OP_LPM_WAKE_SET_STATE, &wakeState);
    fd_watcher_.ConfigureTimeout(std::chrono::seconds(0), []() {
      ALOGE("Zero timeout! Should never happen.");
    });
  }
  recent_activity_flag = false;
}

void VendorInterface::HandleIncomingEvent(const hidl_vec<uint8_t>& hci_packet) {
  std::lock_guard<std::recursive_mutex> lock(startup_mutex);
  if (internal_command.cb != nullptr &&
      internal_command_event_match(hci_packet)) {
    HC_BT_HDR* bt_hdr = WrapPacketAndCopy(HCI_PACKET_TYPE_EVENT, hci_packet);

    // The callbacks can send new commands, so don't zero after calling.
    tINT_CMD_CBACK saved_cb = internal_command.cb;
    internal_command.cb = nullptr;
    ++vendor_callback_depth;
    saved_cb(bt_hdr);
    --vendor_callback_depth;
    AdvanceStartupIfIdle();
  } else {
    event_cb_(hci_packet);
  }
}

}  // namespace implementation
}  // namespace V1_0
}  // namespace bluetooth
}  // namespace hardware
}  // namespace android
