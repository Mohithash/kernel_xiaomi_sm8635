### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=Theettam · SukiSU Ultra
do.devicecheck=0
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=peridot
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties


### AnyKernel install
## boot shell variables
block=boot
is_slot_device=auto
ramdisk_compression=auto
patch_vbmeta_flag=auto
no_magisk_check=1

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh

kernel_version=$(cat /proc/version | awk -F '-' '{print $1}' | awk '{print $3}')

## ---------------------- Theettam banner ----------------------
ui_print " "
ui_print "   =========================================="
ui_print "      /~~\\   THEETTAM KERNEL   /~~\\"
ui_print "     /    \\_      __/\\__      _/    \\"
ui_print "     \\_       >>--  \\/  --<<       _/"
ui_print "        \\~~/   peridot . SM8635  \\~~/"
ui_print "   =========================================="
ui_print "        POCO F6  /  Redmi Turbo 3  (SM8635)"
ui_print "        SukiSU Ultra baked  ·  SUSFS ready"
ui_print "   =========================================="
ui_print " "
ui_print "   Kernel version detected : $kernel_version"
ui_print " "
ui_print "   >>>  Flashing Theettam + SukiSU Ultra onto boot...  <<<"
ui_print " "
ui_print "   ------------------------------------------"
ui_print "    Psst... curious what 'Theettam' means?"
ui_print "    Open Google and search (in Malayalam):"
ui_print " "
ui_print "         >>   theettam malayalam meaning   <<"
ui_print " "
ui_print "    ...go on, we'll wait.  thank us later :)"
ui_print "   ------------------------------------------"
ui_print " "
## -------------------------------------------------------------

# boot install
if [ -L "/dev/block/bootdevice/by-name/init_boot_a" -o -L "/dev/block/by-name/init_boot_a" ]; then
    split_boot # for devices with init_boot ramdisk
    flash_boot # for devices with init_boot ramdisk
else
    dump_boot # use split_boot to skip ramdisk unpack, e.g. for devices with init_boot ramdisk
    write_boot # use flash_boot to skip ramdisk repack, e.g. for devices with init_boot ramdisk
fi
## end boot install
