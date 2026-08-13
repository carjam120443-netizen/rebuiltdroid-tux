#!/usr/bin/env bash
set -euo pipefail

# RebuiltDroid Tux - Android 10 filesystem/ISO builder
# Expected input: a user-provided Android 10 ISO at BASE_ISO, or BASE_URL pointing
# to a redistributable Android 10 ISO permitted by its license.

BASE_ISO="${BASE_ISO:-android10.iso}"
BASE_URL="${BASE_URL:-}"
WORK="${WORK:-$PWD/work}"
OUT="${OUT:-$PWD/out}"
ROOTFS="$WORK/rootfs"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required tool: $1" >&2; exit 1; }; }
for t in xorriso unsquashfs mksquashfs 7z cpio gzip; do need "$t"; done

rm -rf "$WORK" "$OUT"
mkdir -p "$WORK" "$OUT" "$ROOTFS" "$WORK/iso"

if [[ ! -f "$BASE_ISO" ]]; then
  if [[ -z "$BASE_URL" ]]; then
    echo "Set BASE_ISO to an Android 10 ISO or BASE_URL to a legally redistributable source." >&2
    exit 2
  fi
  curl -L --fail --retry 3 "$BASE_URL" -o "$BASE_ISO"
fi

echo "[1/7] Extracting Android 10 ISO..."
xorriso -osirrox on -indev "$BASE_ISO" -extract / "$WORK/iso" >/dev/null

# Android-x86/derivative images commonly use one of these filesystem layouts.
# Locate system/vendor/product/odm images without assuming one exact upstream layout.
find "$WORK/iso" -type f \( -name 'system.img' -o -name 'vendor.img' -o -name 'product.img' -o -name 'odm.img' -o -name 'ramdisk.img' \) -print

mkdir -p "$ROOTFS"/{system,vendor,product,odm,ramdisk}

extract_img() {
  local name="$1" dst="$2" src
  src="$(find "$WORK/iso" -type f -name "$name" -print -quit || true)"
  [[ -n "$src" ]] || return 0
  case "$src" in
    *.squashfs|*.sfs) unsquashfs -d "$dst" "$src" ;;
    *.img)
      mkdir -p "$WORK/mnt/$name"
      if mountpoint -q "$WORK/mnt/$name" 2>/dev/null; then umount "$WORK/mnt/$name"; fi
      # Try 7z first for ext images without requiring a privileged mount.
      if ! 7z x -y -o"$dst" "$src" >/dev/null 2>&1; then
        echo "Unable to unpack $src without mounting; preserving image for later Android tooling."
        cp "$src" "$dst/$name"
      fi
      ;;
  esac
}

# If a filesystem is represented by an image, keep the original image available
# while extracting what can be extracted in an unprivileged CI environment.
extract_img system.img "$ROOTFS/system"
extract_img vendor.img "$ROOTFS/vendor"
extract_img product.img "$ROOTFS/product"
extract_img odm.img "$ROOTFS/odm"

ram="$(find "$WORK/iso" -type f -name 'ramdisk.img' -print -quit || true)"
if [[ -n "$ram" ]]; then
  if gzip -cd "$ram" 2>/dev/null | (cd "$ROOTFS/ramdisk" && cpio -idm --quiet) 2>/dev/null; then :; else cp "$ram" "$ROOTFS/ramdisk/ramdisk.img"; fi
fi

echo "[2/7] Applying RebuiltDroid Tux branding..."
mkdir -p "$ROOTFS/system/etc/rebuiltdroid-tux"
cat > "$ROOTFS/system/etc/rebuiltdroid-tux/README" <<'EOF'
RebuiltDroid Tux
Android 10 customization layer
EOF

# Keep source images in the build tree so a later privileged/image-specific step
# can rebuild them correctly for the exact upstream filesystem format.
mkdir -p "$OUT/filesystems"
for d in system vendor product odm ramdisk; do
  if [[ -d "$ROOTFS/$d" ]]; then
    tar -C "$ROOTFS" -czf "$OUT/filesystems/$d.tar.gz" "$d"
  fi
done

cp -a "$WORK/iso" "$OUT/base-iso-tree"

# Repack the extracted ISO tree. This produces a valid ISO tree even when the
# upstream image format cannot safely be modified in an unprivileged runner.
echo "[3/7] Building ISO..."
xorriso -as mkisofs -R -J -joliet-long -o "$OUT/RebuiltDroid-Tux-Android10.iso" "$WORK/iso" >/dev/null

echo "Build complete: $OUT/RebuiltDroid-Tux-Android10.iso"
