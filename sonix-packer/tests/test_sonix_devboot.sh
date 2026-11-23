#!/bin/sh
# Host-side tests for sonix_devboot.sh.
#
# Test-mode contract (documented here because the script relies on it): with
# SONIX_DEVBOOT_TEST=1 the helper prints exactly three stdout lines and never
# execs:
#   SELECTED=<path>       binary that would be run
#   UMOUNT=<yes|no>       whether /mnt/sd_0 was umounted
#   HANDOFF=launch|direct supervisor used, or direct exec
# Every decision is also logged as one short line on stderr with the prefix
# "sonix_devboot: ". A failed umount is retried once; two failures fall back
# to the installed binary while leaving the staged card copy non-executable.
#
# Fixtures are synthesised here: the real sonix-packer/sonix_player binary is
# untracked and absent from this worktree, so a short text file stands in for
# the card build. No ELF, size validation or boot counter is involved.
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HELPER="$ROOT/sonix-packer/sonix_devboot.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' 0 1 2 3 15

SD_ROOT="$TMP/sd"
MOUNTS="$TMP/mounts"
DEV_DIR="$TMP/dev"
STAGING="$TMP/staging/sonix_player"
BAD_STAGING="$TMP/no-such-dir/sonix_player"
INSTALLED="$TMP/usr/bin/sonix_player"
NO_LAUNCH="$TMP/no-such-launch"
CARD_BIN="$TMP/card.bin"
LAUNCH_STUB="$TMP/bin/launch-stub"
MOUNT_STUB="$TMP/bin/mount"
UMOUNT_STUB="$TMP/bin/umount"
MOUNTPOINT_STUB="$TMP/bin/mountpoint"
CALL_LOG="$TMP/mount.calls"
UMOUNT_LOG="$TMP/umount.calls"
ORDER_LOG="$TMP/order.calls"
PREPARED="$TMP/card.prepared"
MOUNTED_STATE="$TMP/mounted.state"
UMOUNT_MODE="$TMP/umount.mode"
UMOUNT_ATTEMPTED="$TMP/umount.attempted"
CONFIG_FILE="$TMP/device_config.ini"
ERR="$TMP/stderr"

mkdir -p "$SD_ROOT" "$DEV_DIR" "$TMP/staging" "$TMP/bin"

# --- synthesise fixtures ---------------------------------------------------
printf 'dev build\n' > "$CARD_BIN"
printf 'dev build\n' > "$PREPARED"
# Default device config: Developer options unlocked, so the existing cases
# keep exercising the full card flow unless a case overrides CASE_CONFIG.
printf '[system]\ndevoptions_unlocked = 1\n' > "$CONFIG_FILE"

# Block-device fixtures are plain files; test mode checks -e, device mode -b.
for d in mmcblk0p1 mmcblk1p1 mmcblk0 mmcblk1; do : > "$DEV_DIR/$d"; done

printf '#!/bin/sh\nexit 0\n' > "$LAUNCH_STUB"
chmod 755 "$LAUNCH_STUB"

# Mount stub: log argv, optionally place the prepared card file at the mount
# point, then register the mount in both the mounts file and the state file.
cat > "$MOUNT_STUB" <<EOF
#!/bin/sh
printf 'mount %s\n' "\$*" >> "$ORDER_LOG"
printf '%s\n' "\$*" >> "$CALL_LOG"
if [ -f "$PREPARED" ]; then
	cp "$PREPARED" "$SD_ROOT/sonix_player"
fi
printf '1\n' > "$MOUNTED_STATE"
printf '%s %s vfat rw 0 0\n' "\$3" "\$4" >> "$MOUNTS"
exit 0
EOF
chmod 755 "$MOUNT_STUB"

# Umount stub: log every attempt and follow the requested mode.
#   empty  -> succeed
#   once   -> fail the first call, succeed on the retry
#   always -> fail every call
cat > "$UMOUNT_STUB" <<EOF
#!/bin/sh
printf 'umount %s\n' "\$*" >> "$ORDER_LOG"
printf '%s\n' "\$*" >> "$UMOUNT_LOG"
mode=\$(cat "$UMOUNT_MODE" 2>/dev/null)
case "\$mode" in
	once)
		if [ ! -f "$UMOUNT_ATTEMPTED" ]; then
			: > "$UMOUNT_ATTEMPTED"
			exit 1
		fi
		;;
	always)
		exit 1
		;;
esac
: > "$MOUNTED_STATE"
: > "$MOUNTS"
exit 0
EOF
chmod 755 "$UMOUNT_STUB"

