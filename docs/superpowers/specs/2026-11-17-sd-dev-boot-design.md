# SD-card dev build override — design (approved)

- Date: 2026-11-17
- Issue: Jepl4r/sonix-player#147
- Status: **Approved 2026-11-17.** The direction changed after @sandreas' second comment on
  PR #295: ADB, binary validation and the boot counter were all dropped. The shipped flow is
  a single file on a FAT32 card that arms a persistent custom or patched binary, gated on
  Developer options being unlocked. A later comment from @sandreas added that gate; the
  human partner approved adopting it. No product code had been written when this was
  approved.

## Intent and why

@sandreas, who originally asked for this in #147, wants a patched build — and eventually a
completely custom binary (e.g. Rust) — to persist across reboots, with less binding between
firmware and running software. The mechanism that came out of PR #295 runs a `make target`
binary over ADB only until the next reboot, which is not enough for that workflow.

The new workflow is armed with one file: put a binary named `sonix_player` at the root of a
FAT32 microSD card and reboot. Every boot runs it instead of `/usr/bin/sonix_player`.
Removing or renaming that file returns to the firmware binary — no reflash, no recovery
mode, and no ADB at any point. The card is read only when Developer options are unlocked;
the user arms that by tapping Build number five times in About. With Developer options
locked, the helper runs the firmware binary without a mount attempt.

The timing problem from #147 is confirmed by the code: the card is not mounted when the
launcher runs. The player mounts it itself, *after* it has started services
(`main.c:2053` → `mount_sd()` at `system.c:668-740`). A check at
`/mnt/sd_0/sonix_player` before the exec would otherwise see an empty directory on internal
UBIFS, not the card (`system.c:320-330`, `factoryreset.c:50-54`).

## Scope

- **Single-file switch.** `/mnt/sd_0/sonix_player` on a FAT32 card is the only control.
- **Developer-options gate.** Read `devoptions_unlocked` from `[system]` in
  `/usr/data/device_config.ini`. Mount the card only when the value is `1`. With the value
  absent or `0`, run the firmware binary without a mount attempt.
- **One-file revert.** Remove or rename it; no reflash, no ADB, no state files.
- **Both players.** One helper installed by the packer for R1 and R3 Pro II.
- **No writes to rootfs.** rootfs is read-only squashfs (`sonix_firmware_packer.sh:658-659`;
  `work250/rootfs/etc/inittab:17-30`, remount line commented). The firmware binary is never
  modified; the card copy runs from `/tmp`.
- **Card unmounted before the player starts.** The helper unmounts in every branch; the
  player's own mount logic runs normally afterwards (`system.c:681-704`, `system.c:757`).

Not in scope: a new developer-option toggle or marker file (the gate reads a flag the
settings UI already writes), a first-party toolchain for custom languages, or replacing the
OTA path (`firmware.c:104-159`).

## Approaches considered

The launcher script is the only place that runs before the player and can mount the card. A
small helper installed by the packer, `sonix_devboot.sh`, does the mount, copy and unmount,
then hands both paths to `sonix_launch` — no C changes and one stable firmware-side file.
This matches the shape of the script @sandreas originally proposed. Installing it from the
packer keeps R1 and R3 Pro II on one source of truth
(`sonix_firmware_packer.sh:67,556-600`).

A `devmode` marker and a boot counter in `/usr/data` were considered and dropped: arming or
re-arming either needs ADB or a PC, which the user forbade, and @sandreas measured no boot
delay, so there is no timing problem to guard against. Size/ELF validation, an ADB helper,
and ADB verification were removed in the same change. Any binary is accepted; a bad one is
recovered by removing the card file.

The Developer-options gate differs from the rejected `devmode` marker. `devoptions_unlocked`
already exists in `/usr/data/device_config.ini`, and the settings UI writes it when the user
taps Build number five times in About (`systempage.c:158,180-181`). The gate needs no ADB,
writes no new file and adds no second toggle. @sandreas proposed reading it before mounting;
the human partner approved adopting that check.

## Decided design

### Build-time changes

1. `sonix-packer/sonix_devboot.sh` (new): one source of truth, installed for both models.
2. `sonix-packer/sonix_firmware_packer.sh`:
   - `DEVBOOT_SH="$SCRIPT_DIR/sonix_devboot.sh"` next to `PLAYER_BIN`/`LAUNCH_BIN`
     (`:65-67`).
   - In section 5c (`:556-600`), install the helper at 755 beside `sonix_launch`
     (`:570-572`).
   - The awk at `:583-591` prints an **additional** guard line above the existing launch
     line, keeping the original intact for idempotency and as a fallback:
     ```sh
     [ -x /usr/bin/sonix_devboot.sh ] && exec /usr/bin/sonix_devboot.sh
     [ -x /usr/bin/sonix_launch ] && exec /usr/bin/sonix_launch /usr/bin/sonix_player
     ```
   - The rewrite runs only when exactly one line equals `/usr/bin/sonix_player` and
     `sonix_launch` is installed (`:578-600`); the init script tests launcher existence
     with `-f`, not `-x` (`:507-517`).
