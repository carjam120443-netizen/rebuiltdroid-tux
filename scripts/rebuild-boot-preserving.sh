#!/usr/bin/env bash
set -euo pipefail

BASE_ISO="${BASE_ISO:-android10.iso}"
WORK="${WORK:-$PWD/work-preserve-v3}"
OUT="${OUT:-$PWD/out-preserve}"

ISO_TREE="$WORK/iso"
SYSTEM="$WORK/system"

rm -rf "$WORK" "$OUT"
mkdir -p "$ISO_TREE" "$SYSTEM" "$OUT"

echo "=============================================="
echo " RebuiltDroid Tux Android 10"
echo " Boot-Preservation Build v3"
echo "=============================================="

echo
echo "[1/11] Inspecting original boot structure..."

xorriso \
  -indev "$BASE_ISO" \
  -report_el_torito plain \
  | tee "$OUT/original-el-torito.txt"

xorriso \
  -indev "$BASE_ISO" \
  -report_system_area plain \
  | tee "$OUT/original-system-area.txt"

echo
echo "[2/11] Extracting complete ISO filesystem..."

xorriso \
  -osirrox on \
  -indev "$BASE_ISO" \
  -extract / "$ISO_TREE"

echo
echo "[3/11] Locating Android system filesystem..."

SYSTEM_SFS="$(
  find "$ISO_TREE" -type f \
    \( -iname 'system.sfs' -o -iname 'system.squashfs' \) \
    -print -quit
)"

if [[ -z "$SYSTEM_SFS" ]]; then
  echo "ERROR: Android system SquashFS was not found."
  find "$ISO_TREE" -maxdepth 5 -type f | sort
  exit 2
fi

echo "System filesystem:"
echo "  $SYSTEM_SFS"

echo
echo "[4/11] Reading original SquashFS settings..."

SQUASH_INFO="$(unsquashfs -s "$SYSTEM_SFS")"
echo "$SQUASH_INFO"

COMPRESSION="$(
  printf '%s\n' "$SQUASH_INFO" |
  awk -F': ' '/^Compression / {print $2; exit}' |
  tr '[:upper:]' '[:lower:]'
)"

BLOCK_SIZE="$(
  printf '%s\n' "$SQUASH_INFO" |
  awk '/^Block size / {print $3; exit}'
)"

if [[ -z "$COMPRESSION" ]]; then
  echo "ERROR: Could not detect original SquashFS compression."
  exit 3
fi

case "$COMPRESSION" in
  gzip|lzo|lz4|xz|zstd)
    ;;
  *)
    echo "ERROR: Unsupported original SquashFS compression:"
    echo "  $COMPRESSION"
    exit 4
    ;;
esac

if [[ -z "$BLOCK_SIZE" || ! "$BLOCK_SIZE" =~ ^[0-9]+$ ]]; then
  BLOCK_SIZE=131072
fi

echo
echo "Original compression:"
echo "  $COMPRESSION"

echo "Original block size:"
echo "  $BLOCK_SIZE"

echo
echo "[5/11] Extracting real Android system..."

unsquashfs \
  -d "$SYSTEM" \
  "$SYSTEM_SFS"

echo
echo "[6/11] Applying RebuiltDroid Tux branding..."

mkdir -p "$SYSTEM/system/etc/rebuiltdroid-tux"

cat > "$SYSTEM/system/etc/rebuiltdroid-tux/build-info" <<'EOF'
RebuiltDroid Tux
Android-x86 Android 10 x64
Boot-preserving build v3
Original SquashFS compression preserved
EOF

if [[ -d "branding" ]]; then
  mkdir -p "$SYSTEM/system/etc/rebuiltdroid-tux/branding"
  cp -a branding/. \
    "$SYSTEM/system/etc/rebuiltdroid-tux/branding/"
fi

echo
echo "[7/11] Rebuilding system.sfs..."

rm -f "$SYSTEM_SFS"

CPU_COUNT="$(nproc)"

if [[ "$CPU_COUNT" -lt 1 ]]; then
  CPU_COUNT=1
fi

echo "Using $CPU_COUNT processor(s)."
echo "Using original compression: $COMPRESSION"

mksquashfs \
  "$SYSTEM" \
  "$SYSTEM_SFS" \
  -comp "$COMPRESSION" \
  -b "$BLOCK_SIZE" \
  -processors "$CPU_COUNT" \
  -noappend

if [[ ! -s "$SYSTEM_SFS" ]]; then
  echo "ERROR: New system.sfs was not created."
  exit 5
fi

echo
echo "New system.sfs:"
ls -lh "$SYSTEM_SFS"

echo
echo "[8/11] Verifying SquashFS compression..."

NEW_SQUASH_INFO="$(unsquashfs -s "$SYSTEM_SFS")"

echo "$NEW_SQUASH_INFO"

NEW_COMPRESSION="$(
  printf '%s\n' "$NEW_SQUASH_INFO" |
  awk -F': ' '/^Compression / {print $2; exit}' |
  tr '[:upper:]' '[:lower:]'
)"

if [[ "$NEW_COMPRESSION" != "$COMPRESSION" ]]; then
  echo "ERROR: Compression changed!"

  echo "Original:"
  echo "  $COMPRESSION"

  echo "New:"
  echo "  $NEW_COMPRESSION"

  exit 6
fi

echo
echo "SquashFS compression preserved:"
echo "  $NEW_COMPRESSION"

echo
echo "[9/11] Replaying original Android-x86 boot metadata..."

ISO_OUTPUT="$OUT/RebuiltDroid-Tux-Android10-preserved.iso"

xorriso \
  -indev "$BASE_ISO" \
  -outdev "$ISO_OUTPUT" \
  -boot_image any replay \
  -map "$SYSTEM_SFS" "/$(basename "$SYSTEM_SFS")" \
  -volid "RebuiltDroid Tux Android 10" \
  -commit

if [[ ! -s "$ISO_OUTPUT" ]]; then
  echo "ERROR: ISO was not created."
  exit 7
fi

echo
echo "[10/11] Verifying boot structure..."

xorriso \
  -indev "$ISO_OUTPUT" \
  -report_el_torito plain \
  | tee "$OUT/rebuilt-el-torito.txt"

xorriso \
  -indev "$ISO_OUTPUT" \
  -report_system_area plain \
  | tee "$OUT/rebuilt-system-area.txt"

if ! grep -q "El Torito" "$OUT/rebuilt-el-torito.txt"; then
  echo "ERROR: El Torito boot metadata missing."
  exit 8
fi

if ! grep -q "/isolinux/isolinux.bin" "$OUT/rebuilt-el-torito.txt"; then
  echo "ERROR: BIOS boot image was not preserved."
  exit 9
fi

if ! grep -q "/boot/grub/efi.img" "$OUT/rebuilt-el-torito.txt"; then
  echo "ERROR: UEFI boot image was not preserved."
  exit 10
fi

if ! grep -qi "isohybrid\|MBR.*GPT" \
  "$OUT/rebuilt-system-area.txt"; then
  echo "ERROR: Expected ISO hybrid MBR/GPT structure missing."
  exit 11
fi

echo
echo "Boot metadata checks passed."

echo
echo "[11/11] Creating extracted ISO tree archive..."

tar \
  -C "$ISO_TREE" \
  -czf "$OUT/iso-tree.tar.gz" \
  .

echo
echo "=============================================="
echo " BUILD COMPLETE"
echo "=============================================="

echo
echo "Generated ISO:"
ls -lh "$ISO_OUTPUT"

echo
echo "Output directory:"
ls -lh "$OUT"

echo
echo "RebuiltDroid Tux ISO is ready."
