#!/usr/bin/env bash
set -euo pipefail

# RebuiltDroid Tux - static verification for Android's real Package Manager
# framework/service stack. This deliberately does NOT add a fake `cmd package`
# shim; the goal is to catch missing Android framework pieces in the ISO.

BASE_ISO="${BASE_ISO:-android10.iso}"
WORK="${WORK:-$PWD/work-package-check}"
TREE="$WORK/iso"
SYSTEM="$WORK/system"

for t in xorriso unsquashfs find grep; do
  command -v "$t" >/dev/null 2>&1 || { echo "Missing required tool: $t" >&2; exit 1; }
done

rm -rf "$WORK"
mkdir -p "$TREE" "$SYSTEM"

[[ -f "$BASE_ISO" ]] || { echo "ERROR: $BASE_ISO not found" >&2; exit 2; }

echo "[1/4] Extracting ISO..."
xorriso -osirrox on -indev "$BASE_ISO" -extract / "$TREE" >/dev/null

SYSTEM_SFS="$(find "$TREE" -type f \( -iname 'system.sfs' -o -iname 'system.squashfs' \) -print -quit)"
[[ -n "$SYSTEM_SFS" ]] || { echo "ERROR: system.sfs/system.squashfs not found" >&2; exit 3; }

echo "[2/4] Extracting Android system filesystem..."
unsquashfs -d "$SYSTEM" "$SYSTEM_SFS" >/dev/null

# These are core pieces used by Android's system_server/runtime startup.
echo "[3/4] Checking framework/runtime..."
for f in \
  "$SYSTEM/system/framework/framework.jar" \
  "$SYSTEM/system/bin/app_process" \
  "$SYSTEM/system/bin/servicemanager"; do
  [[ -e "$f" ]] || { echo "ERROR: missing $f" >&2; exit 4; }
done

if command -v strings >/dev/null 2>&1; then
  if strings "$SYSTEM/system/framework/framework.jar" 2>/dev/null | grep -Eq 'PackageManagerService|com/android/server/pm'; then
    echo "PackageManagerService references found in framework.jar."
  else
    echo "WARNING: PackageManagerService references were not found by strings."
    echo "The framework may use a different packaging/optimization layout."
  fi
fi

echo "[4/4] Checking Android init/service configuration..."
if [[ -d "$SYSTEM/system/etc/init" || -f "$SYSTEM/system/etc/init/hw/init.rc" ]]; then
  echo "Android init configuration present."
else
  echo "WARNING: expected Android init configuration was not found."
fi

echo "Package Manager static verification complete."