3. `README.md`: the `### Persistent dev build from microSD` subsection documents the
   one-file workflow and the Developer-options prerequisite; the packer input tree lists
   `sonix_devboot.sh` beside `sonix_launch`.

### Runtime flow of `sonix_devboot.sh`

Run as `/bin/sh` from `sonix_player.sh` at S92, with rootfs read-only and `/usr/data`
already mounted (S21).

1. Set `INSTALLED=/usr/bin/sonix_player`, `CARD=/mnt/sd_0/sonix_player`,
   `TMP=/tmp/sonix_player`, `CONFIG=/usr/data/device_config.ini`.
2. **Gate on Developer options.** Read `devoptions_unlocked` from `$CONFIG`. Match the format
   the config writer emits: a `[system]` header followed by `key = value` lines
   (`config.c:281-284`). If the value is not `1`, start `$INSTALLED` through
   `sonix_launch` and do not touch the card; no mount attempt happens
   (`systempage.c:158,180-181`). The key exists in the shipped config, so this needs no ADB
   and writes no new file.
3. **Make the card visible if needed.** If the mount point is not already mounted, try, in
   order, `/dev/mmcblk0p1`, `/dev/mmcblk1p1`, `/dev/mmcblk0`, `/dev/mmcblk1` — only `-b`
   devices — `mount -t vfat "$dev" /mnt/sd_0`, breaking on success. The device order
   matches the player's own candidate list (`system.c:332-340`); the player shells out to
   busybox `mount` as well (`system.c:613-644`, `sysserver.h:22`).
4. **Verify the mount point.** Require a `sd_0` entry in `/proc/mounts`; otherwise treat
   the override as absent so a stray file on internal UBIFS is never executed
   (`system.c:354-363`, `factoryreset.c:50-54`). Do not remount an already-mounted card
   (`system.c:681-704`).
5. **Select the binary.** If `$CARD` is a regular file, `cp` it to `$TMP`, `chmod 755`, and
   set `SELECTED=$TMP`; otherwise set `SELECTED=$INSTALLED`.
6. **Unmount the card in every branch.** If the helper mounted it, `umount /mnt/sd_0` after
   the copy, or in the no-file branch, so the player starts with the card unmounted.
7. **Hand off.** `exec /usr/bin/sonix_launch "$SELECTED"` so the dev and firmware paths are
   supervised identically — `sonix_launch` runs the player and reboots ~1 s after any exit
   (`launcher/sonix_launch.c:1-10,111-127`; `Makefile:330-338`). If `sonix_launch` is absent,
   `exec "$SELECTED"` directly, mirroring the original launcher.

**No binary validation.** There is no size check, no ELF/ABI check, no boot counter, no new
devmode marker and no ADB. The Developer-options gate reads an existing key; it does not
validate the binary. Recovery from a corrupt or crashing binary is to remove or rename the
file on the card; the next boot returns to the firmware binary. Custom binaries from other
projects are accepted as-is.

## Verification plan (before claiming done)

Host-side (no device):

1. `sh -n sonix_devboot.sh`.
2. In a fake root with a stub `/proc/mounts`, stub `mount`/`umount` and a stub config file,
   assert: locked Developer options → `$INSTALLED` selected with no mount attempt; card file
   present with the key at `1` → `$TMP` selected and the card unmounted; no card file →
   `$INSTALLED` selected and the card unmounted; no real mount → `$INSTALLED` selected; the
   device loop tries the four nodes in order; `sonix_launch` receives the selected path on
   both branches.
3. Re-run the packer into a scratch output and inspect `usr/bin/sonix_player.sh`: both new
   and original lines present, helper installed at 755 in both model trees.

Device-side (requires an R1 or R3 Pro II — cannot be done here):

4. No card / no file → identical boot to stock firmware.
5. Valid binary named `sonix_player` on a FAT32 card → reboot twice; dev binary runs both
   times.
6. Bad binary → remove the file from the card and boot normally (recovery path).
7. Developer options locked → no mount attempt and the firmware binary runs. Unlock with
   five taps on Build number, reboot, and the card binary runs.
