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

echo
echo "[1/8] Inspecting original ISO..."

xorriso \
  -indev "$BASE_ISO" \
  -report_el_torito plain \
  | tee "$OUT/original-el-torito.txt"

xorriso \
  -indev "$BASE_ISO" \
  -report_system_area plain \
  | tee "$OUT/original-system-area.txt"

echo
echo "[2/8] Extracting complete ISO filesystem..."

xorriso \
  -osirrox on \
  -indev "$BASE_ISO" \
  -extract / "$ISO_TREE"

echo
echo "[3/8] Locating Android system filesystem..."

SYSTEM_SFS="$(
  find "$ISO_TREE" -type f \
    \( -iname 'system.sfs' -o -iname 'system.squashfs' \) \
    -print -quit
)"

if [[ -z "$SYSTEM_SFS" ]]; then
    echo "ERROR: Android system SquashFS was not found."
    echo
    echo "Files found in the extracted ISO:"
    find "$ISO_TREE" -maxdepth 5 -type f | sort
    exit 2
fi

echo "System filesystem:"
echo "  $SYSTEM_SFS"

echo
echo "[4/8] Extracting real Android system..."

unsquashfs \
  -d "$SYSTEM" \
  "$SYSTEM_SFS"

echo
echo "[5/8] Applying RebuiltDroid Tux branding..."

mkdir -p "$SYSTEM/system/etc/rebuiltdroid-tux"

cat > "$SYSTEM/system/etc/rebuiltdroid-tux/build-info" <<'EOF'
RebuiltDroid Tux
Android-x86 Android 10 x64
Boot-preserving build
EOF

if [[ -d "branding" ]]; then
    mkdir -p "$SYSTEM/system/etc/rebuiltdroid-tux/branding"

    cp -a \
      branding/. \
      "$SYSTEM/system/etc/rebuiltdroid-tux/branding/" \
      || true
fi

echo
echo "[6/8] Rebuilding ONLY the Android system filesystem..."

rm -f "$SYSTEM_SFS"

# Use every CPU available on the GitHub Actions runner.
CPU_COUNT="$(nproc)"

if [[ "$CPU_COUNT" -lt 1 ]]; then
    CPU_COUNT=1
fi

echo "Using $CPU_COUNT processor(s) for SquashFS compression."

mksquashfs \
  "$SYSTEM" \
  "$SYSTEM_SFS" \
  -comp xz \
  -processors "$CPU_COUNT" \
  -noappend \
  -progress

echo
echo "[7/8] Rebuilding ISO from preserved Android-x86 boot tree..."

#
# We do not modify:
#
# - kernel
# - initrd
# - GRUB files
# - isolinux files
# - Android boot configuration
# - EFI image
#
# Only system.sfs has been replaced.
#

ISO_OUTPUT="$OUT/RebuiltDroid-Tux-Android10-preserved.iso"

xorriso \
  -as mkisofs \
  -R \
  -J \
  -joliet-long \
  -V "RebuiltDroid Tux Android 10" \
  -o "$ISO_OUTPUT" \
  "$ISO_TREE"

echo
echo "[8/8] Verifying generated ISO..."

if [[ ! -s "$ISO_OUTPUT" ]]; then
    echo "ERROR: ISO was not created."
    exit 3
fi

echo
echo "Generated ISO:"
ls -lh "$ISO_OUTPUT"

echo
echo "Checking rebuilt El Torito boot information..."

xorriso \
  -indev "$ISO_OUTPUT" \
  -report_el_torito plain \
  | tee "$OUT/rebuilt-el-torito.txt"

echo
echo "Checking rebuilt system-area information..."

xorriso \
  -indev "$ISO_OUTPUT" \
  -report_system_area plain \
  | tee "$OUT/rebuilt-system-area.txt"

echo
echo "Creating extracted ISO tree archive..."

tar \
  -C "$ISO_TREE" \
  -czf "$OUT/iso-tree.tar.gz" \
  .

echo
echo "========================================"
echo " BUILD COMPLETE"
echo "========================================"

echo
echo "ISO:"
echo "  $ISO_OUTPUT"

echo
echo "Artifacts:"
echo "  $OUT/original-el-torito.txt"
echo "  $OUT/original-system-area.txt"
echo "  $OUT/rebuilt-el-torito.txt"
echo "  $OUT/rebuilt-system-area.txt"
echo "  $OUT/iso-tree.tar.gz"

echo
echo "RebuiltDroid Tux ISO is ready."
