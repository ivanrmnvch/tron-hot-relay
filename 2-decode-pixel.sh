#!/bin/bash
# Pixel 9, Linux development environment: Debian in a VM on AVF, not a chroot.
# Android storage reaches the VM only through the shared mount at /mnt/shared.
# DCIM shows up there from Android 16 QPR2 on; older builds expose Download only.
set -u

DIR=${1:-/mnt/shared/DCIM/Camera}

[ -d "$DIR" ] || {
  echo "not a directory: $DIR"
  exit 1
}

# Only *.jpg: with RAW on, the camera writes a .RAW-02.ORIGINAL.dng beside
# every .RAW-01.jpg, and zbarimg cannot read dng.
PHOTO=$(ls -t "$DIR"/*.jpg 2>/dev/null | head -1)
[ -n "$PHOTO" ] || { echo "no .jpg in $DIR"; exit 1; }

HEX=$(zbarimg --raw -q "$PHOTO" | tr -d '[:space:]')
[ -n "$HEX" ] || { echo "no QR decoded in $(basename "$PHOTO")"; exit 1; }

printf '%s' "$HEX" > ./signed.hex
echo "$(basename "$PHOTO") -> ./signed.hex"
