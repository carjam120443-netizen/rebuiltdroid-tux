#!/usr/bin/env bash
set -euo pipefail

BASE_ISO="${BASE_ISO:-android10.iso}"
BASE_URL="${BASE_URL:-https://archive.org/download/androidx86-10-isos/Android%2010%20x64%20%28Eng%29.iso}"
WORK="${WORK:-$PWD/work}"
OUT="${OUT:-$PWD/out}"
TREE="$WORK/iso"
SYSTEM="$WORK/system"

for t in curl xorriso unsquashfs mksquashfs; do
  command -v "$t" >/dev/null 2>&1 || { echo "Missing required tool: $t" >&2; exit 1; }
done

rm -rf "$WORK" "$OUT"
mkdir -p "$TREE" "$SYSTEM" "$OUT"

[[ -f "$BASE_ISO" ]] || curl -L --fail --retry 5 "$BASE_URL" -o "$BASE_ISO"

echo "Extracting Android-x86 ISO..."
xorriso -osirrox on -indev "$BASE_ISO" -extract / "$TREE"
echo "Searching ISO for Android system filesystem..."
SYSTEM_SFS="$(find "$TREE" -type f \( -iname 'system.sfs' -o -iname 'system.squashfs' \) -print -quit)"

if [[ -z "$SYSTEM_SFS" ]]; then
  echo "No system.sfs/system.squashfs found in the ISO. ISO contents:"
  find "$TREE" -maxdepth 4 -type f -printf '%P\n' | sort | head -200
  exit 2
fi

echo "Found system filesystem: ${SYSTEM_SFS#"$TREE"/}"
echo "Extracting real system filesystem..."
unsquashfs -d "$SYSTEM" "$SYSTEM_SFS"

# Android-x86's SquashFS contents represent the Android /system tree.
# Keep RebuiltDroid metadata inside that tree rather than alongside it.
ANDROID_SYSTEM="$SYSTEM/system"
mkdir -p "$ANDROID_SYSTEM/etc/rebuiltdroid-tux"
cat > "$ANDROID_SYSTEM/etc/rebuiltdroid-tux/BUILD_INFO" <<'EOF'
RebuiltDroid Tux
Base: Android-x86 Android 10 x64
Filesystem: SquashFS
EOF

cat > "$ANDROID_SYSTEM/etc/rebuiltdroid-tux.properties" <<'EOF'
ro.rebuiltdroid.name=RebuiltDroid Tux
ro.rebuiltdroid.version=Android 10
ro.rebuiltdroid.base=Android-x86
EOF

echo "Rebuilding real system filesystem..."
mksquashfs "$SYSTEM" "$WORK/system.sfs" -comp xz -noappend >/dev/null

ISO_SYSTEM_PATH="/${SYSTEM_SFS#"$TREE"/}"
echo "Replacing $ISO_SYSTEM_PATH while replaying the original boot metadata..."
xorriso -indev "$BASE_ISO" \
  -outdev "$OUT/RebuiltDroid-Tux-Android10.iso" \
  -boot_image any replay \
  -map "$WORK/system.sfs" "$ISO_SYSTEM_PATH" \
  -commit >/dev/null

mkdir -p "$OUT/filesystems"
cp "$WORK/system.sfs" "$OUT/filesystems/system.sfs"
cat > "$OUT/BUILD_INFO.txt" <<EOF
RebuiltDroid Tux Android 10 x64
Base: $BASE_URL
Filesystem: SquashFS
Original filesystem path: $ISO_SYSTEM_PATH
Branding path inside Android filesystem: /system/etc/rebuiltdroid-tux
Output: RebuiltDroid-Tux-Android10.iso
EOF

echo "Done: $OUT/RebuiltDroid-Tux-Android10.iso"
