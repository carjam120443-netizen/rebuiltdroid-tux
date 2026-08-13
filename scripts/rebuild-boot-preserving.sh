#!/usr/bin/env bash
set -euo pipefail

BASE_ISO="${BASE_ISO:-android10.iso}"
WORK="${WORK:-$PWD/work-preserve}"
OUT="${OUT:-$PWD/out-preserve}"
ISO_TREE="$WORK/iso"
SYSTEM="$WORK/system"

rm -rf "$WORK" "$OUT"
mkdir -p "$ISO_TREE" "$SYSTEM" "$OUT"

echo "========================================"
echo " RebuiltDroid Tux Boot-Preserving Build"
echo "========================================"

echo "[1/9] Inspecting original ISO..."
xorriso -indev "$BASE_ISO" -report_el_torito plain | tee "$OUT/original-el-torito.txt"
xorriso -indev "$BASE_ISO" -report_system_area plain | tee "$OUT/original-system-area.txt"

echo "[2/9] Extracting complete ISO filesystem..."
xorriso -osirrox on -indev "$BASE_ISO" -extract / "$ISO_TREE"

echo "[3/9] Locating Android system filesystem..."
SYSTEM_SFS="$(find "$ISO_TREE" -type f \( -iname 'system.sfs' -o -iname 'system.squashfs' \) -print -quit)"
if [[ -z "$SYSTEM_SFS" ]]; then
  echo "ERROR: Android system SquashFS was not found."
  find "$ISO_TREE" -maxdepth 5 -type f | sort
  exit 2
fi
echo "System filesystem: $SYSTEM_SFS"

echo "[4/9] Extracting real Android system..."
unsquashfs -d "$SYSTEM" "$SYSTEM_SFS"

echo "[5/9] Applying RebuiltDroid Tux branding..."
mkdir -p "$SYSTEM/system/etc/rebuiltdroid-tux"
printf '%s\n' 'RebuiltDroid Tux' 'Android-x86 Android 10 x64' 'Boot-preserving build' > "$SYSTEM/system/etc/rebuiltdroid-tux/build-info"
if [[ -d branding ]]; then
  mkdir -p "$SYSTEM/system/etc/rebuiltdroid-tux/branding"
  cp -a branding/. "$SYSTEM/system/etc/rebuiltdroid-tux/branding/" || true
fi

echo "[6/9] Rebuilding Android system filesystem..."
rm -f "$SYSTEM_SFS"
CPU_COUNT="$(nproc)"; [[ "$CPU_COUNT" -ge 1 ]] || CPU_COUNT=1
echo "Using $CPU_COUNT processor(s) for SquashFS compression."
mksquashfs "$SYSTEM" "$SYSTEM_SFS" -comp xz -processors "$CPU_COUNT" -noappend -progress
echo "New system.sfs:"
ls -lh "$SYSTEM_SFS"

echo "[7/9] Rebuilding ISO with original boot metadata replayed..."
ISO_OUTPUT="$OUT/RebuiltDroid-Tux-Android10-preserved.iso"
# Use the original ISO as the input and explicitly replay its El Torito/system-area boot data.
# The ISO tree is copied first, then only system.sfs is replaced.
xorriso -indev "$BASE_ISO" -outdev "$ISO_OUTPUT" \
  -boot_image any replay \
  -map "$SYSTEM_SFS" /system.sfs \
  -volid "RebuiltDroid Tux Android 10" \
  -commit

if [[ ! -s "$ISO_OUTPUT" ]]; then echo "ERROR: ISO was not created."; exit 3; fi

echo "[8/9] Verifying required Android-x86 boot files and metadata..."
for required in /isolinux/isolinux.bin /isolinux/boot.cat /boot/grub/efi.img /kernel /initrd.img; do
  if ! xorriso -indev "$ISO_OUTPUT" -find "$required" -type f -print -quit | grep -q .; then
    echo "WARNING: required path not found: $required"
  else
    echo "OK: $required"
  fi
done
xorriso -indev "$ISO_OUTPUT" -report_el_torito plain | tee "$OUT/rebuilt-el-torito.txt"
xorriso -indev "$ISO_OUTPUT" -report_system_area plain | tee "$OUT/rebuilt-system-area.txt"
if ! grep -q 'El Torito' "$OUT/rebuilt-el-torito.txt"; then echo "ERROR: El Torito boot metadata missing."; exit 4; fi
if ! grep -q 'isohybrid' "$OUT/rebuilt-system-area.txt"; then echo "ERROR: isohybrid system area missing."; exit 5; fi

echo "[9/9] Creating extracted ISO tree archive..."
tar -C "$ISO_TREE" -czf "$OUT/iso-tree.tar.gz" .
echo "========================================"
echo " BUILD COMPLETE"
echo "========================================"
ls -lh "$ISO_OUTPUT"
echo "RebuiltDroid Tux ISO is ready."
