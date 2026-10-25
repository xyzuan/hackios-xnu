# munch.dtb — placeholder

This directory should hold `munch.dtb`: the flattened device tree from the POCO F4's own
`vendor_boot`. It is **not in the repository** — pull it from the phone:

```sh
# phone in Android, on adb
adb pull /sys/firmware/devicetree/base munch.dtb     # live tree
# or, from a vendor_boot.img dumped on the PC:
#   extract the DTB that mkbootimg appended (see mkxnuimg.py: gzip(kernel) + dtb)
```

`pull-soc.sh` pulls `/sys/firmware/fdt` to generate `soc.args` from the same tree; the tree
itself (this file) is what `mkxnuimg.py` appends to the boot image so the bootloader passes it
to the kernel.

For the scaffold this file is missing; the build does not require it (the `.fdf`'s device-tree
FILE block is commented out, as in redwood), but `mkxnuimg.py` needs it to pack a bootable image.
