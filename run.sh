#!/bin/bash
set -u

cd "$(dirname "$0")" || exit 1

./1-build-secure-v2.sh || exit 1

# The cold ceremony happens here: scan the QR above, sign, photograph the
# signed QR, and wait for the photo to appear in the shared mount.
echo
read -rp "signed QR photographed? [enter] "

HEX=$(./2-decode-pixel-v2.sh) || exit 1

exec ./3-broadcast-v2.sh "$HEX"
