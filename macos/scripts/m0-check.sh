#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ADB="$PWD/Resources/adb"
"$ADB" devices -l
SERIAL="${1:-}"
if [[ -z "$SERIAL" ]]; then
  SERIAL="$("$ADB" devices | awk 'NR>1 && $2=="device" {print $1;exit}')"
fi
[[ -n "$SERIAL" ]] || { echo 'No authorized tablet. Unlock Android and allow USB debugging.'; exit 1; }
for PROP in ro.product.manufacturer ro.product.model ro.build.version.release ro.build.version.sdk; do
  printf '%s: ' "$PROP"
  "$ADB" -s "$SERIAL" shell getprop "$PROP"
done
"$ADB" -s "$SERIAL" shell ls -l /dev/uhid
