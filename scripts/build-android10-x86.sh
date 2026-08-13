#!/usr/bin/env bash
set -euo pipefail

BASE_ISO="${BASE_ISO:-android10.iso}"
BASE_URL="${BASE_URL:-https://archive.org/download/androidx86-10-isos/Android%2010%20x64%20%28Eng%29.iso}"
WORK="${WORK:-$PWD/work}"
OUT="${OUT:-$PWD/out}"
TREE="$WORK/iso"
SYSTEM="$WORK/system"

for t in curl xorriso unsquashfs mksquashfs find file; do
  command -v "$t" >/dev/null 2>&1 || { echo "Missing required tool: $t" >&2; exit 1; }
done

rm -rf "$WORK" "$OUT"
mkdir -p "$TREE" "$SYSTEM" "$OUT"

[[ -f "$BASE_ISO" ]] || curl -L --fail --retry 5 "$BASE_URL" -o "$BASE_ISO"

echo "Extracting Android-x86 ISO..."
xorriso -osirrox on -indev "$BASE_ISO" -extract / "$TREE"

echo "ISO filesystem candidates:"
find "$TREE" -type f -o -type l | sort | sed "s#^$TREE/##" | head -200

SYSTEM_SFS="$(find "$TREE" -type f \( -iname 'system.sfs' -o -iname 'system.squashfs' \) -print -quit)"
if [[ -z "$SYSTEM_SFS" ]]; then
  echo "No system.sfs/system.squashfs found" >&2
  exit 2
fi

echo "Found system filesystem: ${SYSTEM_SFS#"$TREE"/}"
file "$SYSTEM_SFS"

rm -rf "$SYSTEM"
mkdir -p "$SYSTEM"
unsquashfs -d "$SYSTEM" "$SYSTEM_SFS"

echo "Extracted system filesystem contents:"
find "$SYSTEM" -maxdepth 3 -printf '%y %p\n' | sort | head -250

# Android-x86 system.sfs normally contains the Android /system tree directly.
# Some images package an extra system/ directory, so accept both layouts.
if [[ -d "$SYSTEM/framework" ]]; then
  ANDROID_SYSTEM="$SYSTEM"
elif [[ -d "$SYSTEM/system/framework" ]]; then
  ANDROID_SYSTEM="$SYSTEM/system"
else
  echo "Could not locate Android /system tree" >&2
  echo "Looking for framework.jar anywhere in extracted filesystem:" >&2
  find "$SYSTEM" -type f -name 'framework.jar' -print >&2
  exit 3
fi

echo "Android /system tree: $ANDROID_SYSTEM"
mkdir -p "$ANDROID_SYSTEM/etc/rebuiltdroid-tux"
printf '%s\n' 'RebuiltDroid Tux' 'Base: Android-x86 Android 10 x64' 'Filesystem: SquashFS' > "$ANDROID_SYSTEM/etc/rebuiltdroid-tux/BUILD_INFO"
printf '%s\n' 'ro.rebuiltdroid.name=RebuiltDroid Tux' 'ro.rebuiltdroid.version=Android 10' 'ro.rebuiltdroid.base=Android-x86' > "$ANDROID_SYSTEM/etc/rebuiltdroid-tux.properties"

echo "Rebuilding system.sfs..."
mksquashfs "$SYSTEM" "$WORK/system.sfs" -comp xz -noappend >/dev/null

ISO_SYSTEM_PATH="/${SYSTEM_SFS#"$TREE"/}"
echo "Replacing ISO filesystem: $ISO_SYSTEM_PATH"
xorriso -indev "$BASE_ISO" \
  -outdev "$OUT/RebuiltDroid-Tux-Android10.iso" \
  -boot_image any replay \
  -map "$WORK/system.sfs" "$ISO_SYSTEM_PATH" \
  -commit >/dev/null

mkdir -p "$OUT/filesystems"
cp "$WORK/system.sfs" "$OUT/filesystems/system.sfs"
printf '%s\n' \
  'RebuiltDroid Tux Android 10 x64' \
  "Base: $BASE_URL" \
  'Filesystem: SquashFS' \
  "Original filesystem path: $ISO_SYSTEM_PATH" \
  "Detected Android /system tree: $ANDROID_SYSTEM" \
  'Branding path inside Android filesystem: /system/etc/rebuiltdroid-tux' \
  'Output: RebuiltDroid-Tux-Android10.iso' > "$OUT/BUILD_INFO.txt"

echo "Done: $OUT/RebuiltDroid-Tux-Android10.iso"
