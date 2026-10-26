# Munch modem architecture (reverse-engineered from the pulled firmware + device tree)

> Findings from analyzing the firmware pulled by `pull-firmware.sh` and the live device tree
> (`/sys/firmware/fdt` + `/proc/device-tree`), with `file`/`readelf` on the `.mbn` files.
> This documents **what `hakios.mpss.c` must change** for the POCO F4, which is the largest
> single piece of the kernel port.

## The headline

**Munch's modem is an external SDX55 connected over PCIe, not an integrated MPSS loaded by the
AP via TrustZone.** This is a different modem architecture from redwood, not just a different
firmware format. `hakios.mpss.c`'s entire loading path does not apply.

## The evidence

### 1. The device tree has no integrated-MPSS node

Redwood's `hakios.mpss.c` expects (from its header comment):
- `qcom,mss@4080000` — the modem's PIL/remoteproc node
- `qcom,pas-id` = 4 — the TrustZone Peripheral Authentication Service image id
- `qcom,smp2p-modem`, `qcom,glink/modem` — the SoC-internal transports
- `reserved-memory mpss@8b800000` (246 MB) — the modem's memory, which the AP loads into

**Munch has none of these.** `find`/`grep` over `/proc/device-tree` for `*mss*`, `*remoteproc*`,
`*pas*`, `qcom,mpss`, `qcom,pas`, `qcom,mss`, `qcom,remoteproc` returns nothing. The
`reserved-memory/` listing has no `mpss`/`mss`/`pil_modem`/`pil_mss` region.

What munch *does* have:
- `qcom,pcie@1c00000`, `qcom,pcie@1c08000`, `qcom,pcie@1c10000` — three PCIe controllers
- `ad-hoc-bus/slv-qns-pcie-modem-mem-noc`, `mas-xm-pcie3-modem`, `slv-xs-pcie-modem` —
  the interconnect paths naming the modem as a PCIe endpoint on pcie3

The modem is on PCIe. The AP does not load it; the modem boots itself.

### 2. The firmware is split PIE shared objects, not a monolithic MDT

Redwood: `modem.mdt` (ELF32 header + signed hash block) + `modem.b00..b29` (the segment blobs,
85 MB total). One signed image, fixed addresses, loaded verbatim into `mpss@8b800000`.

Munch: `/vendor/firmware_mnt/image/modem_pr/so/*.mbn` — **~25 ELF32 Hexagon shared objects**
(`ET_DYN`, `QUALCOMM DSP6`, position-independent), each signed independently, plus
`modem_pr/mcfg/configs/` (~275 carrier-config files).

```
$ file fw-modem/so/544_0_5.mbn
ELF 32-bit LSB shared object, QUALCOMM DSP6, version 1 (SYSV), dynamically linked, no section header

$ readelf -l fw-modem/so/544_0_5.mbn
Elf file type is DYN (Shared object file)
Entry point 0x0
  Type           Offset   VirtAddr   PhysAddr   FileSiz MemSiz  Flg Align
  NULL           0x000000 0x00000000 0x00000000 0x000d4 0x00000     0   <- signature/hash
  NULL           0x001000 0x00147000 0x00147000 0x01a98 0x02000     0   <- hash table
  LOAD           0x003000 0x00000000 0x00000000 0x18902 0x18902 R E     <- code (PIE)
  LOAD           0x01c000 0x00019000 0x00019000 0x12dfa8 0x12dfd0 RW   <- data (PIE)
  DYNAMIC        0x01c000 0x00019000 0x00019000 0x00080 0x00080 RW     <- dynamic relocations
```

Every `.mbn` has the same 5-header structure: two `NULL` (Qualcomm's signed-image wrapper —
signature + hash), two `LOAD` (code + data, both PIE), one `DYNAMIC` (relocations). The
`DYNAMIC` section has `RELACOUNT`, `PLTRELSZ`, `RELA` — these are **relocated at load time**,
not pre-linked to fixed addresses. This is the "split modem" / "shared-object modem"
architecture.

The filename numbering is the **image/PD (protection domain) id**:
- `544_0_5.mbn` (1.3 MB) — the modem's main PD (contains `rfc_hwid544`)
- `595_0_0.mbn`, `596_0_0.mbn` (366 KB / 837 KB) — RF / transceiver PDs
- `704_0_0.mbn`, `705_0_0.mbn`, `709_0_0.mbn`, `710_0_0.mbn` (~1.2 MB each) — likely the
  network-stack PDs (NAS/WDS/QMI services)
