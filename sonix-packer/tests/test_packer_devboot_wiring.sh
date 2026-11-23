#!/bin/sh
# Host-side wiring tests for the packer's SD dev helper install and launcher
# rewrite. Purely static and awk-level: no flashing, no root, no squashfs tools.
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
PACKER="$ROOT/sonix-packer/sonix_firmware_packer.sh"
LAUNCHER_SRC="$ROOT/sonix-packer/assets/R1/usr/bin/sonix_player.sh"

# Full-line fixtures: the wiring test must match the exact lines the awk emits,
# not a substring that could also appear in a differently formatted line.
DEVBOOT_LINE='[ -x /usr/bin/sonix_devboot.sh ] && exec /usr/bin/sonix_devboot.sh'
PLAYER_LINE='/usr/bin/sonix_player'

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' 0 1 2 3 15

PASS=0
FAILS=0
pass() { printf 'ok   - %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf 'FAIL - %s: %s\n' "$1" "$2"; FAILS=$((FAILS + 1)); }

# --- syntax ----------------------------------------------------------------
ERR="$TMP/syntax.err"
if sh -n "$PACKER" 2>"$ERR"; then
	pass 'packer passes sh -n'
else
	bad 'packer passes sh -n' "$(cat "$ERR")"
fi

# --- static source checks --------------------------------------------------
static_has() {
	if grep -Fq -- "$2" "$PACKER"; then
		pass "$1"
	else
		bad "$1" "missing literal: $2"
	fi
}

static_has 'packer defines DEVBOOT_SH' 'DEVBOOT_SH='
static_has 'packer installs sonix_devboot.sh' \
	'cp -f "$DEVBOOT_SH" "$SQUASH_DIR/usr/bin/sonix_devboot.sh"'
static_has 'packer installs sonix_devboot.sh at mode 755' \
	'chmod 755 "$SQUASH_DIR/usr/bin/sonix_devboot.sh"'
static_has 'packer installs sonix_launch' \
	'cp -f "$LAUNCH_BIN" "$SQUASH_DIR/usr/bin/sonix_launch"'
static_has 'packer installs sonix_launch at mode 755' \
	'chmod 755 "$SQUASH_DIR/usr/bin/sonix_launch"'
static_has 'packer verifies the devboot line' \
	'grep -q "exec /usr/bin/sonix_devboot.sh"'
static_has 'packer has DEVBOT-AWK-BEGIN marker' '# DEVBOT-AWK-BEGIN'
static_has 'packer has DEVBOT-AWK-END marker' '# DEVBOT-AWK-END'

# --- build a standalone rewrite script from the marked awk block -----------
# The extracted block is the awk invocation; the harness supplies LAUNCHER_FILE
# and relies on the block writing to "$LAUNCHER_FILE.new", as the packer does.
REWRITE="$TMP/rewrite.sh"
{
	printf 'LAUNCHER_FILE="$1"\n'
	sed -n '/# DEVBOT-AWK-BEGIN/,/# DEVBOT-AWK-END/p' "$PACKER" |
		sed '/# DEVBOT-AWK-BEGIN/d; /# DEVBOT-AWK-END/d'
} > "$REWRITE"
chmod 755 "$REWRITE"

# --- run the extracted awk on a copy of the R1 launcher --------------------
LAUNCHER="$TMP/launcher.sh"
cp "$LAUNCHER_SRC" "$LAUNCHER"

if sh "$REWRITE" "$LAUNCHER" 2>"$TMP/rewrite.err"; then
	pass 'extracted awk runs on a launcher copy'
else
	bad 'extracted awk runs on a launcher copy' "$(cat "$TMP/rewrite.err")"
fi

OUT="$LAUNCHER.new"
if [ -f "$OUT" ]; then
	pass 'extracted awk writes $LAUNCHER_FILE.new'
else
	bad 'extracted awk writes $LAUNCHER_FILE.new' 'no output file produced'
fi

count_exact() {
	[ -f "$2" ] || { printf '0\n'; return; }
	grep -Fxc -- "$1" "$2" 2>/dev/null || true
}

expect_count() {
	if [ "$3" = "$2" ]; then
		pass "$1"
	else
		bad "$1" "expected $2, got $3"
	fi
}

dev_count=$(count_exact "$DEVBOOT_LINE" "$OUT")
expect_count 'exactly one devboot exec line' 1 "$dev_count"

# The awk injects only the devboot line: sonix_launch is supervised inside
# devboot, so no launcher exec line for it belongs in this rewrite.
launch_count=$(grep -Fc -- 'exec /usr/bin/sonix_launch' "$OUT" 2>/dev/null || true)
expect_count 'awk injects no sonix_launch exec line' 0 "$launch_count"

player_count=$(count_exact "$PLAYER_LINE" "$OUT")
expect_count 'original /usr/bin/sonix_player line retained' 1 "$player_count"

# Line order: devboot exec, then the untouched original player line.
dev_line=$(grep -nFx -- "$DEVBOOT_LINE" "$OUT" 2>/dev/null | head -1 | cut -d: -f1)
player_line=$(grep -nFx -- "$PLAYER_LINE" "$OUT" 2>/dev/null | head -1 | cut -d: -f1)

if [ -n "$dev_line" ] && [ -n "$player_line" ] && \
	[ "$dev_line" -lt "$player_line" ]; then
	pass 'devboot exec line appears above the retained player line'
else
	bad 'devboot exec line appears above the retained player line' \
		"devboot=$dev_line player=$player_line"
fi

# --- idempotency: run the same extracted awk on its own output -------------
LAUNCHER2="$TMP/launcher2.sh"
cp "$OUT" "$LAUNCHER2" 2>/dev/null || : > "$LAUNCHER2"
if sh "$REWRITE" "$LAUNCHER2" 2>"$TMP/rewrite2.err"; then
	pass 'extracted awk reruns on its own output'
else
	bad 'extracted awk reruns on its own output' "$(cat "$TMP/rewrite2.err")"
fi

OUT2="$LAUNCHER2.new"
dev_count2=$(count_exact "$DEVBOOT_LINE" "$OUT2")
expect_count 'idempotent: still exactly one devboot exec line' 1 "$dev_count2"
player_count2=$(count_exact "$PLAYER_LINE" "$OUT2")
expect_count 'idempotent: player line still retained once' 1 "$player_count2"

if [ -f "$OUT2" ] && cmp -s "$OUT" "$OUT2"; then
	pass 'idempotent: second output is byte-identical'
else
	bad 'idempotent: second output is byte-identical' 'outputs differ'
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAILS"
[ "$FAILS" -eq 0 ]
