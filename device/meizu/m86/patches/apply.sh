#!/bin/bash
cd ../../../..
cd frameworks/av
git apply -v ../../device/meizu/m86/patches/frameworks/av/0001-Add-samsung-WFD.patch
git apply -v ../../device/meizu/m86/patches/frameworks/av/0001-codecs-load-fix.patch
git apply -v ../../device/meizu/m86/patches/frameworks/av/0001-disable-some-logging.patch
git apply -v ../../device/meizu/m86/patches/frameworks/av/0001-make-native-Audioflinger-work.patch
git apply -v ../../device/meizu/m86/patches/frameworks/av/0001-prevent-camera-crash-on-init.patch
git apply -v ../../device/meizu/m86/patches/frameworks/av/0001-video-zooming-issue-fix.patch
git apply -v ../../device/meizu/m86/patches/frameworks/av/videoRecFix/new41/0001-PATCH-1-4-Revert-stagefright-untangle-metadata-mode.patch
git apply -v ../../device/meizu/m86/patches/frameworks/av/videoRecFix/new41/0001-PATCH-2-4-Revert-Add-cameraserver-process.patch
git apply -v ../../device/meizu/m86/patches/frameworks/av/videoRecFix/new41/0003-Mark-CameraService-as-media.patch
git apply -v ../../device/meizu/m86/patches/frameworks/av/videoRecFix/new41/0004-ACodec-Accept-kMetadataBufferTypeCameraSource-as-buf.patch
cd ../..
cd frameworks/base
git apply -v ../../device/meizu/m86/patches/frameworks/base/000-another-null-check.patch
git apply -v ../../device/meizu/m86/patches/frameworks/base/000-checking-that-map-is-not-null-to-prevent-apps-crashi.patch
git apply -v ../../device/meizu/m86/patches/frameworks/base/0001-adding-reject-alarm-feature-to-alarm-blocker.patch
git apply -v ../../device/meizu/m86/patches/frameworks/base/0001-Hifi-Settings-1-3.patch
git apply -v ../../device/meizu/m86/patches/frameworks/base/0001-signature-spoof-1-2.patch
git apply -v ../../device/meizu/m86/patches/frameworks/base/0001-Suspend-Actions-WiFi-Toggle-1-2.patch
git apply -v ../../device/meizu/m86/patches/frameworks/base/0001-Swipe-for-Recents-1-2.patch
git apply -v ../../device/meizu/m86/patches/frameworks/base/0001-WakelockBlocker-fix.patch
git apply -v ../../device/meizu/m86/patches/frameworks/base/543852aff3a7c228cc70db5603b138a33d42cb9e.patch
cd ../..
cd frameworks/opt/telephony
git apply -v ../../../device/meizu/m86/patches/frameworks/opt/telephony/0001-disable-datastall-detection.patch
git apply -v ../../../device/meizu/m86/patches/frameworks/opt/telephony/0001-network-selection-fix.patch
git apply -v ../../../device/meizu/m86/patches/frameworks/opt/telephony/0001-pkcs-payload-null-fix.patch
git apply -v ../../../device/meizu/m86/patches/frameworks/opt/telephony/0001-ProxyController-trying-to-avoid-wakelock.patch
cd ../../..
cd hardware/libhardware
git apply -v ../../device/meizu/m86/patches/hardware/libhardware/0001-comment-additional-fields-due-to-gpsd-struct-length-.patch
git apply -v ../../device/meizu/m86/patches/hardware/libhardware/0001-For-stock-audio-hals-to-work.patch
git apply -v ../../device/meizu/m86/patches/hardware/libhardware/0001-immvibe-daemon-patch.patch
cd ../..
cd packages/apps/CMParts
git apply -v ../../../device/meizu/m86/patches/packages/apps/CMParts/0001-HIFI-Settings-3-3.patch
cd ../../..
cd packages/apps/Dialer
git apply -v ../../../device/meizu/m86/patches/packages/apps/Dialer/0001-remove-that-unthemmable-white-bar-in-callog.patch
git apply -v ../../../device/meizu/m86/patches/packages/apps/Dialer/0001-Themes-Expose-hardcoded-layout-and-style-colors.patch
cd ../../..
cd packages/apps/Settings
git apply -v ../../../device/meizu/m86/patches/packages/apps/Settings/0001-AlarmsBlocker-2-2-faust93-based-on-WlBlocker-by-maxw.patch
git apply -v ../../../device/meizu/m86/patches/packages/apps/Settings/0001-HiFi-Settings.patch
git apply -v ../../../device/meizu/m86/patches/packages/apps/Settings/0001-Meizu-Gestures.patch
git apply -v ../../../device/meizu/m86/patches/packages/apps/Settings/0001-ScreenState-adding-wifi-toggle.patch
git apply -v ../../../device/meizu/m86/patches/packages/apps/Settings/0001-signature-spoof-2-2.patch
git apply -v ../../../device/meizu/m86/patches/packages/apps/Settings/0001-spoof-signature.patch
git apply -v ../../../device/meizu/m86/patches/packages/apps/Settings/0001-Suspend-Actions-2-3.patch
git apply -v ../../../device/meizu/m86/patches/packages/apps/Settings/0001-Swipe-for-Recents-2-2.patch
cd ../../..
cd packages/services/Telephony
git apply -v ../../../device/meizu/m86/patches/packages/services/Telephony/46280baa5e557b76a262da27b673b0ca222e3998.patch
cd ../../..
cd system/core
git apply -v ../../device/meizu/m86/patches/system/core/0001-shutup-camera-logs.patch
cd ../..
cd system/vold
git apply -v ../../device/meizu/m86/patches/system/vold/0001-disable-setexeccon-temporarily.patch
git apply -v ../../device/meizu/m86/patches/system/vold/0001-No-SD-encryption.patch
cd ../..
cd vendor/cmsdk
git apply -v ../../device/meizu/m86/patches/vendor/cmsdk/0001-Hifi-Settings-2-3.patch
cd ../..
echo -e "Patches Applied Successfully!\n"
