#!/bin/bash
set -u

export TZ=UTC
NETWORK=tron:3448148188
TOKEN=USDT
EXPIRATION=600000          # 10 minutes

LIST=$(wallet-cli list -o json)
mapfile -t ACC_LABEL < <(jq -r '.data[].label' <<<"$LIST")
mapfile -t ACC_SHOW  < <(jq -r '.data[] | "\(.label)  [\(.type)]  \(.addresses.tron // "-")"' <<<"$LIST")
[ ${#ACC_LABEL[@]} -gt 0 ] || { echo "no accounts"; exit 1; }

echo "Accounts:"
PS3="From (number): "
select PICK in "${ACC_SHOW[@]}"; do [ -n "${PICK:-}" ] && break; done
FROM=${ACC_LABEL[REPLY-1]}

BOOK=$(wallet-cli contact list -o json)
mapfile -t CON_ADDR < <(jq -r '.data.contacts[].address' <<<"$BOOK")
mapfile -t CON_SHOW < <(jq -r '.data.contacts[] | "\(.name)  \(.address)"' <<<"$BOOK")

MANUAL="enter address manually"
echo "Contacts:"
PS3="To (number): "
select PICK in "${CON_SHOW[@]}" "$MANUAL"; do [ -n "${PICK:-}" ] && break; done
if [ "$PICK" = "$MANUAL" ]; then
  read -rp "To (address): " TO
else
  TO=${CON_ADDR[REPLY-1]}
fi

read -rp "Amount ($TOKEN): " AMOUNT
[ -n "$TO" ] && [ -n "$AMOUNT" ] || { echo "empty input"; exit 1; }

echo
echo "$FROM -> $TO : $AMOUNT $TOKEN"
read -rp "Build? [y/N] " OK
[ "$OK" = "y" ] || { echo "cancelled"; exit 1; }

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
