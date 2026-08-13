#!/usr/bin/env bash
set -euo pipefail

BASE_ISO="${BASE_ISO:-android10.iso}"
WORK="${WORK:-$PWD/work-package-check}"
TREE="$WORK/iso"
SYSTEM="$WORK/system"

for t in xorriso unsquashfs find grep file; do
  command -v "$t" >/dev/null 2>&1 || { echo "Missing required tool: $t" >&2; exit 1; }
done

rm -rf "$WORK"
mkdir -p "$TREE" "$SYSTEM"
[[ -f "$BASE_ISO" ]] || { echo "ERROR: $BASE_ISO not found" >&2; exit 2; }

echo "[1/5] Extracting ISO..."
xorriso -osirrox on -indev "$BASE_ISO" -extract / "$TREE" >/dev/null
SYSTEM_SFS="$(find "$TREE" -type f \( -iname 'system.sfs' -o -iname 'system.squashfs' \) -print -quit)"
[[ -n "$SYSTEM_SFS" ]] || { echo "ERROR: system.sfs/system.squashfs not found" >&2; exit 3; }

echo "Found system filesystem: ${SYSTEM_SFS#"$TREE"/}"
file "$SYSTEM_SFS"

echo "[2/5] Extracting Android system filesystem..."
unsquashfs -d "$SYSTEM" "$SYSTEM_SFS" >/dev/null

if [[ -d "$SYSTEM/framework" ]]; then
  ANDROID_SYSTEM="$SYSTEM"
elif [[ -d "$SYSTEM/system/framework" ]]; then
  ANDROID_SYSTEM="$SYSTEM/system"
else
  echo "ERROR: Could not locate Android /system tree." >&2
  echo "framework.jar candidates:" >&2
  find "$SYSTEM" -type f -name 'framework.jar' -print >&2
  exit 4
fi

echo "Android /system tree: $ANDROID_SYSTEM"
echo "[3/5] Checking framework/runtime..."
for f in \
  "$ANDROID_SYSTEM/framework/framework.jar" \
  "$ANDROID_SYSTEM/bin/app_process" \
  "$ANDROID_SYSTEM/bin/servicemanager"; do
  [[ -e "$f" ]] || { echo "ERROR: missing $f" >&2; exit 5; }
done

if command -v strings >/dev/null 2>&1; then
  if strings "$ANDROID_SYSTEM/framework/framework.jar" 2>/dev/null | grep -Eq 'PackageManagerService|com/android/server/pm'; then
    echo "PackageManagerService references found in framework.jar."
  else
    echo "WARNING: PackageManagerService references were not found by strings."
  fi
fi

echo "[4/5] Checking Android init/service configuration..."
if [[ -d "$ANDROID_SYSTEM/etc/init" || -f "$ANDROID_SYSTEM/etc/init/hw/init.rc" ]]; then
  echo "Android init configuration present."
else
  echo "WARNING: expected Android init configuration was not found."
fi

echo "[5/5] Package Manager static verification complete."