- `574_0`, `578_0`, `600_0`, `811_0`, `840_0`, `841_0` (26-32 KB each) — small support PDs

### 3. The mcfg configs are ELF-wrapped carrier data

`modem_pr/mcfg/configs/mcfg_hw/.../mcfg_hw.mbn` and `.../mcfg_sw/.../mcfg_sw.mbn` are also
ELF32 files (`\177ELF\001\001\001`, `Machine: None`, statically linked) — the carrier
configuration wrapped in an ELF container. The tree is organised by modem platform
(`generic/common/SDX55/`) and carrier (`Russia/MTS/`, `Russia/MegaFon/`, …), split into
`mcfg_hw` (hardware config: RF calibration, bands) and `mcfg_sw` (software config: APN,
carrier policies). Munch's modem platform is **SDX55** — the Snapdragon X55 5G modem, which
is what the SM8250/SD870 family integrates.

## What `hakios.mpss.c` does for redwood (the path that does NOT apply to munch)

Steps 2-7 of `hakios.mpss.c` (from its header comment), with what each assumes:

| Step | What it does | Redwood assumption | Munch reality |
|---|---|---|---|
| 2 | Read `fw/modem.mdt`, parse ELF program headers, check segments fit `mpss@8b800000` | One MDT file, fixed-address segments | Many PIE `.so` files, relocatable, no `mpss` region |
| 3 | Open the always-on processor's mailbox | AOP/RPMh path for modem rails | No AP-side rail control (modem is external) |
| 4 | Ask TrustZone to take the image header (`pas-id` 4) and where it'll go | `qcom,pas-id` node present | No `pas-id` node; modem self-authenticates |
| 5 | Copy segment blobs to the modem's reserved memory | AP owns `mpss@8b800000` | No AP-side modem memory |
| 6 | Ask TrustZone to authenticate+start (`pas-id` 4) | TrustZone PIL | Modem boots itself |
| 7 | SMP2P "up" handshake, GLINK channels, QRTR on IPCRTR | SoC-internal transports | PCIe + QMI-over-PCIe |

Only step 1 (read the shared-memory partition state) and the post-load conversation
(QMI NAS/DMS queries) have analogues on munch; the loading itself is gone.

## What the munch port needs

This is a new driver, not a port of `hakios.mpss.c`. Sketch of the pieces:

1. **PCIe bring-up for the modem endpoint.** One of `qcom,pcie@1c00000/1c08000/1c10000` hosts
   the modem; the device tree's `pcie-modem` bus paths name pcie3. The AP's PCIe controller
   driver must bring the link up and enumerate the modem endpoint (vendor/device id TBD —
   read from the endpoint config space once the link is up). This is closer to a laptop's
   M.2-cellular bring-up than to redwood's integrated-DSP bring-up.

2. **Firmware push (or pull).** Two models, needs runtime confirmation:
   - The AP pushes the `.so` + `mcfg` files to the modem over PCIe (a QMI "load image"
     message, like Quectel's `QMI_WDA`/Firmware Update service), or
   - The modem pulls them from the AP's storage (the modem runs TFTP against an AP-side
     server, the way redwood's `hakios.mpss.c` already serves `rmtfs`/`tftp` — see
     `xnu/files/bsd/dev/hakios.mpss.c` around line 3521, "the modem opens a file by path").
   Redwood's TFTP server may already cover this; the question is which files the modem
   asks for and in what order.

3. **QMI-over-PCIe transport** replacing SMP2P + GLINK + QRTR. The modem's QMI services
   (NAS, DMS, WDS, WDA) are reached over PCIe, not over the SoC's IPC router. The QRTR
   layer (`hakios.qrtr.c`) may need a PCIe transport underneath instead of GLINK-IPCRTR.

4. **The mcfg config selection.** The modem needs the right `mcfg_hw.mbn` + `mcfg_sw.mbn`
   for the carrier. Redwood's modem has its configs baked into the monolithic image; munch's
   are separate files the AP must serve. The selection (which `mcfg_*` dir) depends on the
   carrier, SIM, and the modem's reported hardware revision — likely a QMI query.

