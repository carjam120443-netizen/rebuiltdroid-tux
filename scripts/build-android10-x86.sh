#!/usr/bin/env bash
set -euo pipefail

BASE_ISO="${BASE_ISO:-android10.iso}"
BASE_URL="${BASE_URL:-https://archive.org/download/androidx86-10-isos/Android%2010%20x64%20%28Eng%29.iso}"
WORK="${WORK:-$PWD/work}"
OUT="${OUT:-$PWD/out}"
TREE="$WORK/iso"
SYSTEM="$WORK/system"
IMG="$WORK/system.img"
RAW_IMG="$WORK/system.raw.img"
MOUNT="$WORK/mnt-system"

for t in curl xorriso unsquashfs mksquashfs file find mount umount; do
  command -v "$t" >/dev/null 2>&1 || { echo "Missing required tool: $t" >&2; exit 1; }
done

rm -rf "$WORK" "$OUT"
mkdir -p "$TREE" "$SYSTEM" "$OUT" "$MOUNT"
[[ -f "$BASE_ISO" ]] || curl -L --fail --retry 5 "$BASE_URL" -o "$BASE_ISO"

xorriso -osirrox on -indev "$BASE_ISO" -extract / "$TREE"
SYSTEM_SFS="$(find "$TREE" -type f \( -iname 'system.sfs' -o -iname 'system.squashfs' \) -print -quit)"
[[ -n "$SYSTEM_SFS" ]] || { echo "No system.sfs/system.squashfs found" >&2; exit 2; }
echo "Found system filesystem: ${SYSTEM_SFS#"$TREE"/}"

unsquashfs -d "$SYSTEM" "$SYSTEM_SFS" >/dev/null
if [[ -f "$SYSTEM/system.img" ]]; then
  IMG="$SYSTEM/system.img"
elif [[ -f "$SYSTEM/system/system.img" ]]; then
  IMG="$SYSTEM/system/system.img"
else
  echo "Could not locate Android system.img" >&2
  find "$SYSTEM" -maxdepth 3 -type f -print | sort | head -100
  exit 3
fi

file "$IMG"
if file "$IMG" | grep -qi 'Android sparse image'; then
  command -v simg2img >/dev/null 2>&1 || { echo "Missing required tool: simg2img" >&2; exit 4; }
  simg2img "$IMG" "$RAW_IMG"
else
  cp "$IMG" "$RAW_IMG"
fi

sudo mount -o loop,rw "$RAW_IMG" "$MOUNT"
ANDROID_SYSTEM="$MOUNT"

# Android-x86 10's system image can use an A/B-style layout where framework
# artifacts are under /system/system. Accept both layouts, but never invent a
# framework.jar: the real framework must be present in the image.
if [[ -f "$MOUNT/framework/framework.jar" ]]; then
  FRAMEWORK_ROOT="$MOUNT"
elif [[ -f "$MOUNT/system/framework/framework.jar" ]]; then
  FRAMEWORK_ROOT="$MOUNT/system"
else
  echo "Android system image has no framework.jar" >&2
  echo "Framework candidates:" >&2
  find "$MOUNT" -type f -name 'framework.jar' -print >&2
  sudo umount "$MOUNT"
  exit 5
fi

echo "Android framework root: ${FRAMEWORK_ROOT#$MOUNT}"
mkdir -p "$FRAMEWORK_ROOT/etc/rebuiltdroid-tux"
printf '%s\n' 'RebuiltDroid Tux' 'Base: Android-x86 Android 10 x64' 'Filesystem: system.img inside system.sfs' > "$FRAMEWORK_ROOT/etc/rebuiltdroid-tux/BUILD_INFO"
printf '%s\n' 'ro.rebuiltdroid.name=RebuiltDroid Tux' 'ro.rebuiltdroid.version=Android 10' 'ro.rebuiltdroid.base=Android-x86' > "$FRAMEWORK_ROOT/etc/rebuiltdroid-tux.properties"
sync
sudo umount "$MOUNT"

# Preserve the image exactly as a filesystem image; do not put the mounted
# image contents directly into the outer SquashFS.
cp "$RAW_IMG" "$SYSTEM/system.img"
mksquashfs "$SYSTEM" "$WORK/system.sfs" -comp zlib -noappend >/dev/null
ISO_SYSTEM_PATH="/${SYSTEM_SFS#"$TREE"/}"
xorriso -indev "$BASE_ISO" -outdev "$OUT/RebuiltDroid-Tux-Android10.iso" -boot_image any replay -map "$WORK/system.sfs" "$ISO_SYSTEM_PATH" -commit >/dev/null

mkdir -p "$OUT/filesystems"
cp "$WORK/system.sfs" "$OUT/filesystems/system.sfs"
printf '%s\n' 'RebuiltDroid Tux Android 10 x64' "Base: $BASE_URL" 'Filesystem: SquashFS containing system.img' "Original filesystem path: $ISO_SYSTEM_PATH" 'Branding path inside Android filesystem: /system/etc/rebuiltdroid-tux' 'Output: RebuiltDroid-Tux-Android10.iso' > "$OUT/BUILD_INFO.txt"
echo "Done: $OUT/RebuiltDroid-Tux-Android10.iso"
