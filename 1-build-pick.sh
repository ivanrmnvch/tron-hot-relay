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

# ── sender ────────────────────────────────────────────────────────────────
LIST=$(wallet-cli list -o json)
mapfile -t ACC_LABEL < <(jq -r '.data[].label' <<<"$LIST")
mapfile -t ACC_TYPE  < <(jq -r '.data[].type'  <<<"$LIST")
mapfile -t ACC_ADDR  < <(jq -r '.data[].addresses.tron // "-"' <<<"$LIST")
[ ${#ACC_LABEL[@]} -gt 0 ] || { echo "no accounts"; exit 1; }

NW=0; TW=0
for i in "${!ACC_LABEL[@]}"; do
  [ ${#ACC_LABEL[i]} -gt $NW ] && NW=${#ACC_LABEL[i]}
  [ ${#ACC_TYPE[i]}  -gt $TW ] && TW=${#ACC_TYPE[i]}
done

section "SENDER"
for i in "${!ACC_LABEL[@]}"; do
  printf '  %d   %-*s   %-*s   %s\n' $((i+1)) "$NW" "${ACC_LABEL[i]}" "$TW" "${ACC_TYPE[i]}" "${ACC_ADDR[i]}"
done
echo
read -erp "  number or label: " ANS

FROM=$ANS; FROM_ADDR=""
if [[ "$ANS" =~ ^[0-9]+$ ]]; then
  [ ${#ANS} -le 9 ] && [ "$ANS" -ge 1 ] && [ "$ANS" -le ${#ACC_LABEL[@]} ] || { echo "  number out of range: $ANS"; exit 1; }
  FROM=${ACC_LABEL[ANS-1]}; FROM_ADDR=${ACC_ADDR[ANS-1]}
else
  for i in "${!ACC_LABEL[@]}"; do
    [ "${ACC_LABEL[i]}" = "$ANS" ] && { FROM_ADDR=${ACC_ADDR[i]}; break; }
  done
fi
[ -n "$FROM_ADDR" ] || FROM_ADDR=$FROM     # an address typed straight in

# ── recipient ─────────────────────────────────────────────────────────────
BOOK=$(wallet-cli contact list -o json)
mapfile -t CON_NAME < <(jq -r '.data.contacts[].name'    <<<"$BOOK")
mapfile -t CON_ADDR < <(jq -r '.data.contacts[].address' <<<"$BOOK")

CW=0
for n in ${CON_NAME[@]+"${CON_NAME[@]}"}; do [ ${#n} -gt $CW ] && CW=${#n}; done

section "RECIPIENT"
for i in ${CON_NAME[@]+"${!CON_NAME[@]}"}; do
  printf '  %d   %-*s   %s\n' $((i+1)) "$CW" "${CON_NAME[i]}" "${CON_ADDR[i]}"
done
echo
read -erp "  number, contact or address: " ANS

TO_NAME=""; TO=""
if [[ "$ANS" =~ ^[0-9]+$ ]]; then
  [ ${#ANS} -le 9 ] && [ "$ANS" -ge 1 ] && [ "$ANS" -le ${#CON_ADDR[@]} ] || { echo "  number out of range: $ANS"; exit 1; }
  TO_NAME=${CON_NAME[ANS-1]}; TO=${CON_ADDR[ANS-1]}
else
  for i in ${CON_NAME[@]+"${!CON_NAME[@]}"}; do
    [ "${CON_NAME[i]}" = "$ANS" ] && { TO_NAME=$ANS; TO=${CON_ADDR[i]}; break; }
  done
fi
[ -n "$TO" ] || TO=$ANS                    # an address typed straight in

# ── amount ────────────────────────────────────────────────────────────────
section "AMOUNT"
read -erp "  $TOKEN: " AMOUNT
[ -n "$FROM" ] && [ -n "$TO" ] && [ -n "$AMOUNT" ] || { echo "  empty input"; exit 1; }

# ── review ────────────────────────────────────────────────────────────────
section "REVIEW"
row "From"  "$FROM_ADDR" "$([ "$FROM" != "$FROM_ADDR" ] && echo "$FROM")"
row "To"    "$TO"        "$TO_NAME"
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

# ── transaction ───────────────────────────────────────────────────────────
# The table below is a decoded view; the QR carries the bytes. Prove the two
# agree as far as is possible here. The third check — that raw_data re-encodes
# to exactly these bytes — needs a protobuf encoder and runs on the signer.
RAWHEX=$(jq -r '.data.tx.raw_data_hex' build.json)
case "$HEX" in
  *"$RAWHEX"*) ;;
  *) echo "  raw_data_hex is not inside the transaction hex"; exit 1 ;;
esac
[ "$(printf '%s' "$RAWHEX" | xxd -r -p | sha256sum | cut -d' ' -f1)" = "$TXID" ] || {
  echo "  txID is not sha256(raw_data_hex)"; exit 1
}

# The sender lives inside the transaction as a 41-hex owner_address.
# encoding convert is local — no node call — and gives back base58.
FROM_TX=$(wallet-cli encoding convert \
  "$(jq -r '.data.tx.raw_data.contract[0].parameter.value.owner_address' build.json)" \
  -o json | jq -r '.data.tron')
[ -n "$FROM_TX" ] && [ "$FROM_TX" != "null" ] || {
  echo "  cannot read owner_address from build.json"; exit 1
}

section "TRANSACTION"
row "From"  "$FROM_TX"
row "To"    "$TO_ADDR"
printf '  %-9s %s %s\n' "Amount" "$(money "$RAW" "$DEC")" "$SYMBOL"
printf '  %-9s %s\n'    "Raw"    "$RAW"
row "Token" "$CONTRACT" "$SYMBOL"
printf '  %-9s %s\n'              "txID"    "$TXID"
printf '  %-9s %s  (in %dm)\n'    "Expires" "$EXPIRES" $(( SECS / 60 ))

section "QR"
qrencode -t ANSIUTF8 -l M -m 2 -r unsigned.hex
