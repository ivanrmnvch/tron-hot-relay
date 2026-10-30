#!/bin/bash
set -u

export TZ=UTC
NETWORK=${NETWORK:-tron:3448148188}   # NETWORK=tron:728126428 for mainnet
FILE=${1:-signed.hex}

# A run that stops at the dry-run or at the prompt never reaches the redirect
# below, so the previous run's txID would survive in the file.
rm -f broadcast.json

# Checks signatures, threshold and expiration locally. Nothing is sent, and a
# transaction that could not succeed never reaches the node.
wallet-cli tx broadcast --file "$FILE" --dry-run --network "$NETWORK" || exit 1

echo
read -rp "broadcast? [y/N] " OK
[ "$OK" = "y" ] || { echo "cancelled"; exit 1; }

wallet-cli tx broadcast --file "$FILE" --network "$NETWORK" -o json > broadcast.json \
  || { cat broadcast.json; exit 1; }

TXID=$(jq -r '.data.txId' broadcast.json)
echo "txID $TXID"

# Branch on data.state, never on the exit code: a transaction that went through
# and reverted is a successful command with a failed transaction.
STATE=unknown
for ((i = 0; i < 20; i++)); do
  sleep 3
  STATE=$(wallet-cli tx status --txid "$TXID" --network "$NETWORK" -o json | jq -r '.data.state')
  echo "  $STATE"
  case "$STATE" in
    confirmed) exit 0 ;;
    failed)    exit 1 ;;
  esac
done

# pending and not_found at the deadline are an unknown outcome, not a failure.
echo "still '$STATE' — outcome UNKNOWN. Do not resend; reconcile the txid first."
exit 1