5. **IPA unchanged.** The IPA (IP accelerator, `hakios.ipa.c`) sits between the modem and
   the AP for the data path. On munch the IPA is IPA 4.5 (redwood: 4.11) — different
   register layout — but the IPA-to-modem wiring is likely still SoC-internal, not over
   PCIe. The IPA port is independent of the modem-transport port.

## What is NOT needed from `pull-firmware.sh`'s output for the modem

- The `modem_pr/so/*.mbn` files are **the modem's own code** — they are NOT loaded by the AP
  into AP-side memory (no `mpss` region exists). They are pushed to the modem or served to
  it over PCIe/TFTP. The AP never parses their ELF structure the way `hakios.mpss.c` parses
  `modem.mdt`. `tools/modem_firmware.py` (which validates the MDT format) does not apply.
- The `mcfg/` tree is served to the modem on demand; the AP does not interpret it.

## Open questions (need runtime evidence from the phone)

- Which PCIe controller hosts the modem (`1c00000` / `1c08000` / `1c10000`)?
- What is the modem endpoint's vendor/device id (read after the link is up)?
- Does the modem pull its `.so` files via TFTP (redwood-style) or does the AP push them via
  a QMI firmware-update service?
- What QMI services does the modem expose over PCIe, and on what ports?
- Which `mcfg_*` config does the modem request for a given SIM/carrier?

These can be answered by booting Linux/Android on the phone and capturing the modem's
PCIe traffic and QMI exchanges — not from the firmware files alone.

## The other firmware: classic MDT (ports from redwood with chip/version changes)

The modem is the only firmware that needs a **new loading path**. The rest of munch's
firmware uses the same `ELF32 EXEC, QUALCOMM DSP6, statically linked` MDT format redwood
already loads via TrustZone PAS — confirmed with `readelf`:

| Firmware | Format | Entry | Redwood equivalent | Port |
|---|---|---|---|---|
| `fw-gpu/a650_zap.mdt` (+ `.b00/.b01/.b02/.elf`) | MDT, Hexagon EXEC | `0x5000` | `a660_zap.*` | `hakios.adreno.c`: new chip id (Adreno 650), register layout. Same loading path (TrustZone PAS). |
| `fw-gpu/a650_gmu.bin`, `a650_sqe.fw` | raw blobs | — | `a660_gmu.bin`, `a660_sqe.fw` | GMU/sqe microcode, same handling. |
| `fw-audio/adsp.mdt` (+ `.b00..b18`, 19 segs) | MDT, Hexagon EXEC | `0x89500000` | `adsp.mdt` (36 segs) | `hakios.adsp.c`: new segment count, new codec (TFA9894). Same loading path. |
| `fw-ipa/ipa_fws.mdt`, `ipa_uc.mdt` (+ `.b*`) | MDT, Hexagon EXEC | `0x0` | (in redwood's modem image) | `hakios.ipa.c`: **separate AP-side firmware on munch** (not in the modem image), IPA 4.5 vs 4.11 register layout. Same MDT loading. |
| `fw-haptic/aw8697_haptic.bin`, `aw8697_rtp_1.bin` | raw blobs | — | same | `hakios.haptic.c`: **no change** — same AW8697 chip. |
| `fw-audio-codec/tfa98xx.cnt` | NXP TFA9894 config | — | (AW88263s, DSP-driven) | `hakios.speaker.c`/`hakios.sound.c`: new amplifier family. |
| `fw-camera/com.qti.sensormodule.munch_*.bin`, `com.qti.tuned.munch_*.bin` | Qualcomm Chromatix binary | — | `hakios_*.bin` | `hakios.camera.c`: new sensors (IMX582/OV64B40/OV8856/GC02M1/IMX596). Parsed as data. |

So the kernel port splits cleanly:
- **New driver**: modem (PCIe + split-`.so` + QMI-over-PCIe) — see above.
- **Port with version/chip changes**: Adreno 650, IPA 4.5, ADSP (19 segs), cameras, audio codec.
- **No change**: haptic (AW8697), the SoC base addresses (identical, see `soc.args`).

`tools/modem_firmware.py` (which validates the MDT format against a device-tree modem node)
does not apply to munch's split modem; it still applies to the IPA/ADSP/GPU-zap MDTs if
pointed at those firmware dirs (they're the same ELF32 MDT format).
