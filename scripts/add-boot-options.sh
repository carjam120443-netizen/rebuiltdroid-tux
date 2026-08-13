#!/usr/bin/env bash
set -euo pipefail
TREE="${1:?ISO tree path required}"
ANDROID="$TREE/android"
CFG="$ANDROID/grub/menu.lst"
mkdir -p "$ANDROID/grub"
cat >> "$CFG" <<'EOF'

title RebuiltDroid Tux - Debug Mode
    kernel /android/kernel root=/dev/ram0 androidboot.hardware=android_x86 DEBUG=2
    initrd /android/initrd.img

title RebuiltDroid Tux - VESA / Safe Graphics Mode
    kernel /android/kernel root=/dev/ram0 androidboot.hardware=android_x86 nomodeset
    initrd /android/initrd.img

title RebuiltDroid Tux - Vulkan Graphics
    kernel /android/kernel root=/dev/ram0 androidboot.hardware=android_x86
    initrd /android/initrd.img

title RebuiltDroid Tux - No Setup Wizard
    kernel /android/kernel root=/dev/ram0 androidboot.hardware=android_x86 androidboot.rebuiltdroid.skip_setup=1
    initrd /android/initrd.img

title RebuiltDroid Tux - Auto Installation
    kernel /android/kernel root=/dev/ram0 androidboot.hardware=android_x86 androidboot.rebuiltdroid.auto_install=1
    initrd /android/initrd.img

title RebuiltDroid Tux - Auto Update
    kernel /android/kernel root=/dev/ram0 androidboot.hardware=android_x86 androidboot.rebuiltdroid.auto_update=1
    initrd /android/initrd.img

title RebuiltDroid Tux - Boot From Local Drive
    kernel /android/kernel root=/dev/ram0 androidboot.hardware=android_x86 androidboot.rebuiltdroid.local_boot=1
    initrd /android/initrd.img
EOF
echo "Added RebuiltDroid Tux boot options to $CFG"
