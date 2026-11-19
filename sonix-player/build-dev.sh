#!/bin/sh

make target -j$(nproc)

adb shell 'kill -HUP $(pgrep sonix_launch)'
adb shell 'kill -HUP $(pgrep sonix_player)'
adb shell 'kill -HUP $(pgrep sonix_player_debug)'

adb push sonix_player_debug /mnt/sd_0
