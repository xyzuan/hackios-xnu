#!/bin/bash
# Pull the phone's own firmware out of its Android into the fw-*/ directories at the top of the
# repository (never committed: it is the vendor's). The phone is on adb, in Android.
#
# POCO F4 (munch, SM8250 "kona"). The firmware set differs from redwood (SM7325 "yupik") in
# several SoC-family ways; see devices/poco-f4/README.md:
#   - GPU: Adreno 650 (a650_*), not 642L (a660_*)
#   - Haptic: AW8697 (same chip as redwood — aw8697_haptic.bin)
#   - Audio codec: NXP TFA9894 (tfa98xx.cnt), not Awinic AW88263s
#   - IPA: ipa_fws.* + ipa_uc.* in /vendor/firmware (not via the modem)
#   - Wi-Fi: WCN6855 on PCIe (wlan/qca_cld/ has only config + MAC; the firmware is loaded at runtime,
#     not a pullable file — see fw-wifi note below)
#   - Modem: SPLIT layout — /vendor/firmware_mnt/image/modem_pr/{so,mcfg}/, NOT a monolithic
#     modem.mdt + modem.b00..b29 set. This is the SM8250 split-modem architecture; hakios.mpss.c
#     (written for redwood's monolithic modem) will need rework for this layout.
#   - Audio DSP: adsp.* with 19 segments (b00..b18), not redwood's 36
#   - Cameras: IMX582/OV64B40 (wide), OV8856 (ultra), GC02M1 (macro), IMX596 (front) — see fw-camera/
#
# /vendor/firmware/ is world-readable (0644) -> plain adb pull works.
# /vendor/firmware_mnt/image/ is 0640 system:system -> needs root (KernelSU/Magisk). We use
# `su -c "cp ... /sdcard/; chmod 644 ..."` then `adb pull` from /sdcard for those.
# No 'set -e': each pull reports its own failure and the script continues, so one missing
# file (e.g. on a different ROM) doesn't abort the rest.
cd "$(dirname "$0")/../.."
ADB=${ADB:-adb}

# A pull that falls back to su-cp-then-pull when the file is not world-readable.
#   pull DIR REMOTE_PATH...
pull() { # DIR REMOTE_PATH...  (missing files are told, not fatal)
	local dir=$1; shift
	mkdir -p "$dir"
	for f in "$@"; do
		if $ADB pull "$f" "$dir/" >/dev/null 2>&1; then
			:
		else
			# not world-readable: copy to /sdcard as root, pull, clean up
			local name=$(basename "$f")
			if $ADB shell "su -c 'cp \"$f\" /sdcard/__pull && chmod 644 /sdcard/__pull'" 2>/dev/null && \
			   $ADB pull /sdcard/__pull "$dir/$name" >/dev/null 2>&1; then
				$ADB shell "rm -f /sdcard/__pull" >/dev/null 2>&1
			else
				echo "pull-firmware.sh: $f: not on the phone or no root"
				$ADB shell "rm -f /sdcard/__pull" >/dev/null 2>&1
			fi
		fi
	done
	echo "pull-firmware.sh: $dir: $(ls -1 "$dir" 2>/dev/null | wc -l | tr -d ' ') files"
}

# Pull a whole remote directory recursively (for the split modem's so/ and mcfg/ trees).
#   pull_tree DIR REMOTE_DIR
pull_tree() {
	local dir=$1 remote=$2
	mkdir -p "$dir"
	# tar the remote dir as root, pull the tarball, extract locally.
	# tar preserves the remote dir's mode bits (often dr-xr-x---), so chmod u+w
	# after extract or we can't even clean up the tarball locally.
	if $ADB shell "su -c 'cd \"$remote\" && tar cf - .'" 2>/dev/null > "$dir/.tree.tar" && [ -s "$dir/.tree.tar" ]; then
		( cd "$dir" && tar xf .tree.tar 2>/dev/null )
		chmod -R u+w "$dir" 2>/dev/null
		rm -f "$dir/.tree.tar" 2>/dev/null
		echo "pull-firmware.sh: $dir: $(find "$dir" -type f | wc -l | tr -d ' ') files (from $remote)"
	else
		echo "pull-firmware.sh: $remote: could not pull (no root?)"
		rm -f "$dir/.tree.tar" 2>/dev/null
	fi
}

$ADB get-state >/dev/null

# GPU: Adreno 650. /vendor/firmware/, world-readable.
pull fw-gpu \
	/vendor/firmware/a650_gmu.bin \
	/vendor/firmware/a650_sqe.fw \
	/vendor/firmware/a650_zap.mdt /vendor/firmware/a650_zap.b00 /vendor/firmware/a650_zap.b01 /vendor/firmware/a650_zap.b02 /vendor/firmware/a650_zap.elf