# Mountpoint stub: consulted when the mounts file has no match.
cat > "$MOUNTPOINT_STUB" <<EOF
#!/bin/sh
[ "\$1" = -q ] || exit 2
[ "\$(cat "$MOUNTED_STATE" 2>/dev/null)" = 1 ]
EOF
chmod 755 "$MOUNTPOINT_STUB"

# --- test machinery --------------------------------------------------------
PASS=0
FAILS=0
pass() { printf 'ok   - %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf 'FAIL - %s: %s\n' "$1" "$2"; FAILS=$((FAILS + 1)); }

reset_case() {
	: > "$MOUNTS"
	: > "$CALL_LOG"
	: > "$UMOUNT_LOG"
	: > "$ORDER_LOG"
	: > "$MOUNTED_STATE"
	: > "$UMOUNT_MODE"
	rm -f "$SD_ROOT/sonix_player" "$STAGING" "$UMOUNT_ATTEMPTED" "$ERR"
	rm -rf "$TMP/no-such-dir"
	CASE_DEVICES=''
	CASE_LAUNCH="$NO_LAUNCH"
	CASE_STAGING="$STAGING"
	CASE_CONFIG="$CONFIG_FILE"
	CASE_FAILS=$FAILS
}

finish_case() {
	if [ "$FAILS" -eq "$CASE_FAILS" ]; then
		pass "$LABEL"
	fi
}

run_case() {
	out=$(SONIX_DEVBOOT_TEST=1 \
		SONIX_MOUNTS_FILE="$MOUNTS" \
		SONIX_MOUNTPOINT="$MOUNTPOINT_STUB" \
		SONIX_SD_ROOT="$SD_ROOT" \
		SONIX_DEVICES="$CASE_DEVICES" \
		SONIX_MOUNT="$MOUNT_STUB" \
		SONIX_UMOUNT="$UMOUNT_STUB" \
		SONIX_INSTALLED="$INSTALLED" \
		SONIX_STAGING="$CASE_STAGING" \
		SONIX_LAUNCH="$CASE_LAUNCH" \
		SONIX_CONFIG_FILE="$CASE_CONFIG" \
		sh "$HELPER" 2>"$ERR")
}

assert_line() {
	printf '%s\n' "$out" | grep -qxF -- "$1" || \
		bad "$LABEL" "missing line '$1' (got: $(printf '%s' "$out" | tr '\n' '|'))"
}

assert_selection() {
	assert_line "SELECTED=$1"
	assert_line "UMOUNT=$2"
	assert_line "HANDOFF=$3"
	lines=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
	[ "$lines" = 3 ] || bad "$LABEL" "expected 3 stdout lines, got $lines"
	bad_lines=$(grep -vc '^sonix_devboot: ' "$ERR" 2>/dev/null || true)
	[ "$bad_lines" = 0 ] || bad "$LABEL" "unexpected stderr: $(cat "$ERR")"
}

check_staged() {
	[ -f "$STAGING" ] || { bad "$LABEL" 'staged file missing'; return; }
	mode=$(stat -c%a "$STAGING")
	[ "$mode" = 755 ] || bad "$LABEL" "mode $mode != 755"
	cmp -s "$1" "$STAGING" || bad "$LABEL" "staged file differs from $1"
}

mounted_card() {
	printf '1\n' > "$MOUNTED_STATE"
	printf '/dev/mmcblk0p1 %s vfat rw 0 0\n' "$SD_ROOT" >> "$MOUNTS"
	cp "$1" "$SD_ROOT/sonix_player"
}

mounted_empty() {
	printf '1\n' > "$MOUNTED_STATE"
	printf '/dev/mmcblk0p1 %s vfat rw 0 0\n' "$SD_ROOT" >> "$MOUNTS"
}

assert_umount_last() {
	last=$(tail -1 "$ORDER_LOG" 2>/dev/null)
	case "$last" in
		umount*) ;;
		*) bad "$LABEL" "umount is not the last recorded action: $(cat "$ORDER_LOG")" ;;
	esac
}

assert_umount_attempts() {
	attempts=$(wc -l < "$UMOUNT_LOG" | tr -d ' ')
	[ "$attempts" = "$1" ] || \
		bad "$LABEL" "expected $1 umount attempts, got $attempts: $(cat "$UMOUNT_LOG")"
}

