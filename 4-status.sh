#!/bin/bash
set -u

NETWORK=${NETWORK:-tron:3448148188}   # NETWORK=tron:728126428 for mainnet
TXID=${1:?usage: 4-status.sh <txid>}

# Branch on data.state, never on the exit code: a transaction that went through
# and reverted is a successful command with a failed transaction.
STATE=unknown
for ((i = 0; i < 20; i++)); do
  sleep 3
  status=$(wallet-cli tx status --txid "$TXID" --network "$NETWORK" -o json)
  STATE=${status#*'"state":"'}
  STATE=${STATE%%'"'*}
  echo "  $STATE"
  case "$STATE" in
    confirmed) exit 0 ;;
    failed)    exit 1 ;;
  esac
done

# pending and not_found at the deadline are an unknown outcome, not a failure.
echo "still '$STATE' — outcome UNKNOWN. Do not resend; reconcile the txid first."
exit 1
