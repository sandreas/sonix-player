# SD-card dev build override Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a developer put a compatible `sonix_player` binary at `/mnt/sd_0/sonix_player` and have every boot run it instead of the read-only installed binary, with a persistent crash-loop guard and a one-file revert.

**Architecture:** A single POSIX `sh` helper lives next to the packer and is installed into the squashfs at `/usr/bin/sonix_devboot.sh`. The packer adds one line to the launcher script so the helper runs before `exec sonix_launch`; the helper mounts the card itself (nothing else does at S92), validates and stages the binary into `/tmp`, updates a boot counter in `/usr/data`, and execs `sonix_launch` with the chosen path. No C changes, no writes to the root filesystem.

**Tech Stack:** POSIX `sh` (busybox ash on device), `mount -t vfat`, `stat`, `od`, `cut`, `grep /proc/mounts`, `mksquashfs` via the existing packer.

**Spec:** `docs/superpowers/specs/2026-11-17-sd-dev-boot-design.md`

## Global Constraints

- POSIX `sh` only; tabs for indentation; English ASCII comments (repo convention, PR #295).
- Card binary path: `/mnt/sd_0/sonix_player`; installed binary: `/usr/bin/sonix_player`.
- Validation: size 1–32 MiB (1048576–33554432 bytes); header bytes `7f454c460101` (ELF32 LSB) and `02000800` at hex offset 33–40 (`ET_EXEC` + `EM_MIPS`). Use `cut -c`/`case`, not `${var:0:n}`.
- Staging: copy to `/tmp/.sonix_dev_player.$$`, `mv -f` to `/tmp/sonix_dev_player`, `chmod 755`. No partial binary at the executed path. Nothing written to the rootfs.
- Boot-loop guard: state in `/usr/data/.sonix_devboot_ts` and `/usr/data/.sonix_devboot_count`; rapid window 120 s; disable override when count > 4.
- Both models (R1, R3 Pro II) installed from one helper file by the packer.
- Keep the existing `exec /usr/bin/sonix_launch /usr/bin/sonix_player` line in the launcher; add a line above it, never replace it.
- The init script tests launcher existence with `-f`, not `-x`: installed helper must be chmod 755.
- Device glibc ABI 2.22: the binary contract is documented in README; no toolchain is shipped.
- The helper must treat a path as a card only when `/proc/mounts` shows a real mount at the SD root; `/mnt/sd_0` unmounted is a directory on internal UBIFS.
- If the card is already mounted, do not remount it.

## Review Focus

These are the failure modes the spec implies that no happy-path test covers. Each maps to a test in the owning task.

1. Card absent, but a stray `/usr/data/mnt/sd_0/sonix_player` exists — must select the installed binary, not the stray file. → Task 1, "stray file" case.
2. Card present with a valid binary but `sonix_launch` missing — must exec the binary directly. → Task 1, "direct handoff" case.
3. A valid binary that crashes immediately — must not reboot forever; the guard disables the override. → Task 2, "rapid boots" case.
4. Packer re-run on a launcher that already has the devboot line — must not duplicate lines. → Task 3, "idempotent" case.
5. Card already mounted (e.g. from stock UI) — helper must read the binary and not call `mount` again. → Task 1, "already mounted" case.
6. ELF magic correct but wrong machine/type — must fall back to the installed binary. → Task 1, "wrong machine" and "wrong type" cases.

---

### Task 1: Helper core — detect, validate, stage, handoff

**Files:**
- Create: `sonix-packer/sonix_devboot.sh`
- Create: `sonix-packer/tests/test_sonix_devboot.sh`
- Test fixture (read-only): `sonix-packer/sonix_player` (existing 10,139,468-byte ELF32 LE MIPS `ET_EXEC`)

**Interfaces:**
- Consumes: nothing.
- Produces: helper supporting env overrides `SONIX_DEVBOOT_TEST`, `SONIX_MOUNTS_FILE`, `SONIX_SD_ROOT`, `SONIX_DEVICES`, `SONIX_MOUNT`, `SONIX_INSTALLED`, `SONIX_STAGING`, `SONIX_LAUNCH`, `SONIX_DATA_DIR`. In test mode it prints `SELECTED=<path>`, `HANDOFF=launch|direct`, `OVERRIDE=enabled` and exits without exec'ing; these lines are the contract Tasks 2–3 tests parse.

- [ ] **Step 1: Write the failing test harness**

Create `sonix-packer/tests/test_sonix_devboot.sh` with `mktemp -d` + `trap` cleanup. It builds these fixtures from the real binary: `GOOD` (copy), `SMALL` (`head -c 20`), `NONELF` (text), `WRONGMACHINE` (copy with bytes 18–19 zeroed via `dd ... seek=18 count=2 conv=notrunc`), `WRONGTYPE` (copy with bytes 16–17 set to `03 00`). It creates a stub `mount` in `$TMP/bin` that appends its argv to `$TMP/mount.calls` and copies a prepared card file into `$SD_ROOT` when invoked. Device fixtures are regular files under `$TMP/dev/` (test mode uses `-e`, device uses `-b`). A helper function `run_case()` sets `SONIX_*` env vars, runs the helper with `sh`, and captures stdout.

Add cases asserting:
- no card file → `SELECTED=` equals `SONIX_INSTALLED`, `HANDOFF=launch`
- card file present, mounts file empty → `SELECTED=` equals `SONIX_INSTALLED` (stray-file guard)
- card file present, mounts file contains `$SD_ROOT`, `GOOD` → `SELECTED=` equals `$SONIX_STAGING`, file exists, mode 755, `cmp` equals `GOOD`
- same but `SMALL`, `NONELF`, `WRONGMACHINE`, `WRONGTYPE` → each selects `SONIX_INSTALLED`
- card already mounted → `$TMP/mount.calls` is empty, `SELECTED=` equals `$SONIX_STAGING`
- card not mounted → mount stub called with `/dev/mmcblk0p1` and `$SD_ROOT`, then selection succeeds
- `SONIX_LAUNCH` points to a nonexistent path → `HANDOFF=direct`

- [ ] **Step 2: Run tests to verify they fail**

Run: `sh sonix-packer/tests/test_sonix_devboot.sh`
Expected: fails immediately — `sonix_devboot.sh` does not exist.

- [ ] **Step 3: Implement `sonix-packer/sonix_devboot.sh`**

Structure, all paths overridable by the env vars above:
- `fail()` prints `sonix_devboot: <msg>` to stderr.
- `ensure_card_mounted()`: if `$SD_ROOT/sonix_player` is not a regular file, iterate `$SONIX_DEVICES`, skip non-block devices (`-b`, or `-e` in test mode), run `$SONIX_MOUNT -t vfat "$dev" "$SD_ROOT"`, break on success.
- `card_is_mounted()`: `grep -q " $SD_ROOT " "$SONIX_MOUNTS_FILE"`. If false, selection is the installed binary. During a real mount retry `/proc/mounts` once after the mount call.
- `valid_binary()`: size via `stat -c%s` within 1048576–33554432; header via `od -An -tx1 -N20 "$1" | tr -d ' \n'`; `ident=$(printf '%s' "$hdr" | cut -c1-12)`; `mach=$(printf '%s' "$hdr" | cut -c33-40)`; require `7f454c460101` and `02000800`.
- `stage()`: `cp "$CARD" /tmp/.sonix_dev_player.$$`, `mv -f` to `$SONIX_STAGING`, `chmod 755`.
- Select `$SONIX_STAGING` on success, else `$SONIX_INSTALLED`; log the reason to stderr on each rejection.
- Handoff: if `[ -x "$SONIX_LAUNCH" ]` then `exec "$SONIX_LAUNCH" "$SELECTED"` else `exec "$SELECTED"`.
- In test mode: skip the final `exec`, print the three contract lines, exit 0. Still perform staging so the staged file can be asserted.

- [ ] **Step 4: Run tests to verify they pass**

Run: `sh sonix-packer/tests/test_sonix_devboot.sh`
Expected: PASS for all cases.

- [ ] **Step 5: Commit**

```bash
git add sonix-packer/sonix_devboot.sh sonix-packer/tests/test_sonix_devboot.sh
git commit -m "tools: add SD-card dev build selector"
```

### Task 2: Persistent boot-loop guard

**Files:**
- Modify: `sonix-packer/sonix_devboot.sh`
- Modify: `sonix-packer/tests/test_sonix_devboot.sh`

**Interfaces:**
- Consumes: Task 1's helper, env vars and test-mode output contract; `SONIX_DATA_DIR`, `SONIX_NOW_CMD` (default `date +%s`).
- Produces: state files `<DATA_DIR>/.sonix_devboot_ts` and `<DATA_DIR>/.sonix_devboot_count` (plain integers); test output adds `OVERRIDE=enabled|disabled` and `COUNT=<n>`.

- [ ] **Step 1: Write the failing guard tests**

Extend the harness with `FAKE_NOW` and a `NOW_CMD` stub (`printf '%s\n' "$FAKE_NOW"`), `SONIX_DATA_DIR="$TMP/data"`, and assertions:
- first override boot at `FAKE_NOW=1000` → `OVERRIDE=enabled`, `COUNT=1`, ts file contains `1000`
- second boot at `1010` → `COUNT=2`
- third boot at `1200` → `COUNT=1` (window expired, reset)
- five consecutive boots at `1000,1010,1020,1030,1040` → the fifth is `OVERRIDE=disabled`, `SELECTED=SONIX_INSTALLED`, `COUNT=5`
- when disabled, deleting both state files re-enables the override on the next boot
- guard runs only when an override was otherwise selected: with no card, no state files are created

- [ ] **Step 2: Run tests to verify they fail**

Run: `sh sonix-packer/tests/test_sonix_devboot.sh`
Expected: FAIL on the new `OVERRIDE=` assertions (line never printed).

- [ ] **Step 3: Implement `guard_allows_override()` in the helper**

Read `$DATA_DIR/.sonix_devboot_ts` and `$DATA_DIR/.sonix_devboot_count` with safe defaults (`0`), `now=$($NOW_CMD)`. If `now - last <= 120`, `count=$((count+1))`, else `count=1`. Write both files. Return false when `count > 4`. Call it only after a valid candidate binary has been staged; on false, log a one-line warning naming the recovery action and select `$SONIX_INSTALLED`. In test mode print `OVERRIDE=` and `COUNT=`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `sh sonix-packer/tests/test_sonix_devboot.sh`
Expected: PASS for all cases including the previous task's.

- [ ] **Step 5: Commit**

```bash
git add sonix-packer/sonix_devboot.sh sonix-packer/tests/test_sonix_devboot.sh
git commit -m "tools: guard SD dev override against reboot loops"
```

### Task 3: Packer wiring — install helper and rewrite launcher

**Files:**
- Modify: `sonix-packer/sonix_firmware_packer.sh:64-65` (constant), `:553-587` (section 5c)
- Create: `sonix-packer/tests/test_packer_devboot_wiring.sh`

**Interfaces:**
- Consumes: `sonix-packer/sonix_devboot.sh` from Task 1.
- Produces: `/usr/bin/sonix_devboot.sh` at mode 755 in both model squashfs trees; launcher line `[ -x /usr/bin/sonix_devboot.sh ] && exec /usr/bin/sonix_devboot.sh` above the existing `sonix_launch` line.

- [ ] **Step 1: Write the failing wiring test**

Create `sonix-packer/tests/test_packer_devboot_wiring.sh`. It:
- runs `sh -n sonix-packer/sonix_firmware_packer.sh`
- asserts the packer contains `DEVBOOT_SH=`, `chmod 755 "$SQUASH_DIR/usr/bin/sonix_devboot.sh"` and the two `# DEVBOT-AWK-BEGIN/END` marker comments
- extracts the awk program between the markers into a temp script with `sed -n '/BEGIN/,/END/p'` (dropping the marker lines), sets `LAUNCHER_FILE="$1"`, runs it on a copy of `sonix-packer/assets/R1/usr/bin/sonix_player.sh`, and asserts: exactly one `exec /usr/bin/sonix_devboot.sh`; exactly one `exec /usr/bin/sonix_launch /usr/bin/sonix_player`; devboot line appears before the launch line; the original `/usr/bin/sonix_player` line still exists below both
- runs the extracted awk a second time on its own output and asserts the counts are unchanged (idempotency)

- [ ] **Step 2: Run tests to verify they fail**

Run: `sh sonix-packer/tests/test_packer_devboot_wiring.sh`
Expected: FAIL — markers and `DEVBOOT_SH` absent.

- [ ] **Step 3: Modify the packer**

Add `DEVBOOT_SH="$SCRIPT_DIR/sonix_devboot.sh"` beside `PLAYER_BIN`/`LAUNCH_BIN`. In section 5c, after installing `sonix_launch`: `cp -f "$DEVBOOT_SH" "$SQUASH_DIR/usr/bin/sonix_devboot.sh"`, `chmod 755`, `say` the path. Replace the single `print` of the existing awk with a two-line print, wrapped in the `# DEVBOT-AWK-BEGIN` / `# DEVBOT-AWK-END` comment markers:

```sh
awk '$0 == "/usr/bin/sonix_player" {
	print "[ -x /usr/bin/sonix_devboot.sh ] && exec /usr/bin/sonix_devboot.sh"
	print "[ -x /usr/bin/sonix_launch ] && exec /usr/bin/sonix_launch /usr/bin/sonix_player"
} { print }'
```

Leave the `grep -q "exec /usr/bin/sonix_launch"` check at `:578` unchanged.

- [ ] **Step 4: Run tests to verify they pass**

Run: `sh sonix-packer/tests/test_packer_devboot_wiring.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add sonix-packer/sonix_firmware_packer.sh sonix-packer/tests/test_packer_devboot_wiring.sh
git commit -m "packer: install SD dev override helper and wire launcher"
```

### Task 4: README documentation and final host verification

**Files:**
- Modify: `README.md` (after the `### Trying a build without flashing` subsection added by PR #295, around `:229`)
- Modify: `docs/superpowers/specs/2026-11-17-sd-dev-boot-design.md` (no content change; verify status is Approved)

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: user-facing instructions; no code interface.

- [ ] **Step 1: Add the documentation subsection**

Write `### Persistent dev build from microSD` covering, in this order: copy a compatible `make target` binary to the card root as `sonix_player` (FAT32 card); reboot and it runs on every boot without flashing; remove/rename the file to return to the installed build; validation performed (1–32 MiB, ELF32 LE MIPS `ET_EXEC`); bad or crashing binaries fall back or are disabled after five rapid boots; recovery by removing the card or deleting `/usr/data/.sonix_devboot_count`; the binary contract (glibc 2.22 or static) for custom builds; note that this complements the ADB helper and works on both R1 and R3 Pro II.

- [ ] **Step 2: Run the full host verification suite**

Run:
```bash
sh -n sonix-packer/sonix_devboot.sh
sh -n sonix-packer/sonix_firmware_packer.sh
sh sonix-packer/tests/test_sonix_devboot.sh
sh sonix-packer/tests/test_packer_devboot_wiring.sh
```
Expected: all four commands exit 0 with no output from `sh -n`.

- [ ] **Step 3: Confirm no rootfs writes in the helper**

Run: `grep -nE '/usr/bin|/usr/lib|/etc/' sonix-packer/sonix_devboot.sh`
Expected: only `/usr/bin/sonix_launch` (read/exec) and `/usr/bin/sonix_player` (fallback) appear. No write operation targets those paths.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: document persistent SD-card dev build"
```

## Device verification (cannot run in this environment)

After the four tasks, a tester with an R1 or R3 Pro II must confirm: (1) no card binary → boot identical to installed firmware; (2) valid binary → runs on two consecutive reboots; (3) oversized/non-ELF file → one normal boot with a warning; (4) crash-loop simulation → guard disables the override after the fifth rapid boot and card removal restores normal boot. Until these pass, do not claim the feature works on hardware.
