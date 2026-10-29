#!/bin/bash
set -u

NETWORK=${NETWORK:-tron:3448148188}   # NETWORK=tron:728126428 for mainnet
TOKEN=USDT
EXPIRATION=600000          # 10 minutes

read -erp "From (account label): " FROM
read -erp "To (contact or address): " TO
read -erp "Amount ($TOKEN): " AMOUNT
[ -n "$FROM" ] && [ -n "$TO" ] && [ -n "$AMOUNT" ] || { echo "empty input"; exit 1; }

rm -f build.json unsigned.hex

wallet-cli tx send \
  --account "$FROM" --to "$TO" --amount "$AMOUNT" --token "$TOKEN" \
  --build-only --expiration "$EXPIRATION" \
  --network "$NETWORK" -o json > build.json || { cat build.json; exit 1; }

HEX=$(jq -r '.data.hex' build.json)
printf '%s' "${HEX^^}" > unsigned.hex        # ^^ uppercases: denser QR

jq -r '.data | "\(.token) \(.rawAmount) -> \(.to)
contract \(.contract)
txID     \(.tx.txID)
expires  \(.tx.raw_data.expiration / 1000 | floor | todate)"' build.json
echo

qrencode -t ANSIUTF8 -l M -m 2 -r unsigned.hex