# --- cases -----------------------------------------------------------------
reset_case
CASE_LAUNCH="$LAUNCH_STUB"
LABEL='no card -> installed, launch handoff, no umount'
run_case
assert_selection "$INSTALLED" no launch
[ ! -s "$CALL_LOG" ] || bad "$LABEL" "unexpected mount: $(cat "$CALL_LOG")"
[ ! -s "$UMOUNT_LOG" ] || bad "$LABEL" "unexpected umount: $(cat "$UMOUNT_LOG")"
finish_case

reset_case
cp "$CARD_BIN" "$SD_ROOT/sonix_player"
LABEL='stray card file without a mount -> installed, no umount'
run_case
assert_selection "$INSTALLED" no direct
[ ! -s "$CALL_LOG" ] || bad "$LABEL" "unexpected mount: $(cat "$CALL_LOG")"
finish_case

reset_case
mounted_card "$CARD_BIN"
CASE_LAUNCH="$LAUNCH_STUB"
LABEL='card already mounted -> copy, umount, SD handoff'
run_case
assert_selection "$STAGING" yes launch
check_staged "$CARD_BIN"
[ ! -s "$CALL_LOG" ] || bad "$LABEL" "mount was called: $(cat "$CALL_LOG")"
grep -Fqx -- "$SD_ROOT" "$UMOUNT_LOG" || \
	bad "$LABEL" "umount argv wrong: $(cat "$UMOUNT_LOG")"
assert_umount_last
finish_case

reset_case
printf '1\n' > "$MOUNTED_STATE"
cp "$CARD_BIN" "$SD_ROOT/sonix_player"
LABEL='mountpoint command sees mounted card -> no mount call'
run_case
assert_selection "$STAGING" yes direct
[ ! -s "$CALL_LOG" ] || bad "$LABEL" "mount was called: $(cat "$CALL_LOG")"
check_staged "$CARD_BIN"
finish_case

for dev in mmcblk0p1 mmcblk1p1 mmcblk0 mmcblk1; do
	reset_case
	CASE_DEVICES="$DEV_DIR/$dev"
	cp "$CARD_BIN" "$PREPARED"
	CASE_LAUNCH="$LAUNCH_STUB"
	LABEL="card not mounted, device $dev -> mount, copy, umount, SD handoff"
	run_case
	assert_selection "$STAGING" yes launch
	grep -Fq -- "-t vfat $DEV_DIR/$dev $SD_ROOT" "$CALL_LOG" || \
		bad "$LABEL" "mount argv wrong: $(cat "$CALL_LOG")"
	check_staged "$CARD_BIN"
	assert_umount_last
	finish_case
done

reset_case
CASE_DEVICES="$DEV_DIR/mmcblk0p1 $DEV_DIR/mmcblk1p1 $DEV_DIR/mmcblk0 $DEV_DIR/mmcblk1"
cp "$CARD_BIN" "$PREPARED"
LABEL='all device candidates present -> first one tried only'
run_case
assert_selection "$STAGING" yes direct
mount_calls=$(wc -l < "$CALL_LOG" | tr -d ' ')
[ "$mount_calls" = 1 ] || bad "$LABEL" "expected 1 mount call, got $mount_calls"
grep -Fqx -- "-t vfat $DEV_DIR/mmcblk0p1 $SD_ROOT" "$CALL_LOG" || \
	bad "$LABEL" "wrong first device: $(cat "$CALL_LOG")"
finish_case

reset_case
mounted_empty
CASE_LAUNCH="$LAUNCH_STUB"
LABEL='mounted card without binary -> umount, installed fallback'
run_case
assert_selection "$INSTALLED" yes launch
[ ! -e "$STAGING" ] || bad "$LABEL" 'staged file created with no card binary'
assert_umount_last
finish_case

reset_case
mounted_card "$CARD_BIN"
CASE_STAGING="$BAD_STAGING"
CASE_LAUNCH="$LAUNCH_STUB"
LABEL='copy failure -> umount, installed fallback'
run_case
assert_selection "$INSTALLED" yes launch
grep -q 'copy of .* failed' "$ERR" || bad "$LABEL" "no copy failure logged: $(cat "$ERR")"
assert_umount_last
finish_case

reset_case
mounted_card "$CARD_BIN"
printf 'always\n' > "$UMOUNT_MODE"
CASE_LAUNCH="$LAUNCH_STUB"
LABEL='umount fails twice -> installed fallback, staged copy left harmless'
run_case
assert_selection "$INSTALLED" no launch
assert_umount_attempts 2
grep -q 'umount of .* failed; retrying' "$ERR" || \
	bad "$LABEL" "no first failure logged: $(cat "$ERR")"
