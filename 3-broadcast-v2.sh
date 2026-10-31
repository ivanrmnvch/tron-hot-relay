#!/bin/bash
set -u

NETWORK=tron:3448148188   # NETWORK=tron:728126428 for mainnet
HEX=${1:?usage: 3-broadcast-v2.sh <signed-hex>}

# Checks signatures, threshold and expiration locally. Nothing is sent, and a
# transaction that could not succeed never reaches the node.
wallet-cli tx broadcast --hex "$HEX" --dry-run --network "$NETWORK" || exit 1

echo
read -rp "broadcast? [y/N] " OK
[ "$OK" = "y" ] || { echo "cancelled"; exit 1; }

json=$(wallet-cli tx broadcast --hex "$HEX" --network "$NETWORK" -o json) \
  || { echo "$json" >&2; exit 1; }

TXID=${json#*'"txId":"'}
TXID=${TXID%%'"'*}

# A tron txid is 64 hex chars. Anything else means the reply carried no txid
# (or the format changed), and polling garbage would turn a failure into
# twenty rounds of "unknown".
[[ "$TXID" =~ ^[0-9a-f]{64}$ ]] || { echo "$json" >&2; exit 1; }
echo "txID $TXID"

exec "$(dirname "$0")/4-status.sh" "$TXID"
