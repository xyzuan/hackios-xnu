# Binaries/munch/ — the phone's UEFI drivers, placeholder

This directory should hold the UEFI DXE drivers and raw files extracted from the POCO F4's own
`xbl.img`, the way Mu-Silicium ships them for its supported phones (see
`devices/poco-x5-pro/uefi/files/Binaries/redwood/README.md` for redwood's set and the patches
applied to some of them).

Extract them with [UEFIReader](https://github.com/WOA-Project/UEFIReader):

```sh
# from a dumped xbl.img of the POCO F4
UEFIReader xbl.img   # -> a tree of .efi / .inf / .depex / .te / .raw under QcomPkg/, MdeModulePkg/, ...
# lay the result out as this directory: Binaries/munch/QcomPkg/Drivers/..., Binaries/munch/RawFiles/...
```

The driver lists in `../Platforms/Xiaomi/munchPkg/Include/{APRIORI,DXE,RAW}.inc` reference
`Binaries/munch/...`; the build will fail until those files are present.

## For a first bring-up test

alioth (POCO F3) is the **same SM8250 SoC**, and Mu-Silicium ships its `Binaries/alioth` as a
submodule. The SoC-level drivers (Clock, SPMI, UFS, USB, Tz, Smem, etc.) are shared across the
SoC, so for a first test you can alias them:

```sh
# after `uefi/apply.sh` has cloned Mu-Silicium (with submodules)
cd Mu-Silicium
rm -rf Binaries/munch
cp -r Binaries/alioth Binaries/munch     # SoC-level drivers: same SM8250
```

The **board-specific** files must come from munch's own `xbl.img` — above all:
- `RawFiles/Panel_*.xml` (the display panel init sequences — munch's panel differs from alioth's),
- `RawFiles/QcomChargerCfg.cfg`, `RawFiles/BATTERY.PROVISION*` (charger / battery calibration),
- `RawFiles/SecParti.cfg`, `RawFiles/uefipil.cfg` (partition / PIL config).

With `USE_CUSTOM_DISPLAY_DRIVER = 0` (the scaffold default), the panel XMLs are not used — the
build uses `SiliciumPkg/Drivers/SimpleFbDxe` instead — so an alioth alias is enough to get a
first UEFI image that initialises the SoC and hands off to the XNU loader.
