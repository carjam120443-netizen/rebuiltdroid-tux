#!/usr/bin/env bash
set -euo pipefail

BASE_ISO="${BASE_ISO:-android10.iso}"
WORK="${WORK:-$PWD/work-preserve-v2}"
OUT="${OUT:-$PWD/out-preserve}"
ISO_TREE="$WORK/iso"
SYSTEM="$WORK/system"

rm -rf "$WORK" "$OUT"
mkdir -p "$ISO_TREE" "$SYSTEM" "$OUT"

echo "=============================================="
echo " RebuiltDroid Tux Android 10"
echo " Boot-Preservation Build v2"
echo "=============================================="

echo
 echo "[1/10] Inspecting original boot structure..."
xorriso -indev "$BASE_ISO" -report_el_torito plain | tee "$OUT/original-el-torito.txt"
xorriso -indev "$BASE_ISO" -report_system_area plain | tee "$OUT/original-system-area.txt"

 echo
 echo "[2/10] Extracting complete ISO filesystem..."
xorriso -osirrox on -indev "$BASE_ISO" -extract / "$ISO_TREE"

 echo
 echo "[3/10] Locating Android system filesystem..."
SYSTEM_SFS="$(find "$ISO_TREE" -type f \( -iname 'system.sfs' -o -iname 'system.squashfs' \) -print -quit)"
if [[ -z "$SYSTEM_SFS" ]]; then
  echo "ERROR: Android system SquashFS was not found."
  find "$ISO_TREE" -maxdepth 5 -type f | sort
  exit 2
fi

echo "System filesystem: $SYSTEM_SFS"

 echo
 echo "[4/10] Extracting real Android system..."
unsquashfs -d "$SYSTEM" "$SYSTEM_SFS"

 echo
 echo "[5/10] Applying RebuiltDroid Tux branding..."
mkdir -p "$SYSTEM/system/etc/rebuiltdroid-tux"
printf '%s\n' \
  'RebuiltDroid Tux' \
  'Android-x86 Android 10 x64' \
  'Boot-preserving build v2' \
  > "$SYSTEM/system/etc/rebuiltdroid-tux/build-info"

if [[ -d branding ]]; then
  mkdir -p "$SYSTEM/system/etc/rebuiltdroid-tux/branding"
  cp -a branding/. "$SYSTEM/system/etc/rebuiltdroid-tux/branding/"
fi

 echo
 echo "[6/10] Rebuilding Android system filesystem..."
rm -f "$SYSTEM_SFS"
CPU_COUNT="$(nproc)"
if [[ "$CPU_COUNT" -lt 1 ]]; then CPU_COUNT=1; fi
echo "Using $CPU_COUNT processor(s) for SquashFS compression."
mksquashfs "$SYSTEM" "$SYSTEM_SFS" \
  -comp xz \
  -processors "$CPU_COUNT" \
  -noappend

test -s "$SYSTEM_SFS"
echo "New system.sfs:"
ls -lh "$SYSTEM_SFS"

 echo
 echo "[7/10] Replaying original Android-x86 boot metadata..."
ISO_OUTPUT="$OUT/RebuiltDroid-Tux-Android10-preserved.iso"

# Start from the original ISO as the source image. This keeps the original
# El Torito catalog, BIOS boot image, UEFI boot image, MBR/isohybrid data,
# and GPT structures instead of generating a new boot layout.
xorriso \
  -indev "$BASE_ISO" \
  -outdev "$ISO_OUTPUT" \
  -boot_image any replay \
  -map "$SYSTEM_SFS" "/$(basename "$SYSTEM_SFS")" \
  -volid "RebuiltDroid Tux Android 10" \
  -commit

if [[ ! -s "$ISO_OUTPUT" ]]; then
  echo "ERROR: ISO was not created."
  exit 3
fi

 echo
 echo "[8/10] Verifying boot structure..."
for required in \
  /isolinux/isolinux.bin \
  /isolinux/boot.cat \
  /boot/grub/efi.img \
  /kernel \
  /initrd.img; do
  if xorriso -indev "$ISO_OUTPUT" -find "$required" -type f -print -quit | grep -q .; then
    echo "OK: $required"
  else
    echo "WARNING: required path not found: $required"
  fi
done

xorriso -indev "$ISO_OUTPUT" -report_el_torito plain \
  | tee "$OUT/rebuilt-el-torito.txt"

xorriso -indev "$ISO_OUTPUT" -report_system_area plain \
  | tee "$OUT/rebuilt-system-area.txt"

if ! grep -q 'El Torito' "$OUT/rebuilt-el-torito.txt"; then
  echo "ERROR: El Torito boot metadata missing."
  exit 4
fi

if ! grep -qi 'isohybrid\|MBR.*GPT' "$OUT/rebuilt-system-area.txt"; then
  echo "ERROR: Expected isohybrid/MBR/GPT system area was not detected."
  exit 5
fi

 echo
 echo "[9/10] Comparing original and rebuilt boot metadata..."
if ! grep -q '/isolinux/isolinux.bin' "$OUT/rebuilt-el-torito.txt"; then
  echo "ERROR: BIOS boot image was not preserved."
  exit 6
fi

if ! grep -q '/boot/grub/efi.img' "$OUT/rebuilt-el-torito.txt"; then
  echo "ERROR: UEFI boot image was not preserved."
  exit 7
fi

 echo "Boot metadata checks passed."

 echo
 echo "[10/10] Creating extracted ISO tree archive..."
tar -C "$ISO_TREE" -czf "$OUT/iso-tree.tar.gz" .

echo
 echo "=============================================="
echo " BUILD COMPLETE"
echo "=============================================="
echo
ls -lh "$ISO_OUTPUT"
echo
 echo "RebuiltDroid Tux ISO is ready."
