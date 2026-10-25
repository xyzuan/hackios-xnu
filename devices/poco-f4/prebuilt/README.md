# prebuilt/ for munch (POCO F4)

Built UEFI pieces for this device, refreshed by `tools/update-prebuilt.sh` after a Mu-Silicium
build. **Empty in the scaffold** — nothing is built yet.

After `uefi/apply.sh` + `python3 build_uefi.py -d munch -r RELEASE`, this directory should hold:

| File | From |
|---|---|
| `SILICIUM_UEFI.fd` | `Mu-Silicium/Build/munchPkg/RELEASE_CLANGPDB/FV/SILICIUM_UEFI.fd` |
| `BootShim.bin` | `Mu-Silicium/BootShim/BootShim.bin` (built with `FD_BASE=0x9FC00000 FD_SIZE=0x300000`) |
| `device-tree.dtb` | the phone's own DTB from `vendor_boot` (see `../uefi/files/Resources/DTBs/`) |
| `ramdisk` | `Mu-Silicium/Resources/ramdisk` |
| `mkbootimg.py` | `Mu-Silicium/Resources/Scripts/mkbootimg.py` |

> `tools/update-prebuilt.sh` is device-aware: `DEVICE=poco-f4` makes it copy from
> `Build/munchPkg` into this directory. (Default `DEVICE=poco-x5-pro` refreshes redwood's, so
> `make prebuilt` without `DEVICE` keeps its old behavior.)
