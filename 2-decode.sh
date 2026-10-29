#!/bin/bash
set -u

PHOTO=${1:-}
[ -n "$PHOTO" ] || { echo "usage: $0 <photo.jpg>"; exit 1; }
[ -s "$PHOTO" ] || { echo "not found: $PHOTO"; exit 1; }

HEX=$(zbarimg --raw -q "$PHOTO" | tr -d '[:space:]')
[ -n "$HEX" ] || { echo "no QR decoded in $PHOTO"; exit 1; }

printf '%s' "$HEX" > ./signed.hex
echo "$PHOTO -> ./signed.hex"
