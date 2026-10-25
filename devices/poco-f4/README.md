# Device: POCO F4 (munch) — SCAFFOLD, for testing

> **Status: scaffold.** This directory is a port of the `poco-x5-pro` (redwood) device layout to
> the POCO F4 (munch), modelled on Mu-Silicium's `aliothPkg` (POCO F3 — the same SM8250 "kona" SoC).
> It is a starting point to test the UEFI side on this phone. The kernel drivers are **not** yet
> adapted to this SoC family; see "What is not done" below.

Everything in HakiOS that belongs to one phone is here. The kernel, loader and user space above
know nothing about the phone: addresses, interrupts, power rails and firmware come from its device
tree and its Android. A port to another Qualcomm phone is another directory like this one.

| What | Where |
|---|---|
| SoC | Qualcomm Snapdragon 870 (SM8250, "kona" in Mu-Silicium; "yupik"-class driver defaults live in the kernel) |
| UEFI for the phone | `uefi/`: a port of Mu-Silicium, modelled on `aliothPkg` (same SM8250). `apply.sh` clones and applies, `export.sh` saves |
| Prebuilt UEFI images | `prebuilt/`: **empty** in the scaffold — built by `uefi/apply.sh` + `python3 build_uefi.py -d munch`; refreshed here by `tools/update-prebuilt.sh` (see its note below) |
| The phone's firmware | **not in the repository**: `pull-firmware.sh` pulls it off your phone over `adb` into `fw-*/` at the top |
| Tools | `tools/modem_firmware.py` (the modem image by the device tree), `tools/cellular_probe.py` (the modem's nodes in the device tree) — both SoC-agnostic, shared with redwood |

## What is done

- The device directory and the UEFI package (`munchPkg`), renamed from `aliothPkg`, with kona's
  real memory map and configuration map (from alioth) — not redwood's SM7325 values.
- The SoC-agnostic parts carried over from redwood verbatim: the `mu-silicium.patch` (BootShim
  copies the "XNUP" container to `0xF0000000`; `BootManagerLib` starts the XNU loader instead of a
  menu) and `XnuLoader.[ch]`.
- The `XNU Payload` memory region (`0xF0000000`, 64 MB) added to munch's memory map, since the
  BootShim writes there and alioth's map did not reserve it.
- `pull-firmware.sh` and `pull-soc.sh` adapted to munch (the GPU is Adreno 650 → `a650_*`).

## What is not done (the real port)

This is a scaffold. To boot XNU on munch, at least these remain:

- **Kernel drivers.** `xnu/files/bsd/dev/hakios.*.c` carry redwood's (SM7325 / "yupik") chips and
  addresses as defaults. Munch is a different SoC family (SM8250 / "kona"):
  - Adreno **650** (redwood: 642L), different GMU/zap shader and register layout.
  - Wi-Fi **WCN6855** on **PCIe** (redwood: WCN6750 on the WPSS DSP inside the SoC) — a different
    bring-up path; `hakios.wifi.c`/`hakios.lx.c` are written for the WPSS DSP.
  - IPA **4.5** (redwood: 4.11) — different register layout in `hakios.ipa.c`.
  - Different PMICs, audio codec, haptic driver, camera sensors.
  The SoC base addresses (IPA/IPCC/AOSS/RPMh/SMMU) are overridable via `soc.args`
  (`hakios.mpss.c`, `soc_override()`), but the version and chip differences above are real driver
  rewrites — the head of each `hakios.*.c` says where its numbers came from.
- **`Binaries/munch/`** UEFI drivers — extract from the phone's `xbl.img` with
  [UEFIReader](https://github.com/WOA-Project/UEFIReader) (see `uefi/files/Binaries/munch/README.md`).
  For a first bring-up test the SoC-level drivers can be aliased from Mu-Silicium's `Binaries/alioth`
  (same SM8250); the board-specific files (display panels, charger config, battery provision) must
  come from munch's own `xbl.img`.
- **`munch.dtb`** device tree — pull from the phone's `vendor_boot` (see `uefi/files/Resources/DTBs/`).
- **`soc.args`** — regenerate from the phone with `pull-soc.sh`.

The build/run scripts (`mkxnuimg.py`, `tools/update-prebuilt.sh`, `xl`, `tools/modem-cycle.sh`,
the `Makefile`) are **device-aware**: they read the codename, UEFI package name and FD base/size
from `uefi/files/Resources/Configs/munch.toml`, selected by `DEVICE=poco-f4` (default
`poco-x5-pro`, so redwood keeps working).

## Firmware

```sh
devices/poco-f4/pull-firmware.sh      # the phone in Android, on adb
```

Pulls the GPU (`fw-gpu/`), Wi-Fi (`fw-wifi/`), the audio DSP (`fw-audio/`, battery and charging
come through it), the vibration motor (`fw-haptic/`), the modem (`fw-modem/`, with `image/` for its
TFTP) and the cameras (`fw-camera/`). All of it is the vendor's and stays out of git. The chip
identifiers that are not yet known for munch are marked `TODO` in the script; `adb pull` reports
anything it cannot find instead of failing.

## Running

From the top of the repository, see the main README: `./xl enter`, `./xl ramdisk`, `./xl run`,
or everything in one command: `tools/modem-cycle.sh "ARGS" SECS`, or `make phone DEVICE=poco-f4`.
The build/run scripts pick the device from `DEVICE` (default `poco-x5-pro`); `mkxnuimg.py` reads
munch's UEFI FD base/size (`0x9FC00000`/`0x300000`) and codename from
`uefi/files/Resources/Configs/munch.toml`.

## Porting to this phone: the SoC addresses

```sh
devices/poco-f4/pull-soc.sh      # adb pull /sys/firmware/fdt, then tools/soc-args.py -> devices/poco-f4/soc.args
```

`tools/soc-args.py DEVICE-TREE.dtb` reads the `qcom,ipa`, `qcom,ipcc`, the AOSS mailbox, the RPMh
controller and `apps-smmu` nodes and prints `soc_ipa_base`, `soc_gsi_base`, `soc_ipcc`, `soc_aoss`,
`soc_rsc`, `soc_apps_smmu`. The run scripts append `devices/<name>/soc.args` to the kernel command
line automatically (`SOC_ARGS=` to point elsewhere). The memory addresses (`soc_smem`,
`soc_cmd_db`, `soc_mpss_mem`, `soc_imem`) come from the phone's reserved-memory nodes; add them by
hand for now. **`soc.args` is empty in the scaffold** — run `pull-soc.sh` to fill it.
