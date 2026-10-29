#!/bin/bash
set -u

export TZ=UTC
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
  --network "$NETWORK" -o json > build.json

jq -e '.success' build.json >/dev/null || {
  jq -r '.error | "\(.code): \(.message)"' build.json 2>/dev/null || cat build.json
  exit 1
}

# One pass over the file; @tsv keeps the fields apart, IFS splits them back.
IFS=$'\t' read -r HEX TOKEN AMOUNT TO CONTRACT TXID EXPIRES < <(
  jq -r '.data | [.hex, .token, .rawAmount, .to, .contract, .tx.txID,
                  (.tx.raw_data.expiration / 1000 | floor)] | @tsv' build.json
)

# A missing .hex would otherwise reach the QR as the four letters "NULL".
[ -n "$HEX" ] || { echo "no transaction hex in build.json"; exit 1; }

printf '%s' "${HEX^^}" > unsigned.hex        # ^^ uppercases: denser QR, no tr

printf '%s %s -> %s\ncontract %s\ntxID     %s\n' "$TOKEN" "$AMOUNT" "$TO" "$CONTRACT" "$TXID"
date -u -d "@$EXPIRES" '+expires  %Y-%m-%d %H:%M UTC'
echo

qrencode -t ANSIUTF8 -l M -m 2 -r unsigned.hex
