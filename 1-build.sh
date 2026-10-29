#!/bin/bash
set -u

NETWORK=${NETWORK:-tron:3448148188}   # NETWORK=tron:728126428 for mainnet
TOKEN=USDT
EXPIRATION=600000          # 10 minutes
RULE_W=69                  # width of the QR at -m 2, so blocks line up with it

section() {                # block heading plus a rule to the edge
  local n=$(( RULE_W - ${#1} - 1 )); [ "$n" -lt 3 ] && n=3
  printf '\n%s %s\n' "$1" "$(printf '─%.0s' $(seq 1 "$n"))"
}

# label, address, optional friendly name. TRON addresses are all 34 chars,
# so the address column lines up without padding it.
row() { printf '  %-9s %s%s\n' "$1" "$2" "${3:+  ($3)}"; }

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

section "SENDER"
read -erp "  account label or address: " FROM

section "RECIPIENT"
read -erp "  contact or address: " TO

section "AMOUNT"
read -erp "  $TOKEN: " AMOUNT
[ -n "$FROM" ] && [ -n "$TO" ] && [ -n "$AMOUNT" ] || { echo "  empty input"; exit 1; }

section "REVIEW"
row "From" "$FROM"
row "To"   "$TO"
printf '  %-9s %s %s\n' "Amount" "$AMOUNT" "$TOKEN"
echo
read -erp "  build? [y/N] " OK
[ "$OK" = "y" ] || { echo "  cancelled"; exit 1; }

rm -f build.json unsigned.hex

wallet-cli tx send \
  --account "$FROM" --to "$TO" --amount "$AMOUNT" --token "$TOKEN" \
  --build-only --expiration "$EXPIRATION" \
  --network "$NETWORK" -o json > build.json || { cat build.json; exit 1; }

HEX=$(jq -r '.data.hex' build.json)
printf '%s' "${HEX^^}" > unsigned.hex      # ^^ uppercases: denser QR

IFS=$'\t' read -r RAW DEC TO_ADDR CONTRACT SYMBOL TXID EXPIRES SECS < <(
  jq -r '.data | [.rawAmount, .decimals, .to, .contract, .token, .tx.txID,
                  (.tx.raw_data.expiration / 1000 | floor | todate),
                  (.tx.raw_data.expiration / 1000 - now | floor)] | @tsv' build.json
)

section "TRANSACTION"
printf '  %-9s %s %s\n' "Amount" "$(money "$RAW" "$DEC")" "$SYMBOL"
printf '  %-9s %s\n'    "Raw"    "$RAW"
row "To"    "$TO_ADDR"
row "Token" "$CONTRACT" "$SYMBOL"
printf '  %-9s %s\n'           "txID"    "$TXID"
printf '  %-9s %s  (in %dm)\n' "Expires" "$EXPIRES" $(( SECS / 60 ))

section "QR"
qrencode -t ANSIUTF8 -l M -m 2 -r unsigned.hex
