#!/usr/bin/env bash
set -euo pipefail
BASE_ISO="${BASE_ISO:-android10.iso}"
WORK="${WORK:-$PWD/work-package-check}"
TREE="$WORK/iso"
SYSTEM="$WORK/system"
RAW_IMG="$WORK/system.raw.img"
MOUNT="$WORK/mnt-system"
for t in xorriso unsquashfs find grep file mount umount; do command -v "$t" >/dev/null 2>&1 || { echo "Missing required tool: $t" >&2; exit 1; }; done
rm -rf "$WORK"
mkdir -p "$TREE" "$SYSTEM" "$MOUNT"
[[ -f "$BASE_ISO" ]] || { echo "ERROR: $BASE_ISO not found" >&2; exit 2; }
echo "[1/6] Extracting ISO..."
xorriso -osirrox on -indev "$BASE_ISO" -extract / "$TREE" >/dev/null
SYSTEM_SFS="$(find "$TREE" -type f \( -iname 'system.sfs' -o -iname 'system.squashfs' \) -print -quit)"
[[ -n "$SYSTEM_SFS" ]] || { echo "ERROR: system.sfs/system.squashfs not found" >&2; exit 3; }
echo "Found system filesystem: ${SYSTEM_SFS#"$TREE"/}"
file "$SYSTEM_SFS"
echo "[2/6] Extracting system.sfs..."
unsquashfs -d "$SYSTEM" "$SYSTEM_SFS" >/dev/null
if [[ -f "$SYSTEM/system.img" ]]; then
  IMG="$SYSTEM/system.img"
elif [[ -f "$SYSTEM/system/system.img" ]]; then
  IMG="$SYSTEM/system/system.img"
else
  echo "ERROR: system.sfs does not contain system.img" >&2
  find "$SYSTEM" -maxdepth 3 -type f -print | sort | head -100 >&2
  exit 4
fi
file "$IMG"
echo "[3/6] Preparing Android system image..."
if file "$IMG" | grep -qi 'Android sparse image'; then
  command -v simg2img >/dev/null 2>&1 || { echo "ERROR: simg2img is required for sparse system.img" >&2; exit 5; }
  simg2img "$IMG" "$RAW_IMG"
else
  cp "$IMG" "$RAW_IMG"
fi
echo "[4/6] Mounting Android /system image..."
sudo mount -o loop,ro "$RAW_IMG" "$MOUNT"
cleanup() { sudo umount "$MOUNT" 2>/dev/null || true; }
trap cleanup EXIT
ANDROID_SYSTEM="$MOUNT"
[[ -f "$ANDROID_SYSTEM/framework/framework.jar" ]] || { echo "ERROR: framework.jar missing from system.img" >&2; exit 6; }
echo "Android /system tree: $ANDROID_SYSTEM"
echo "[5/6] Checking framework/runtime..."
for f in \
  "$ANDROID_SYSTEM/framework/framework.jar" \
  "$ANDROID_SYSTEM/bin/app_process" \
  "$ANDROID_SYSTEM/bin/servicemanager"; do
  [[ -e "$f" ]] || { echo "ERROR: missing $f" >&2; exit 7; }
done
if command -v strings >/dev/null 2>&1; then
  if strings "$ANDROID_SYSTEM/framework/framework.jar" 2>/dev/null | grep -Eq 'PackageManagerService|com/android/server/pm'; then
    echo "PackageManagerService references found in framework.jar."
  else
    echo "WARNING: PackageManagerService references were not found by strings."
  fi
fi
echo "[6/6] Checking Android init/service configuration..."
if [[ -d "$ANDROID_SYSTEM/etc/init" || -f "$ANDROID_SYSTEM/etc/init/hw/init.rc" ]]; then
  echo "Android init configuration present."
else
  echo "WARNING: expected Android init configuration was not found."
fi
echo "Package Manager static verification complete."
