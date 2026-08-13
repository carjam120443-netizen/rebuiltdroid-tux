#!/usr/bin/env bash
set -euo pipefail
BASE_ISO="${BASE_ISO:-android10.iso}"
BASE_URL="${BASE_URL:-https://archive.org/download/androidx86-10-isos/Android%2010%20x64%20%28Eng%29.iso}"
WORK="${WORK:-$PWD/work}"
OUT="${OUT:-$PWD/out}"
TREE="$WORK/iso"
SYSTEM="$WORK/system"
for t in curl xorriso unsquashfs mksquashfs; do command -v "$t" >/dev/null 2>&1 || { echo "Missing required tool: $t" >&2; exit 1; }; done
rm -rf "$WORK" "$OUT"
mkdir -p "$TREE" "$SYSTEM" "$OUT"
[[ -f "$BASE_ISO" ]] || curl -L --fail --retry 5 "$BASE_URL" -o "$BASE_ISO"
xorriso -osirrox on -indev "$BASE_ISO" -extract / "$TREE"
SYSTEM_SFS="$(find "$TREE" -type f \( -iname 'system.sfs' -o -iname 'system.squashfs' \) -print -quit)"
[[ -n "$SYSTEM_SFS" ]] || { echo "No system.sfs/system.squashfs found" >&2; exit 2; }
unsquashfs -d "$SYSTEM" "$SYSTEM_SFS"
if [[ -d "$SYSTEM/framework" ]]; then ANDROID_SYSTEM="$SYSTEM"; elif [[ -d "$SYSTEM/system/framework" ]]; then ANDROID_SYSTEM="$SYSTEM/system"; else echo "Could not locate Android /system tree" >&2; exit 3; fi
echo "Android /system tree: $ANDROID_SYSTEM"
mkdir -p "$ANDROID_SYSTEM/etc/rebuiltdroid-tux"
printf '%s\n' 'RebuiltDroid Tux' 'Base: Android-x86 Android 10 x64' 'Filesystem: SquashFS' > "$ANDROID_SYSTEM/etc/rebuiltdroid-tux/BUILD_INFO"
printf '%s\n' 'ro.rebuiltdroid.name=RebuiltDroid Tux' 'ro.rebuiltdroid.version=Android 10' 'ro.rebuiltdroid.base=Android-x86' > "$ANDROID_SYSTEM/etc/rebuiltdroid-tux.properties"
mksquashfs "$SYSTEM" "$WORK/system.sfs" -comp xz -noappend >/dev/null
ISO_SYSTEM_PATH="/${SYSTEM_SFS#"$TREE"/}"
xorriso -indev "$BASE_ISO" -outdev "$OUT/RebuiltDroid-Tux-Android10.iso" -boot_image any replay -map "$WORK/system.sfs" "$ISO_SYSTEM_PATH" -commit >/dev/null
mkdir -p "$OUT/filesystems"
cp "$WORK/system.sfs" "$OUT/filesystems/system.sfs"
printf '%s\n' 'RebuiltDroid Tux Android 10 x64' "Base: $BASE_URL" 'Filesystem: SquashFS' "Original filesystem path: $ISO_SYSTEM_PATH" "Detected Android /system tree: $ANDROID_SYSTEM" 'Branding path inside Android filesystem: /system/etc/rebuiltdroid-tux' 'Output: RebuiltDroid-Tux-Android10.iso' > "$OUT/BUILD_INFO.txt"
echo "Done: $OUT/RebuiltDroid-Tux-Android10.iso"
