#!/usr/bin/env python3
"""
Pack a device's UEFI (with the hook that starts the XNU loader) and an optional payload
into an Android boot image for `fastboot boot`.

  kernel = gzip(BootShim + UEFI FD + ["XNUP" container]) + DTB

The boot shim copies the FD to its base and the payload to PAYLOAD_BASE.

The UEFI pieces are taken from a Mu-Silicium tree built here (Mu-Silicium/, see
devices/<device>/uefi/README.md) or, when there is none, from devices/<device>/prebuilt/.

Which device: --device (or the DEVICE env, default poco-x5-pro). The device's codename,
UEFI package name (Build/<codename>Pkg), FD base/size and DTB name are read from its UEFI
config toml at devices/<device>/uefi/files/Resources/Configs/<codename>.toml — that file is
the single source of truth the build and the run scripts share.

usage: mkxnuimg.py [-d device] [-p payload.bin] [-o out.img] [--mode RELEASE]
"""
import argparse, glob, gzip, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
MU = os.path.join(HERE, 'Mu-Silicium')
PAYLOAD_BASE, PAYLOAD_MAX = 0xF0000000, 0x04000000   # XnuLoader.h: same for every device


def device_config(device):
    """Return (codename, fd_base, fd_size) for a device from its UEFI config toml."""
    tomls = glob.glob(os.path.join(HERE, 'devices', device, 'uefi', 'files', 'Resources', 'Configs', '*.toml'))
    if not tomls:
        sys.exit(f'mkxnuimg.py: no UEFI config toml found under devices/{device}/uefi/files/Resources/Configs/')
    path = tomls[0]
    codename = os.path.splitext(os.path.basename(path))[0]
    base = size = None
    try:
        import tomllib
        with open(path, 'rb') as f:
            cfg = tomllib.load(f)
        base, size = cfg['uefi_fd']['base'], cfg['uefi_fd']['size']
    except ImportError:
        pass
    if base is None:                                   # fallback: parse the two lines ourselves
        import re
        txt = open(path).read()
        m = re.search(r'^\s*base\s*=\s*(0x[0-9a-fA-F]+)', txt, re.M)
        n = re.search(r'^\s*size\s*=\s*(0x[0-9a-fA-F]+)', txt, re.M)
        if not m or not n:
            sys.exit(f'mkxnuimg.py: cannot read [uefi_fd] base/size from {path}')
        base, size = int(m.group(1), 16), int(n.group(1), 16)
    return codename, base, size


ap = argparse.ArgumentParser()
ap.add_argument('-d', '--device', default=os.environ.get('DEVICE', 'poco-x5-pro'),
                help='device directory under devices/ (default: $DEVICE or poco-x5-pro)')
ap.add_argument('-p', '--payload')
ap.add_argument('-o', '--output')
ap.add_argument('--mode', default='RELEASE')
args = ap.parse_args()

codename, FD_BASE, FD_SIZE = device_config(args.device)
PKG = codename + 'Pkg'
PREBUILT = os.path.join(HERE, 'devices', args.device, 'prebuilt')
if args.output is None:
    args.output = os.path.join(HERE, f'xnu-{codename}.img')

fd_path = os.path.join(MU, f'Build/{PKG}/{args.mode}_CLANGPDB/FV/SILICIUM_UEFI.fd')
if os.path.isfile(fd_path):
    shim_dir = os.path.join(MU, 'BootShim')
    for f in ('BootShim.elf', 'BootShim.bin'):
        try: os.unlink(os.path.join(shim_dir, f))
        except FileNotFoundError: pass
    subprocess.check_call(['make', 'REQUIRES_KERNEL_HEADER=1', f'FD_BASE={FD_BASE:#x}', f'FD_SIZE={FD_SIZE:#x}',
                           f'CFLAGS=--target=aarch64-linux-gnu -DPAYLOAD_BASE={PAYLOAD_BASE:#x}'],
                          cwd=shim_dir, stdout=subprocess.DEVNULL)
    parts = {'shim': os.path.join(shim_dir, 'BootShim.bin'), 'fd': fd_path,
             'dtb': os.path.join(MU, 'Resources/DTBs', f'{codename}.dtb'), 'ramdisk': os.path.join(MU, 'Resources/ramdisk'),
             'mkbootimg': os.path.join(MU, 'Resources/Scripts/mkbootimg.py')}
else:
    parts = {'shim': os.path.join(PREBUILT, 'BootShim.bin'), 'fd': os.path.join(PREBUILT, 'SILICIUM_UEFI.fd'),
             'dtb': os.path.join(PREBUILT, 'device-tree.dtb'), 'ramdisk': os.path.join(PREBUILT, 'ramdisk'),
             'mkbootimg': os.path.join(PREBUILT, 'mkbootimg.py')}
shim = open(parts['shim'], 'rb').read()
fd = open(parts['fd'], 'rb').read()
assert len(fd) == FD_SIZE, hex(len(fd))

blob = shim + fd
if args.payload:
    data = open(args.payload, 'rb').read()
    # the payload file is a complete "XNUP" container (see xnuloader/mkpayload.py)
    assert data[:4] == b'XNUP' and len(data) <= PAYLOAD_MAX - 0x1000, 'bad or oversized payload'
    blob += data
    blob += b'\0' * (-len(blob) % 16)
    print(f'payload: {len(data)} bytes, bytesum={sum(data) & 0xffffffff:08x}')

dtb = open(parts['dtb'], 'rb').read()
kernel = args.output + '.kernel~'
open(kernel, 'wb').write(gzip.compress(blob, 6) + dtb)
try:
    subprocess.check_call([sys.executable, parts['mkbootimg'], '--kernel', kernel, '--ramdisk', parts['ramdisk'],
                           '--header_version', '1', '-o', args.output])
finally:
    os.unlink(kernel)
print(f'{args.output}: {os.path.getsize(args.output)} bytes (device={args.device} codename={codename}, '
      f'shim {len(shim)}, uncompressed {len(blob)})')
