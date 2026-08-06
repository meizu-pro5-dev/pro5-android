#!/bin/bash

VENDOR=meizu
DEVICE=m86

BASE=../../../vendor/$VENDOR/$DEVICE/proprietary
rm -rf $BASE/*

for FILE in `cat proprietary-files.txt | grep -v ^# | grep -v ^$ `; do
    DIR=`dirname $FILE`
    if [ ! -d $BASE/$DIR ]; then
        mkdir -p $BASE/$DIR
    fi

    if [ -z "$1" ]; then
        adb pull /system/$FILE $BASE/$FILE
    else
        cp $1/system/$FILE $BASE/$FILE
    fi
done

./setup-makefiles.sh
