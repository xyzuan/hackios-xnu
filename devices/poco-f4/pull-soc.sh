#!/bin/bash
# Pull the phone's own device tree over adb and turn it into the SoC boot-args HakiOS needs on this
# device (tools/soc-args.py). Unlike the POCO X5 Pro, munch (SM8250 "kona") is a different SoC
# family from the kernel's built-in (SM7325 "yupik") defaults, so its soc.args WILL carry real
# overrides.
#
# /sys/firmware/fdt is 0400 root:root on stock Android 17 — not world-readable. We use
# `su -c "cp ... /sdcard; chmod 644"` (KernelSU/Magisk) then `adb pull` from /sdcard.
# If the phone is older and /sys/firmware/fdt is world-readable, the plain adb pull is tried first.
set -e
cd "$(dirname "$0")/../.."
ADB=${ADB:-adb}
PATH=$PWD/tools/macos-bin/platform-tools:$PATH
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"; $ADB shell "rm -f /sdcard/__fdt" >/dev/null 2>&1' EXIT

# Try plain adb pull first (works on older Android where fdt is world-readable)
if ! $ADB pull /sys/firmware/fdt "$tmp/fdt" >/dev/null 2>&1; then
	# Fall back: copy as root to /sdcard, pull, clean up
	$ADB shell "su -c 'cp /sys/firmware/fdt /sdcard/__fdt && chmod 644 /sdcard/__fdt'" 2>/dev/null || {
		echo "pull-soc.sh: cannot read /sys/firmware/fdt (needs root: install KernelSU/Magisk)"; exit 1; }
	$ADB pull /sdcard/__fdt "$tmp/fdt" >/dev/null 2>&1 || { echo "pull-soc.sh: adb pull failed"; exit 1; }
fi

# Validate it's a real FDT (magic 0xd00dfeed)
python3 - "$tmp/fdt" <<'PY' || { echo "pull-soc.sh: not a valid FDT"; exit 1; }
import struct, sys
with open(sys.argv[1], 'rb') as f:
    magic = f.read(4)
if magic != b'\xd0\x0d\xfe\xed':
    sys.exit('pull-soc.sh: bad FDT magic (got %r)' % magic)
PY

tools/soc-args.py "$tmp/fdt" | tee "$(dirname "$0")/soc.args"
echo "pull-soc.sh: wrote $(dirname "$0")/soc.args ($(wc -l < "$(dirname "$0")/soc.args") lines)"