# Haptic: AW8697 (same chip as redwood). /vendor/firmware/, world-readable.
pull fw-haptic /vendor/firmware/aw8697_haptic.bin /vendor/firmware/aw8697_rtp_1.bin

# IPA firmware: ipa_fws.* + ipa_uc.* in /vendor/firmware (not via the modem). World-readable.
pull fw-ipa \
	$(for f in mdt elf b00 b01 b02 b03 b04; do echo /vendor/firmware/ipa_fws.$f; done) \
	$(for f in mdt elf b00 b01 b02; do echo /vendor/firmware/ipa_uc.$f; done)

# Audio codec: NXP TFA9894. /vendor/firmware/, world-readable.
# (redwood's Awinic AW88263s amplifiers are driven by the audio DSP; munch's TFA9894 has its own
# firmware file. The audio DSP firmware is below.)
pull fw-audio-codec /vendor/firmware/tfa98xx.cnt

# Audio DSP (ADSP): /vendor/firmware_mnt/image/, 0640 -> needs root. 19 segments (b00..b18) + mdt.
pull fw-audio \
	/vendor/firmware_mnt/image/adsp.mdt \
	$(for i in $(seq 0 18); do printf '/vendor/firmware_mnt/image/adsp.b%02d ' $i; done)

# Modem: SPLIT layout (SM8250). /vendor/firmware_mnt/image/modem_pr/{so,mcfg}/.
# NOT a monolithic modem.mdt set. Pull the whole tree as a tarball.
# hakios.mpss.c (redwood, monolithic) will need rework for this split layout.
mkdir -p fw-modem
pull_tree fw-modem/so      /vendor/firmware_mnt/image/modem_pr/so
pull_tree fw-modem/mcfg    /vendor/firmware_mnt/image/modem_pr/mcfg

# Wi-Fi: WCN6855 on PCIe. /vendor/firmware/wlan/qca_cld/ has only symlinks (WCNSS_qcom_cfg.ini,
# wlan_mac.bin). The actual firmware is loaded by the WLAN driver at runtime over PCIe, not a
# pullable file. So fw-wifi/ gets the config + MAC only; the firmware itself is the driver's job.
mkdir -p fw-wifi
pull fw-wifi /vendor/etc/wifi/WCNSS_qcom_cfg.ini
# wlan_mac.bin is at /mnt/vendor/persist/wlan_mac.bin (the symlink target); needs root.
$ADB shell "su -c 'cp /mnt/vendor/persist/wlan_mac.bin /sdcard/__mac && chmod 644 /sdcard/__mac'" 2>/dev/null && \
	$ADB pull /sdcard/__mac fw-wifi/wlan_mac.bin >/dev/null 2>&1 && \
	$ADB shell "rm -f /sdcard/__mac" >/dev/null 2>&1
echo "pull-firmware.sh: fw-wifi: $(ls -1 fw-wifi 2>/dev/null | wc -l | tr -d ' ') files (config + MAC; firmware loaded at runtime by WCN6855 driver)"

# Cameras: munch sensors. /vendor/lib64/camera/, the files are .bin (sensormodule + tuned).
# Sensors: IMX582 (wide, ofilm) / OV64B40 (wide, sunny) / OV8856 (ultra, aac) /
#          GC02M1 (macro, ofilm/sunny) / IMX596 (front, ofilm/sunny).
pull fw-camera \
	$(for n in aac_ov8856_ultra ofilm_gc02m1_macro ofilm_imx582_wide ofilm_imx596_front \
	           sunny_gc02m1_macro sunny_imx596_front sunny_ov64b40_wide sunny_ov8856_ultra; do
		echo /vendor/lib64/camera/com.qti.sensormodule.munch_$n.bin
		echo /vendor/lib64/camera/com.qti.tuned.munch_$n.bin
	done) \
	/vendor/firmware/CAMERA_ICP.elf

# The modem's own files (TFTP, etc.) — the whole firmware_mnt/image tree, in case the kernel
# driver needs more than modem_pr/. Optional; large. Skip by default, enable with FW_FULL=1.
if [ "${FW_FULL:-0}" = 1 ]; then
	mkdir -p fw-modem/image
	pull_tree fw-modem/image /vendor/firmware_mnt/image
fi

echo "pull-firmware.sh: done."
echo "  Wi-Fi also wants fw-wifi/network (the network's name and passphrase) for the kernel to join."
echo "  Modem firmware is the SPLIT layout (modem_pr/so/*.mbn + mcfg/), not redwood's monolithic"
echo "  modem.mdt set — hakios.mpss.c will need rework for this (see devices/poco-f4/README.md)."