grep -q 'failed again; using installed binary' "$ERR" || \
	bad "$LABEL" "no final fallback logged: $(cat "$ERR")"
[ -f "$STAGING" ] || bad "$LABEL" 'staged copy was removed'
staged_mode=$(stat -c%a "$STAGING" 2>/dev/null || true)
[ "$staged_mode" != 755 ] || \
	bad "$LABEL" "staged copy was made executable: $staged_mode"
finish_case

reset_case
mounted_card "$CARD_BIN"
printf 'once\n' > "$UMOUNT_MODE"
CASE_LAUNCH="$LAUNCH_STUB"
LABEL='umount fails once then succeeds -> SD binary still selected'
run_case
assert_selection "$STAGING" yes launch
assert_umount_attempts 2
grep -q 'umounted .* after retry' "$ERR" || \
	bad "$LABEL" "no retry success logged: $(cat "$ERR")"
check_staged "$CARD_BIN"
finish_case

reset_case
mounted_card "$CARD_BIN"
LABEL='launcher absent on SD path -> direct handoff'
run_case
assert_selection "$STAGING" yes direct
finish_case

reset_case
mounted_empty
LABEL='launcher absent on fallback path -> direct handoff'
run_case
assert_selection "$INSTALLED" yes direct
finish_case

reset_case
printf '[system]\ndevoptions_unlocked = 0\n' > "$CASE_CONFIG"
mounted_card "$CARD_BIN"
CASE_LAUNCH="$LAUNCH_STUB"
LABEL='devoptions off -> card ignored, installed, no mount or umount'
run_case
assert_selection "$INSTALLED" no launch
[ ! -s "$CALL_LOG" ] || bad "$LABEL" "unexpected mount: $(cat "$CALL_LOG")"
[ ! -s "$UMOUNT_LOG" ] || bad "$LABEL" "unexpected umount: $(cat "$UMOUNT_LOG")"
if grep -q 'no card' "$ERR"; then
	bad "$LABEL" "no-card line leaked: $(cat "$ERR")"
fi
finish_case

reset_case
CASE_CONFIG="$TMP/no-such-config.ini"
cp "$CARD_BIN" "$SD_ROOT/sonix_player"
CASE_LAUNCH="$LAUNCH_STUB"
LABEL='missing config -> card ignored, installed, no mount'
run_case
assert_selection "$INSTALLED" no launch
[ ! -s "$CALL_LOG" ] || bad "$LABEL" "unexpected mount: $(cat "$CALL_LOG")"
[ ! -s "$UMOUNT_LOG" ] || bad "$LABEL" "unexpected umount: $(cat "$UMOUNT_LOG")"
finish_case

reset_case
printf '[other]\ndevoptions_unlocked = 1\n' > "$CASE_CONFIG"
mounted_card "$CARD_BIN"
CASE_LAUNCH="$LAUNCH_STUB"
LABEL='key in other section -> card ignored, installed, no mount'
run_case
assert_selection "$INSTALLED" no launch
[ ! -s "$CALL_LOG" ] || bad "$LABEL" "unexpected mount: $(cat "$CALL_LOG")"
[ ! -s "$UMOUNT_LOG" ] || bad "$LABEL" "unexpected umount: $(cat "$UMOUNT_LOG")"
finish_case

reset_case
printf '[system]\n  devoptions_unlocked   =   1  \n' > "$CASE_CONFIG"
mounted_card "$CARD_BIN"
CASE_LAUNCH="$LAUNCH_STUB"
LABEL='devoptions value with surrounding spaces -> normal card flow'
run_case
assert_selection "$STAGING" yes launch
check_staged "$CARD_BIN"
[ ! -s "$CALL_LOG" ] || bad "$LABEL" "unexpected mount: $(cat "$CALL_LOG")"
assert_umount_last
finish_case

reset_case
CASE_LAUNCH="$LAUNCH_STUB"
LABEL='devoptions on, no card -> installed fallback, no mount or umount'
run_case
assert_selection "$INSTALLED" no launch
[ ! -s "$CALL_LOG" ] || bad "$LABEL" "unexpected mount: $(cat "$CALL_LOG")"
[ ! -s "$UMOUNT_LOG" ] || bad "$LABEL" "unexpected umount: $(cat "$UMOUNT_LOG")"
finish_case

printf '\n%d passed, %d failed\n' "$PASS" "$FAILS"
[ "$FAILS" -eq 0 ]
