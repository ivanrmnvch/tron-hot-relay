#!/bin/bash
set -u

DIR=/mnt/shared/DCIM/Camera

# Only *.jpg: with RAW on, the camera writes a .RAW-02.ORIGINAL.dng beside
# every .RAW-01.jpg, and zbarimg cannot read dng.
PHOTO=$(ls -t "$DIR"/*.jpg | head -1)
[ -n "$PHOTO" ] || exit 1

HEX=$(zbarimg --raw -q "$PHOTO" | tr -d '[:space:]')

# The newest photo is not necessarily the signing QR: reject empty decodes and
# any other QR payload (URLs, text). The signer emits uppercase hex.
[[ "$HEX" =~ ^[0-9A-F]+$ ]] || { echo "no hex QR in $(basename "$PHOTO")" >&2; exit 1; }

# Which photo was picked goes to stderr; stdout carries only the hex, so the
# output can be passed straight to 3-broadcast-v2.sh.
echo "$(basename "$PHOTO")" >&2
printf '%s\n' "$HEX"
