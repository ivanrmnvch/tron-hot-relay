#!/bin/bash
set -u

export TZ=UTC
NETWORK=${NETWORK:-tron:3448148188}   # NETWORK=tron:728126428 for mainnet
TOKEN=USDT
EXPIRATION=600000          # 10 minutes

menu() {                   # print a numbered list
  local i=1 row
  for row in "$@"; do printf "  %d) %s\n" "$i" "$row"; i=$((i+1)); done
}

# $1 answer, $2 list size, $3 array name -> sets RESOLVED.
# Not a command substitution: exit inside $( ) would only kill the subshell.
resolve() {
  local ans=$1 size=$2
  local -n arr=$3
  if [[ "$ans" =~ ^[0-9]+$ ]]; then
    [ "$ans" -ge 1 ] && [ "$ans" -le "$size" ] || { echo "number out of range: $ans" >&2; return 1; }
    RESOLVED=${arr[ans-1]}
  else
    RESOLVED=$ans
  fi
}

LIST=$(wallet-cli list -o json)
mapfile -t ACC_LABEL < <(jq -r '.data[].label' <<<"$LIST")
mapfile -t ACC_SHOW  < <(jq -r '.data[] | "\(.label)  [\(.type)]  \(.addresses.tron // "-")"' <<<"$LIST")
[ ${#ACC_LABEL[@]} -gt 0 ] || { echo "no accounts"; exit 1; }

echo "Accounts:"
menu "${ACC_SHOW[@]}"
read -erp "From (number or label): " ANS
resolve "$ANS" "${#ACC_LABEL[@]}" ACC_LABEL || exit 1
FROM=$RESOLVED

BOOK=$(wallet-cli contact list -o json)
mapfile -t CON_ADDR < <(jq -r '.data.contacts[].address' <<<"$BOOK")
mapfile -t CON_SHOW < <(jq -r '.data.contacts[] | "\(.name)  \(.address)"' <<<"$BOOK")

echo "Contacts:"
menu "${CON_SHOW[@]}"
read -erp "To (number, contact name or address): " ANS
resolve "$ANS" "${#CON_ADDR[@]}" CON_ADDR || exit 1
TO=$RESOLVED
read -erp "  confirm '$TO' — Enter to accept, or retype: " FIX
[ -n "$FIX" ] && TO=$FIX

read -erp "Amount ($TOKEN): " AMOUNT
[ -n "$FROM" ] && [ -n "$TO" ] && [ -n "$AMOUNT" ] || { echo "empty input"; exit 1; }

echo
echo "$FROM -> $TO : $AMOUNT $TOKEN"
read -erp "Build? [y/N] " OK
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
