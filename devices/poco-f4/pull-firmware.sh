#!/bin/bash
# Pull the phone's own firmware out of its Android into the fw-*/ directories at the top of the
# repository (never committed: it is the vendor's). The phone is on adb, in Android.
#
# SCAFFOLD NOTE: only the GPU (Adreno 650) is filled in for sure. Munch's Wi-Fi (WCN6855, on PCIe),
# audio codec, haptic driver and camera sensors differ from redwood and their exact firmware paths
# need the device tree; the TODO sections below are placeholders. adb pull reports anything it
# cannot find instead of failing, so the script is safe to run as-is and will say what is missing.
set -e
cd "$(dirname "$0")/../.."
pull() { # DIR SOURCE...  (missing files are told, not fatal)
	local dir=$1; shift
	mkdir -p "$dir"
	for f in "$@"; do adb pull "$f" "$dir/" >/dev/null 2>&1 || echo "pull-firmware.sh: $f: not on the phone"; done
	echo "pull-firmware.sh: $dir: $(ls -1 "$dir" | wc -l | tr -d ' ') files"
}
adb get-state >/dev/null
# Adreno 650 (SM8250). TODO: verify zap segment count (redwood's a660 has b00..b02).
pull fw-gpu /vendor/firmware/a650_gmu.bin /vendor/firmware/a650_sqe.fw /vendor/firmware/a650_zap.mdt /vendor/firmware/a650_zap.b00 /vendor/firmware/a650_zap.b01 /vendor/firmware/a650_zap.b02
# TODO(munch): Wi-Fi is WCN6855 on PCIe (not the WPSS DSP redwood uses). Firmware name/layout
# differs from redwood's wpss.*; fill in once the device tree / vendor firmware is checked.
# pull fw-wifi /vendor/firmware/<wcn6855 ...>
# TODO(munch): audio DSP firmware (adsp.*) — paths likely /vendor/firmware_mnt/image/adsp.* as on
# redwood, but the codec and segment count differ.
# pull fw-audio /vendor/firmware_mnt/image/adsp.mdt $(for i in $(seq -w 2 36); do echo /vendor/firmware_mnt/image/adsp.b$i; done)
# TODO(munch): haptic motor driver — munch's haptic chip differs from redwood's AW8697.
# pull fw-haptic /vendor/firmware/<haptic ...>
# Modem (MPSS, MDT format). Same path convention as redwood; segment count may differ.
pull fw-modem /vendor/firmware_mnt/image/modem.mdt $(for i in $(seq -w 0 28); do echo /vendor/firmware_mnt/image/modem.b$i; done)
mkdir -p fw-modem/image && adb pull /vendor/firmware_mnt/image fw-modem/ >/dev/null 2>&1 && echo "pull-firmware.sh: fw-modem/image: the modem's own files (TFTP)"
# TODO(munch): camera sensor module files — munch's sensors differ from redwood's.
# pull fw-camera $(adb shell ls /vendor/lib64/camera/com.qti.sensormodule.hakios_*.bin /vendor/lib64/camera/com.qti.tuned.hakios_*.bin 2>/dev/null | tr -d '\r')
echo "pull-firmware.sh: done; Wi-Fi also wants fw-wifi/mac (the radio's address) and fw-wifi/network (the network's name and passphrase)"
