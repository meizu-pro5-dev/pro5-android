# Copyright (C) 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

"""Package and install the PRO 5's separately built raw device tree."""

import struct

import common


DTB_TARGET_FILES_ENTRY = "RADIO/dtb.img"
DTB_OTA_ENTRY = "dtb.img"
FDT_MAGIC = 0xD00DFEED
FDT_HEADER_SIZE = 40


def _validated_dtb(target_zip):
  try:
    data = target_zip.read(DTB_TARGET_FILES_ENTRY)
  except KeyError:
    raise ValueError(
        "missing generated PRO 5 DTB: {}".format(DTB_TARGET_FILES_ENTRY))

  if len(data) < FDT_HEADER_SIZE:
    raise ValueError("generated PRO 5 DTB is smaller than its FDT header")

  magic, total_size = struct.unpack(">II", data[:8])
  if magic != FDT_MAGIC:
    raise ValueError("generated PRO 5 DTB has invalid FDT magic")
  if total_size != len(data):
    raise ValueError(
        "generated PRO 5 DTB has trailing or truncated data: {} != {}".format(
            total_size, len(data)))
  if b"Meizu, M86" not in data:
    raise ValueError("generated PRO 5 DTB does not identify Meizu, M86")
  return data


def _install_dtb(info, target_zip):
  data = _validated_dtb(target_zip)
  common.ZipWriteStr(info.output_zip, DTB_OTA_ENTRY, data)
  info.script.Print("Installing the matching PRO 5 device tree...")
  info.script.WriteRawImage("/dtb", DTB_OTA_ENTRY)


def FullOTA_InstallEnd(info):
  _install_dtb(info, info.input_zip)


def IncrementalOTA_InstallEnd(info):
  _install_dtb(info, info.target_zip)
