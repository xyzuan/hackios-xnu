#!/bin/bash
# Refresh prebuilt/ from what is built in this tree: the kernel, the loader, our user-space programs
# and the pieces of the phone's UEFI. With them somebody without the cross toolchain can still make the
# images and run the system (QEMU or the phone); see README.md.
#
# DEVICE=poco-f4 (default poco-x5-pro): which phone's UEFI pieces to refresh. The codename and UEFI
# package name (Build/<codename>Pkg) are read from devices/$DEVICE/uefi/files/Resources/Configs/*.toml,
# the same source of truth mkxnuimg.py uses.
set -e
cd "$(dirname "$(readlink -f "$0")")/.."
# KERNEL=... to take the kernel from a tree built elsewhere (xnu/apply.sh makes one anywhere)
K=${KERNEL:-xnu-src/xnu-8796.121.2/BUILD/obj/DEVELOPMENT_ARM64_BCM2837/mach.development.bcm2837}
MU=Mu-Silicium
DEVICE=${DEVICE:-poco-x5-pro}
TOML=$(echo devices/$DEVICE/uefi/files/Resources/Configs/*.toml)
[ -f "$TOML" ] || { echo "update-prebuilt.sh: no UEFI config toml for device $DEVICE"; exit 1; }
CODE=$(basename "$TOML" .toml)
PKG=${CODE}Pkg
mkdir -p prebuilt/userland devices/$DEVICE/prebuilt
cp $K prebuilt/mach.development.bcm2837
[ -f xnuloader/loader.efi ] && cp xnuloader/loader.efi prebuilt/loader.efi || echo "update-prebuilt.sh: no xnuloader/loader.efi here (lld-link); prebuilt/loader.efi kept"
cp userland/hello prebuilt/userland/
for f in init child stage0 hello_dyn svc_test surf_test rwtouch mg_test cpu_test sound_test libhakios.dylib libhakios.sb.dylib \
	libhakios.media.dylib libhakios.app.dylib libhakios.tweaks.dylib HakiosAudio net_test; do
	cp userland/obj/$f prebuilt/userland/
done
if [ -f $MU/Build/$PKG/RELEASE_CLANGPDB/FV/SILICIUM_UEFI.fd ]; then
	cp $MU/Build/$PKG/RELEASE_CLANGPDB/FV/SILICIUM_UEFI.fd $MU/BootShim/BootShim.bin $MU/Resources/DTBs/$CODE.dtb \
		$MU/Resources/ramdisk $MU/Resources/Scripts/mkbootimg.py devices/$DEVICE/prebuilt/
else
	echo "update-prebuilt.sh: no $PKG build in $MU (device $DEVICE); prebuilt UEFI pieces kept"
fi
{
	echo "Built $(date '+%Y-%m-%d %H:%M') from this tree (device $DEVICE, $PKG)."
	echo
	sha256sum prebuilt/mach.development.bcm2837 prebuilt/loader.efi prebuilt/userland/* devices/$DEVICE/prebuilt/* 2>/dev/null
} > prebuilt/SHA256SUMS
ls -la prebuilt prebuilt/userland devices/$DEVICE/prebuilt
