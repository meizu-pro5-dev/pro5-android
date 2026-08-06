#!/bin/bash
cd ../../../..
cd frameworks/av
git apply -v ../../device/meizu/m86/patches/frameworks/av/0001-Add-samsung-WFD.patch
cd ../..
cd hardware/libhardware
git apply -v ../../device/meizu/m86/patches/hardware/libhardware/0001-For-stock-audio-hals-to-work.patch
cd ../..
echo -e "Patches Applied Successfully!\n"
