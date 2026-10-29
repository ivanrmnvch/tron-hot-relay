#!/bin/bash
set -u

NETWORK=${NETWORK:-tron:3448148188}   # NETWORK=tron:728126428 for mainnet
TOKEN=USDT
EXPIRATION=600000          # 10 minutes

menu() { local i=1 r; for r in "$@"; do printf "  %d) %s\n" "$i" "$r"; i=$((i+1)); done; }

# label, address, optional friendly name. TRON addresses are all 34 chars,
# so the address column lines up without padding it.
row() { printf '%-10s %s%s\n' "$1" "$2" "${3:+  ($3)}"; }

# raw integer -> decimal string, by shifting the string. Never by division:
# a float silently loses the low digits of an 18-decimal token.
money() {
  local raw=$1 d=$2 int frac
  [ "$d" -eq 0 ] && { echo "$raw"; return; }
  while [ ${#raw} -le "$d" ]; do raw="0$raw"; done
  int=${raw::-$d}; frac=${raw: -$d}
  frac=${frac%"${frac##*[!0]}"}
  [ -n "$frac" ] && echo "$int.$frac" || echo "$int"
}

LIST=$(wallet-cli list -o json)
mapfile -t ACC_LABEL < <(jq -r '.data[].label' <<<"$LIST")
mapfile -t ACC_ADDR  < <(jq -r '.data[].addresses.tron // "-"' <<<"$LIST")
mapfile -t ACC_SHOW  < <(jq -r '.data[] | "\(.label)  [\(.type)]  \(.addresses.tron // "-")"' <<<"$LIST")
[ ${#ACC_LABEL[@]} -gt 0 ] || { echo "no accounts"; exit 1; }

echo "Accounts:"
menu "${ACC_SHOW[@]}"
read -erp "From (number or label): " ANS
FROM=$ANS; FROM_ADDR=""
if [[ "$ANS" =~ ^[0-9]+$ ]]; then
  [ "$ANS" -ge 1 ] && [ "$ANS" -le ${#ACC_LABEL[@]} ] || { echo "number out of range: $ANS"; exit 1; }
  FROM=${ACC_LABEL[ANS-1]}; FROM_ADDR=${ACC_ADDR[ANS-1]}
else
  for i in "${!ACC_LABEL[@]}"; do
    [ "${ACC_LABEL[i]}" = "$ANS" ] && { FROM_ADDR=${ACC_ADDR[i]}; break; }
  done
fi
[ -n "$FROM_ADDR" ] || FROM_ADDR=$FROM     # an address typed straight in

BOOK=$(wallet-cli contact list -o json)
mapfile -t CON_NAME < <(jq -r '.data.contacts[].name'    <<<"$BOOK")
mapfile -t CON_ADDR < <(jq -r '.data.contacts[].address' <<<"$BOOK")
mapfile -t CON_SHOW < <(jq -r '.data.contacts[] | "\(.name)  \(.address)"' <<<"$BOOK")

echo "Contacts:"
menu "${CON_SHOW[@]}"
read -erp "To (number, contact name or address): " ANS
TO_NAME=""; TO=""
if [[ "$ANS" =~ ^[0-9]+$ ]]; then
  [ "$ANS" -ge 1 ] && [ "$ANS" -le ${#CON_ADDR[@]} ] || { echo "number out of range: $ANS"; exit 1; }
  TO_NAME=${CON_NAME[ANS-1]}; TO=${CON_ADDR[ANS-1]}
else
  for i in "${!CON_NAME[@]}"; do
    [ "${CON_NAME[i]}" = "$ANS" ] && { TO_NAME=$ANS; TO=${CON_ADDR[i]}; break; }
  done
fi
[ -n "$TO" ] || TO=$ANS                    # an address typed straight in

read -erp "Amount ($TOKEN): " AMOUNT
[ -n "$FROM" ] && [ -n "$TO" ] && [ -n "$AMOUNT" ] || { echo "empty input"; exit 1; }

echo
row "From"  "$FROM_ADDR" "$([ "$FROM" != "$FROM_ADDR" ] && echo "$FROM")"
row "To"    "$TO"        "$TO_NAME"
printf '%-10s %s %s\n' "Amount" "$AMOUNT" "$TOKEN"
echo
read -erp "Build? [y/N] " OK
[ "$OK" = "y" ] || { echo "cancelled"; exit 1; }

rm -f build.json unsigned.hex

wallet-cli tx send \
  --account "$FROM" --to "$TO" --amount "$AMOUNT" --token "$TOKEN" \
  --build-only --expiration "$EXPIRATION" \
  --network "$NETWORK" -o json > build.json || { cat build.json; exit 1; }

HEX=$(jq -r '.data.hex' build.json)
printf '%s' "${HEX^^}" > unsigned.hex        # ^^ uppercases: denser QR

IFS=$'\t' read -r RAW DEC TO_ADDR CONTRACT SYMBOL TXID EXPIRES SECS < <(
  jq -r '.data | [.rawAmount, .decimals, .to, .contract, .token, .tx.txID,
                  (.tx.raw_data.expiration / 1000 | floor | todate),
                  (.tx.raw_data.expiration / 1000 - now | floor)] | @tsv' build.json
)

echo
printf '%-10s %s %s\n' "Amount" "$(money "$RAW" "$DEC")" "$SYMBOL"
printf '%-10s %s\n'    "Raw"    "$RAW"
row "To"    "$TO_ADDR"
row "Token" "$CONTRACT" "$SYMBOL"
printf '%-10s %s\n'              "txID"    "$TXID"
printf '%-10s %s  (in %dm)\n'    "Expires" "$EXPIRES" $(( SECS / 60 ))
echo

qrencode -t ANSIUTF8 -l M -m 2 -r unsigned.hex
