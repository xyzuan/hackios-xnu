#!/bin/bash
# Pull the phone's own device tree over adb and turn it into the SoC boot-args HakiOS needs on this
# device (tools/soc-args.py). Unlike the POCO X5 Pro, munch (SM8250 "kona") is a different SoC
# family from the kernel's built-in (SM7325 "yupik") defaults, so its soc.args WILL carry real
# overrides. Needs the phone in Android with adb (root not required: /sys/firmware/fdt is
# world-readable).
set -e
cd "$(dirname "$0")/../.."
PATH=$PWD/tools/macos-bin/platform-tools:$PATH
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
adb pull /sys/firmware/fdt "$tmp/fdt" >/dev/null || { echo "pull-soc.sh: cannot read /sys/firmware/fdt over adb"; exit 1; }
tools/soc-args.py "$tmp/fdt" | tee "$(dirname "$0")/soc.args"
echo "pull-soc.sh: wrote $(dirname "$0")/soc.args"
