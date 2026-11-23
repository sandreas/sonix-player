#!/bin/sh
# Pick a dev build from a microSD card and hand it to the Sonix player at boot.
# Every path is overridable so the same script can be exercised on a host.
#
# Runtime flow: skip the card unless devoptions_unlocked is 1 in the device
# config; otherwise mount the card if needed, copy its binary to /tmp, umount,
# then run the result under sonix_launch. Without a card binary, run the
# installed one the same way. Delete the card file to go back to the installed
# firmware; turn Developer options off to skip the check entirely.

INSTALLED=${SONIX_INSTALLED:-/usr/bin/sonix_player}
CARD_ROOT=${SONIX_SD_ROOT:-/mnt/sd_0}
CARD="$CARD_ROOT/sonix_player"
MOUNTS_FILE=${SONIX_MOUNTS_FILE:-/proc/mounts}
MOUNTPOINT=${SONIX_MOUNTPOINT:-mountpoint}
DEVICES=${SONIX_DEVICES:-'/dev/mmcblk0p1 /dev/mmcblk1p1 /dev/mmcblk0 /dev/mmcblk1'}
MOUNT=${SONIX_MOUNT:-mount}
UMOUNT=${SONIX_UMOUNT:-umount}
STAGING=${SONIX_STAGING:-/tmp/sonix_player}
LAUNCH=${SONIX_LAUNCH:-/usr/bin/sonix_launch}
TEST_MODE=${SONIX_DEVBOOT_TEST:-}
CONFIG_FILE=${SONIX_CONFIG_FILE:-/usr/data/device_config.ini}
AWK=${SONIX_AWK:-awk}

log() {
	printf 'sonix_devboot: %s\n' "$1" >&2
}

# Read devoptions_unlocked from the INI-style device config written by the
# player's config_save(): "[system]" headings and "key = value" lines. Only an
# exact "1" opens the gate; missing, locked or corrupt values read as empty.
# busybox awk ships in the rootfs; SONIX_AWK lets host tests substitute it.
devoptions_value() {
	[ -r "$CONFIG_FILE" ] || return 0
	$AWK -v section=system -v key=devoptions_unlocked '
		/^[[:space:]]*\[/ {
			name = $0
			gsub(/^[[:space:]]*\[[[:space:]]*|[[:space:]]*\][[:space:]]*$/, "", name)
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
			inside = (name == section)
			next
		}
		inside && /=/ {
			line = $0
			eq = index(line, "=")
			k = substr(line, 1, eq - 1)
			v = substr(line, eq + 1)
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
			if (k == key) {
				print v
				exit
			}
		}
	' "$CONFIG_FILE" 2>/dev/null
}

# Scan the mounts file first, then ask mountpoint. Both are overridable for
# host tests; a minimal firmware usually has /proc/mounts but no mountpoint.
card_is_mounted() {
	if [ -r "$MOUNTS_FILE" ] && grep -q " $CARD_ROOT " "$MOUNTS_FILE" 2>/dev/null; then
		return 0
	fi
	if command -v "$MOUNTPOINT" >/dev/null 2>&1; then
		"$MOUNTPOINT" -q "$CARD_ROOT" >/dev/null 2>&1
		return $?
	fi
	return 1
}

# Partition nodes first, then whole-disk nodes, as in the player's system.c.
mount_card() {
	for dev in $DEVICES; do
		if [ -n "$TEST_MODE" ]; then
			[ -e "$dev" ] || continue
		else
			[ -b "$dev" ] || continue
		fi
		if $MOUNT -t vfat "$dev" "$CARD_ROOT" >/dev/null 2>&1; then
			return 0
		fi
	done
	return 1
}

main() {
	SELECTED=$INSTALLED
	CARD_MOUNTED=no
	UMOUNTED=no

	# Developer options gate the whole card check. With the flag off, skip
	# straight to the handoff: no mount, no umount and no "no card" noise on a
	# normal boot. The device loop and card reads only run when it is exactly 1.
	if [ "$(devoptions_value)" = 1 ]; then
		# 1. Mount the card only when the mount point is not already in use.
		if card_is_mounted; then
			log "card already mounted at $CARD_ROOT"
			CARD_MOUNTED=yes
		elif mount_card && card_is_mounted; then
			log "mounted card at $CARD_ROOT"
			CARD_MOUNTED=yes
		else
			log "no card at $CARD_ROOT"
		fi

		# 2. Read the card while it is mounted, then decide what to run.
		if [ "$CARD_MOUNTED" = yes ] && [ -f "$CARD" ]; then
			if cp "$CARD" "$STAGING" 2>/dev/null; then
				SELECTED=$STAGING
				log "SD binary selected; remove $CARD to disable"
			else
				log "copy of $CARD failed; using installed binary"
			fi
		else
			log "no card binary at $CARD; using installed binary"
		fi

		# 3. Umount in every branch, after all card reads have finished. This
		# leaves no file descriptor or working directory on the card. Retry once;
		# a card that cannot be umounted must not become the booted binary.
		if [ "$CARD_MOUNTED" = yes ]; then
			if $UMOUNT "$CARD_ROOT" >/dev/null 2>&1; then
				UMOUNTED=yes
				log "umounted $CARD_ROOT"
			else
				log "umount of $CARD_ROOT failed; retrying"
				if $UMOUNT "$CARD_ROOT" >/dev/null 2>&1; then
					UMOUNTED=yes
					log "umounted $CARD_ROOT after retry"
				else
					log "umount of $CARD_ROOT failed again; using installed binary"
					SELECTED=$INSTALLED
				fi
			fi
		fi
	fi

	# 4. Make the staged copy runnable, then hand it to the supervisor.
	# A card copy rejected above is left on disk, but stays non-executable.
	if [ "$SELECTED" = "$STAGING" ]; then
		chmod 755 "$STAGING" 2>/dev/null || log "chmod of $STAGING failed"
	fi

	if [ -x "$LAUNCH" ]; then
		HANDOFF=launch
	else
		HANDOFF=direct
	fi
	log "handoff=$HANDOFF $SELECTED"

	# Host contract: exactly three stdout lines, no exec.
	#   SELECTED=<path>       binary that would be run
	#   UMOUNT=<yes|no>       whether the card was umounted
	#   HANDOFF=launch|direct supervisor used, or direct exec
	if [ -n "$TEST_MODE" ]; then
		printf 'SELECTED=%s\n' "$SELECTED"
		printf 'UMOUNT=%s\n' "$UMOUNTED"
		printf 'HANDOFF=%s\n' "$HANDOFF"
		exit 0
	fi

	if [ "$HANDOFF" = launch ]; then
		exec "$LAUNCH" "$SELECTED"
	else
		exec "$SELECTED"
	fi
}

main
