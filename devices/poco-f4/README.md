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
- `pull-firmware.sh` and `pull-soc.sh` adapted to munch and **run against the phone** (Android 17,
  KernelSU root). The firmware set and `soc.args` are now real, not placeholders — see "Firmware"
  and "SoC addresses" below.

## What is not done (the real port)

This is a scaffold with the UEFI side + firmware/SoC data filled in. To boot XNU on munch, the
kernel drivers remain:

- **Kernel drivers.** `xnu/files/bsd/dev/hakios.*.c` carry redwood's (SM7325 / "yupik") chips and
  addresses as defaults. Munch is a different SoC family (SM8250 / "kona"). The SoC base addresses
  (IPA/IPCC/AOSS/RPMh/SMMU/SMEM/IMEM) are **identical to redwood's** (see `soc.args`) and need no
  override, but the chip and architecture differences below are real driver rewrites — the head of
  each `hakios.*.c` says where its numbers came from:
  - **Adreno 650** (redwood: 642L) — different GMU/zap shader and register layout (`hakios.adreno.c`).
    Firmware: `a650_gmu.bin`, `a650_sqe.fw`, `a650_zap.{mdt,b00,b01,b02,elf}` (in `fw-gpu/`).
  - **Wi-Fi WCN6855 on PCIe** (redwood: WCN6750 on the WPSS DSP inside the SoC) — a different
    bring-up path; `hakios.wifi.c`/`hakios.lx.c` are written for the WPSS DSP. The firmware is
    loaded by the WLAN driver at runtime over PCIe, not a pullable file (`fw-wifi/` has only
    `WCNSS_qcom_cfg.ini` + `wlan_mac.bin`).
  - **IPA 4.5** (redwood: 4.11) — different register layout in `hakios.ipa.c`. Firmware:
    `ipa_fws.*` + `ipa_uc.*` in `fw-ipa/` (in `/vendor/firmware`, not via the modem).
  - **Modem: SPLIT layout** (redwood: monolithic). Munch's modem is an **external SDX55 on PCIe**,
    not an integrated MPSS loaded by the AP via TrustZone. The firmware is `/vendor/firmware_mnt/
    image/modem_pr/{so,mcfg}/` — `so/*.mbn` (split PIE shared objects, ~25 files) + `mcfg/configs/`
    (carrier configs, ~275 files). There is **no `modem.mdt`**, **no `mpss` reserved-memory
    node**, and **no `qcom,mss`/`qcom,pas` node** on this phone. `hakios.mpss.c` (written for
    redwood's integrated MPSS) needs a **new driver** (PCIe + split-`.so` + QMI-over-PCIe), not a
    port. See `MODEM-ARCHITECTURE.md` for the full analysis.
  - **Audio codec: NXP TFA9894** (`tfa98xx.cnt`, redwood: Awinic AW88263s) — different amplifier
    family. Audio DSP firmware: `adsp.{mdt,b00..b18}` (19 segments; redwood has 36) in `fw-audio/`.
  - **Haptic: AW8697** — same chip as redwood (`aw8697_haptic.bin` + `aw8697_rtp_1.bin` in
    `fw-haptic/`), so `hakios.haptic.c` likely needs no change.
  - **Cameras** (redwood: OV02B10 macro, S5KHM2SD wide): munch has Sony **IMX582** (wide, ofilm) /
    OmniVision **OV64B40** (wide, sunny) / **OV8856** (ultra, aac) / **GC02M1** (macro) / **IMX596**
    (front). `hakios.camera.c` needs rewriting for these sensors. Firmware: `com.qti.sensormodule.
    munch_*.bin` + `com.qti.tuned.munch_*.bin` + `CAMERA_ICP.elf` in `fw-camera/`.
- **`Binaries/munch/`** UEFI drivers — extract from the phone's `xbl.img` with
  [UEFIReader](https://github.com/WOA-Project/UEFIReader) (see `uefi/files/Binaries/munch/README.md`).
  For a first bring-up test the SoC-level drivers can be aliased from Mu-Silicium's `Binaries/alioth`
  (same SM8250); the board-specific files (display panels, charger config, battery provision) must
  come from munch's own `xbl.img`.
- **`munch.dtb`** device tree — pull from the phone's `vendor_boot` (see `uefi/files/Resources/DTBs/`).
  (`soc.args` was generated from `/sys/firmware/fdt`, but the full DTB for `mkxnuimg.py` still
  needs to come from `vendor_boot`.)

The build/run scripts (`mkxnuimg.py`, `tools/update-prebuilt.sh`, `xl`, `tools/modem-cycle.sh`,
the `Makefile`) are **device-aware**: they read the codename, UEFI package name and FD base/size
from `uefi/files/Resources/Configs/munch.toml`, selected by `DEVICE=poco-f4` (default
`poco-x5-pro`, so redwood keeps working).

## Firmware

```sh
devices/poco-f4/pull-firmware.sh      # the phone in Android, on adb (KernelSU/Magisk root needed)
```

Pulls into `fw-*/` at the repo top (gitignored, vendor's, never committed):

| Dir | Contents | Source on phone | Notes |
|---|---|---|---|
| `fw-gpu/` | `a650_gmu.bin`, `a650_sqe.fw`, `a650_zap.*` | `/vendor/firmware/` (0644) | Adreno 650 |
| `fw-haptic/` | `aw8697_haptic.bin`, `aw8697_rtp_1.bin` | `/vendor/firmware/` (0644) | AW8697 (same as redwood) |
| `fw-ipa/` | `ipa_fws.*`, `ipa_uc.*` | `/vendor/firmware/` (0644) | IPA 4.5 firmware |
| `fw-audio-codec/` | `tfa98xx.cnt` | `/vendor/firmware/` (0644) | NXP TFA9894 (not Awinic) |
| `fw-audio/` | `adsp.mdt`, `adsp.b00..b18` (19 segs) | `/vendor/firmware_mnt/image/` (0640, needs root) | Audio DSP |
| `fw-modem/so/` | `*.mbn` (~25 files) | `/vendor/firmware_mnt/image/modem_pr/so/` (0640) | **Split modem** — not a monolithic `modem.mdt` |
| `fw-modem/mcfg/` | `mcfg_hw/`, `mcfg_sw/` (~275 files) | `/vendor/firmware_mnt/image/modem_pr/mcfg/` (0640) | Modem carrier configs |
| `fw-wifi/` | `WCNSS_qcom_cfg.ini`, `wlan_mac.bin` | `/vendor/etc/wifi/`, `/mnt/vendor/persist/` | WCN6855 firmware itself is loaded at runtime over PCIe, not a file |
| `fw-camera/` | `com.qti.sensormodule.munch_*.bin`, `com.qti.tuned.munch_*.bin`, `CAMERA_ICP.elf` | `/vendor/lib64/camera/` (0644), `/vendor/firmware/` | IMX582/OV64B40/OV8856/GC02M1/IMX596 |

The script falls back to `su -c "cp ... /sdcard; chmod 644"` + `adb pull` for files that aren't
world-readable (most of `/vendor/firmware_mnt/image/`); needs KernelSU or Magisk.

## Running

From the top of the repository, see the main README: `./xl enter`, `./xl ramdisk`, `./xl run`,
or everything in one command: `tools/modem-cycle.sh "ARGS" SECS`, or `make phone DEVICE=poco-f4`.
The build/run scripts pick the device from `DEVICE` (default `poco-x5-pro`); `mkxnuimg.py` reads
munch's UEFI FD base/size (`0x9FC00000`/`0x300000`) and codename from
`uefi/files/Resources/Configs/munch.toml`.

## Porting to this phone: the SoC addresses

```sh
devices/poco-f4/pull-soc.sh      # adb pull /sys/firmware/fdt (via su), then tools/soc-args.py -> devices/poco-f4/soc.args
```

`tools/soc-args.py DEVICE-TREE.dtb` reads the `qcom,ipa`, `qcom,ipcc`, the AOSS mailbox, the RPMh
controller and `apps-smmu` nodes and prints `soc_ipa_base`, `soc_gsi_base`, `soc_ipcc`, `soc_aoss`,
`soc_rsc`, `soc_apps_smmu`, plus the memory addresses (`soc_smem`, `soc_cmd_db`, `soc_mpss_mem`,
`soc_imem`) from the phone's reserved-memory nodes. The run scripts append `devices/<name>/soc.args`
to the kernel command line automatically (`SOC_ARGS=` to point elsewhere).

**`soc.args` is filled in** (run against the phone). On munch, the addresses `soc-args.py` finds
are **identical to redwood's** (same Qualcomm SoC block layout across SM8250/SM7325). Two are
added by hand because the parser's compatible-string match misses them on kona:
- `soc_aoss=0xc300000` — munch's AOSS node is `qcom,qmp-aop@c300000` (compatible `qcom,sm8250-aoss-qmp`,
  not the `qcom,sm8350-aoss-qmp` the parser looks for). Same address as redwood.
- `soc_cmd_db=0x80860000` — munch's reserved-memory node is `reserved-memory@80860000` (no `cmd_db`
  in the name). Same address as redwood.

**`soc_mpss_mem` is absent on munch** — the SM8250 split-modem architecture has no `mpss`/`mss`
reserved-memory node (the modem memory is managed via the split `modem_pr/so/` layout). This is a
real difference `hakios.mpss.c` must handle; see "What is not done" above.
