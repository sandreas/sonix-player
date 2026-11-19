#!/bin/sh

ulimit -s 1024
export MALLOC_ARENA_MAX=1

killall sonix_player >/dev/null 2>&1
killall -9 sonix_player >/dev/null 2>&1

if [ -f "/usr/bin/batd" ]; then
    killall batd >/dev/null 2>&1
    killall -9 batd >/dev/null 2>&1
    #/usr/bin/batd -v -s -t5 -o /mnt/sd_0/batlog.txt &
fi

# SD-Karte mounten, Player kopieren und aushängen
if mount /dev/mmcblk0p1 /mnt/sd_0 &&
   [ -f /mnt/sd_0/sonix_player ] &&
   cp /mnt/sd_0/sonix_player /tmp/sonix_player &&
   umount /mnt/sd_0; then

    chmod +x /tmp/sonix_player
    /tmp/sonix_player

else
    # Sicherstellen, dass SD-Karte ausgehängt ist
    if mountpoint -q /mnt/sd_0; then
        umount /mnt/sd_0
    fi

    # Original-Player starten
    /usr/bin/sonix_player
fi

sleep 1
reboot

