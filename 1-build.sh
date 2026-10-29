#!/bin/bash
set -u

export TZ=UTC
NETWORK=tron:3448148188
TOKEN=USDT
EXPIRATION=600000          # 10 minutes

read -rp "From (account label): " FROM
read -rp "To (contact or address): " TO
read -rp "Amount ($TOKEN): " AMOUNT
[ -n "$FROM" ] && [ -n "$TO" ] && [ -n "$AMOUNT" ] || { echo "empty input"; exit 1; }

rm -f build.json unsigned.hex

wallet-cli tx send \
  --account "$FROM" --to "$TO" --amount "$AMOUNT" --token "$TOKEN" \
  --build-only --expiration "$EXPIRATION" \
  --network "$NETWORK" -o json > build.json

jq -e '.success' build.json >/dev/null || {
  jq -r '.error | "\(.code): \(.message)"' build.json
  exit 1
}

jq -r '.data.hex' build.json | tr -d '[:space:]' | tr 'a-f' 'A-F' > unsigned.hex

jq -r '.data | "\(.token) \(.rawAmount) -> \(.to)\ncontract \(.contract)\ntxID     \(.tx.txID)"' build.json
date -u -d "@$(( $(jq -r '.data.tx.raw_data.expiration' build.json) / 1000 ))" '+expires  %Y-%m-%d %H:%M UTC'
echo

# Can the sender pay? tx broadcast --dry-run does not check this on TRON.
bash "$(dirname "$0")/0-fee-check.sh" "$FROM" build.json || {
  echo
  echo "fee problem — fix it before signing, do not start the QR round trip"
  exit 1
}
echo

qrencode -t ANSIUTF8 -l M -m 2 -r unsigned.hex
