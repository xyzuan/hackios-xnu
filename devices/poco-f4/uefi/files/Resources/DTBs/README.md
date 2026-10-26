# munch device tree (dtb + dts)

Pulled from the POCO F4's `vendor_boot` partition (the boot dtb — the *live*
`/sys/firmware/fdt` was already used for `soc.args`; this is the boot tree that
`mkxnuimg.py` appends to the boot image).

| File | Size | Purpose |
|---|---:|---|
| `munch.dtb` | 461 KB | flattened device tree blob — `mkxnuimg.py` appends this to the boot image; the bootloader passes it to the kernel |
| `munch.dts` | 600 KB | decompiled device tree source (`dtc -I dtb -O dts`) — human-readable porting reference |

## How they were pulled

```sh
# phone in Android, on adb, with KSU root
ADB=adb
$ADB shell "su -c 'dd if=/dev/block/by-name/vendor_boot_a of=/sdcard/vendor_boot.img'"
$ADB pull /sdcard/vendor_boot.img vendor_boot.img
$ADB shell "rm /sdcard/vendor_boot.img"
# vendor_boot is Android v3 ("VNDRBOOT" magic); the dtb is at offset 0x135e000, size 461775 bytes
# (found by scanning for the FDT magic 0xd00dfeed and validating totalsize)
python3 -c "d=open('vendor_boot.img','rb').read(); open('munch.dtb','wb').write(d[0x135e000:0x135e000+461775])"
dtc -I dtb -O dts -q -o munch.dts munch.dtb   # the warnings are cosmetic (#address-cells quirks)
```

## What the tree confirms (porting-relevant)

From the root: `model = "Qualcomm Technologies, Inc. kona v2.1 SoC"`,
`compatible = "qcom,kona"`, `qcom,msm-id = <0x164 0x20001>` — SM8250/kona, MSM id 0x164.

- **Modem: external SDX55 on PCIe** — `compatible = "qcom,ext-sdx55m"` (line ~2913),
  the rmnet network device is at `/soc/qcom,pcie@1c10000/pcie2_rp/qcom,mhi@0/mhi_rmnet@0`.
  The three PCIe controllers are `qcom,pcie@1c00000` (pcie0), `@1c08000` (pcie1),
  `@1c10000` (pcie2 = modem host). **No `qcom,mss`/`qcom,mpss` node, no `pas-id = 4`** (the
  redwood modem's TrustZone image id). The other `pas-id`s are for ADSP/CDSP/SLPI/SPSS/GPU.
  See `../../MODEM-ARCHITECTURE.md`.
- **IPA: `qcom,ipa@1e00000`, `qcom,ipa-hw-ver = <0x11>`** (line ~4801). `0x11` = 17 is the
  SoC's IPA version register value; `hakios.ipa.c` (redwood) is keyed on a different
  version — needs checking against the IPA 4.x version table. Also `qcom,ipa_fws`,
  `qcom,ipa_uc`, `qcom,ipa-mpm` sub-nodes.
- **AOSS: `qcom,qmp-aop@c300000`** (line ~5066) — the source of `soc_aoss=0xc300000` in
  `soc.args` (the parser misses it because the compatible is `qcom,sm8250-aoss-qmp`, not
  `qcom,sm8350-aoss-qmp`).
- **apps-smmu** at `0x15000000` (matches `soc.args`'s `soc_apps_smmu`).
- **reserved-memory** has no `mpss`/`mss` node — confirms the modem memory is not AP-managed.

## Regenerating

The dtb/dts here are from this phone's `vendor_boot_a` (the active slot). If the phone's
firmware is updated, re-pull with the steps above. The dts is large (600 KB, 22,693 lines)
but kept in the repo as the porting reference — the modem/PCIe/IPA/PMIC work all reads from it.
