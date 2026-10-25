# UEFI for munch

A port of [Project Silicium / Mu-Silicium](https://github.com/Project-Silicium/Mu-Silicium) to the
POCO F4, **modelled on `aliothPkg`** (the POCO F3 — the same SM8250 "kona" SoC). The redwood port
was done the same way, modelled on `lisaPkg` (the same SM7325 "yupik" SoC as redwood).

> **Scaffold, for testing.** The platform package (`munchPkg`) is `aliothPkg` renamed, with kona's
> real memory map and configuration map. The SoC-agnostic changes (the BootShim payload copy and
> the XNU loader that replaces the boot menu) are carried over from the redwood port verbatim. What
> still has to come from the phone is listed at the end.

What is here:

- `BASE`: the Mu-Silicium commit the port is made on — **the same commit as redwood**, so the
  `mu-silicium.patch` (which touches shared `BootShim/` and `Silicon/.../BootManagerLib/`) applies
  cleanly. KonaPkg and aliothPkg must exist on this commit; if they do not, bump `BASE` to a newer
  Mu-Silicium commit that has them and re-export the patch (`export.sh`).
- `mu-silicium.patch`: changes to existing files: `BootShim/BootShim.S` (copies the "XNUP"
  container behind the UEFI image to `0xF0000000`) and `BootManagerLib` (starts the XNU loader from
  the container instead of a menu). **Identical to redwood's** — SoC-agnostic.
- `files/`: new files:
  - `Platforms/Xiaomi/munchPkg` — the platform package (memory map, configuration map, driver
    lists, `.dsc/.fdf/.dec`, `DeviceBuild.py`), renamed from `aliothPkg`, with kona's memory map
    and config. The `XNU Payload` region (`0xF0000000`, 64 MB) is added to the memory map because
    the BootShim writes there and alioth's map did not reserve it.
  - `Silicon/.../BootManagerLib/XnuLoader.[ch]` — the XNU loader, identical to redwood's.
  - `Resources/Configs/munch.toml` — boot-shim config; UEFI FD base `0x9FC00000`, size `0x300000`
    (kona's UEFI FD region, from alioth's memory map; redwood's was `0x9FD00000`/`0x200000`).
  - `Resources/DTBs/munch.dtb` — **placeholder**; see `files/Resources/DTBs/README.md`.
  - `Binaries/munch` — the UEFI drivers of the phone's own firmware; see
    `files/Binaries/munch/README.md`.

## Build

Packages as in Mu-Silicium's `setup_env.sh` (Arch: `git base-devel lld nasm clang llvm
aarch64-linux-gnu-gcc python python-pip python-virtualenv`).

```sh
devices/poco-f4/uefi/apply.sh          # clones Mu-Silicium (with submodules, ~3 GB) and applies the port
python3 -m venv venv && venv/bin/pip install -r Mu-Silicium/pip-requirements.txt
cd Mu-Silicium
source ../venv/bin/activate
python3 build_uefi.py -d munch -r RELEASE     # -> Build/munchPkg/RELEASE_CLANGPDB/FV/SILICIUM_UEFI.fd
```

The `mu_nasm` workaround (no Mono) is the same as redwood's; see `devices/poco-x5-pro/uefi/README.md`.

After a build, `mkxnuimg.py` (called by `./xl enter`) takes the UEFI from `Mu-Silicium/`. It is
**device-aware**: `DEVICE=poco-f4` (or `--device poco-f4`) makes it read munch's codename, package
(`Build/munchPkg`) and FD base/size (`0x9FC00000`/`0x300000`) from
`files/Resources/Configs/munch.toml`, and write `xnu-munch.img`. `tools/update-prebuilt.sh` takes
the same `DEVICE` and refreshes `devices/poco-f4/prebuilt/` from `Build/munchPkg`.

`devices/poco-f4/uefi/export.sh` is the reverse of `apply.sh`: it saves the changes from
`Mu-Silicium/` here.

## What still has to come from the phone

- `files/Binaries/munch/` — extract from `xbl.img` with UEFIReader, or alias `Binaries/alioth` for
  a first bring-up (same SoC); board-specific files (panels, charger, battery) must be munch's own.
- `files/Resources/DTBs/munch.dtb` — the device tree from the phone's `vendor_boot`.
- ACPI tables: the `.dsc`/`.fdf` reference `alioth/AcpiTables.inf` (the kona sibling's tables, the
  same pattern redwood uses with `lisa/AcpiTables.inf`). If munch needs its own, create
  `munch/AcpiTables.inf` and point the `.dsc`/`.fdf` at it.
