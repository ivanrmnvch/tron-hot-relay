#!/bin/bash
set -u

export TZ=UTC
NETWORK=${NETWORK:-tron:3448148188}   # NETWORK=tron:728126428 for mainnet
FILE=${1:-signed.hex}

[ -s "$FILE" ] || { echo "not found: $FILE"; exit 1; }

# 1. local validation: signatures, threshold, expiration. Nothing is sent.
wallet-cli tx broadcast --file "$FILE" --dry-run --network "$NETWORK" || {
  echo "dry-run rejected it, nothing was sent"
  exit 1
}

echo
read -rp "Broadcast? [y/N] " OK
[ "$OK" = "y" ] || { echo "cancelled"; exit 1; }

rm -f broadcast.json
wallet-cli tx broadcast --file "$FILE" --network "$NETWORK" -o json > broadcast.json

jq -e '.success' broadcast.json >/dev/null || {
  jq -r '.error | "\(.code): \(.message)"' broadcast.json
  exit 1
}

TXID=$(jq -r '.data.txId' broadcast.json)
echo "txID $TXID"

# 2. poll. Branch on data.state, never on the exit code.
STATE=unknown
for _ in $(seq 1 20); do
  sleep 3
  STATE=$(wallet-cli tx status --txid "$TXID" --network "$NETWORK" -o json | jq -r '.data.state')
  echo "  $STATE"
  case "$STATE" in
    confirmed) exit 0 ;;
    failed)    exit 1 ;;
  esac
done

echo "still '$STATE' — outcome UNKNOWN. Do not resend; reconcile the txid first."
exit 1
