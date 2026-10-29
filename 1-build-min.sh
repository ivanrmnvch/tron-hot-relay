#!/bin/bash
set -u

NETWORK=${NETWORK:-tron:3448148188}   # NETWORK=tron:728126428 for mainnet
TOKEN=USDT
EXPIRATION=600000                     # 10 minutes

read -rp "from: "   FROM
read -rp "to: "     TO
read -rp "amount: " AMOUNT

# A failed build must not leave the previous run's hex in place: that is how
# you end up photographing a transaction you did not just build.
rm -f unsigned.hex

wallet-cli tx send \
  --account "$FROM" --to "$TO" --amount "$AMOUNT" --token "$TOKEN" \
  --build-only --expiration "$EXPIRATION" \
  --network "$NETWORK" -o json > build.json || { cat build.json; exit 1; }

HEX=$(jq -r '.data.hex' build.json)
printf '%s' "${HEX^^}" > unsigned.hex   # uppercase hex halves the QR version

qrencode -t ANSIUTF8 -l M -m 2 -r unsigned.hex
