#!/usr/bin/env bash
set -euo pipefail

BASE_ISO="${BASE_ISO:-android10.iso}"
BASE_URL="${BASE_URL:-https://archive.org/download/androidx86-10-isos/Android%2010%20x64%20%28Eng%29.iso}"
WORK="${WORK:-$PWD/work}"
OUT="${OUT:-$PWD/out}"
TREE="$WORK/iso"
SYSTEM="$WORK/system"

for t in curl xorriso unsquashfs mksquashfs; do command -v "$t" >/dev/null || { echo "Missing $t"; exit 1; }; done
rm -rf "$WORK" "$OUT"; mkdir -p "$TREE" "$SYSTEM" "$OUT"
[[ -f "$BASE_ISO" ]] || curl -L --fail --retry 3 "$BASE_URL" -o "$BASE_ISO"

echo "Extracting Android-x86 ISO..."
xorriso -osirrox on -indev "$BASE_ISO" -extract / "$TREE" >/dev/null
ANDROID="$TREE/android"
[[ -f "$ANDROID/system.sfs" ]] || { echo "Expected Android-x86 system.sfs was not found."; find "$ANDROID" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null || true; exit 2; }

echo "Extracting real system filesystem..."
unsquashfs -d "$SYSTEM" "$ANDROID/system.sfs"
mkdir -p "$SYSTEM/etc/rebuiltdroid-tux"
cat > "$SYSTEM/etc/rebuiltdroid-tux/BUILD_INFO" <<'EOF'
RebuiltDroid Tux
Base: Android-x86 Android 10 x64
Filesystem: SquashFS
EOF

# Add a separate customization property file rather than modifying signed/system-critical files.
cat > "$SYSTEM/etc/rebuiltdroid-tux.properties" <<'EOF'
ro.rebuiltdroid.name=RebuiltDroid Tux
ro.rebuiltdroid.version=Android 10
ro.rebuiltdroid.base=Android-x86
EOF

echo "Rebuilding real system.sfs..."
mksquashfs "$SYSTEM" "$WORK/system.sfs" -comp xz -noappend >/dev/null

# Replace only the Android system filesystem while retaining the upstream ISO boot structure.
echo "Creating bootable RebuiltDroid Tux ISO..."
xorriso -indev "$BASE_ISO" -outdev "$OUT/RebuiltDroid-Tux-Android10.iso" -boot_image any replay -map "$WORK/system.sfs" /android/system.sfs -commit >/dev/null

mkdir -p "$OUT/filesystems"
cp "$WORK/system.sfs" "$OUT/filesystems/system.sfs"
cat > "$OUT/BUILD_INFO.txt" <<EOF
RebuiltDroid Tux Android 10 x64
Base: $BASE_URL
Filesystem: Android-x86 system.sfs (SquashFS)
Output: RebuiltDroid-Tux-Android10.iso
EOF

echo "Done: $OUT/RebuiltDroid-Tux-Android10.iso"
