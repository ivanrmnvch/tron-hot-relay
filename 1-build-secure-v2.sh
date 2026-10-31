#!/bin/bash

wallet-cli list

read -rp "Enter sender: " sender

wallet-cli contact list

read -rp "Enter recipient: " recipient
read -rp "Enter amount: " amount

NETWORK=tron:3448148188
TOKEN=USDT
EXPIRATION=600000

json=$(wallet-cli tx send \
  --account "$sender" \
  --to "$recipient" \
  --amount "$amount" \
  --token "$TOKEN" \
  --build-only --expiration "$EXPIRATION" \
  --network "$NETWORK" -o json) || exit 1

if [[ "$json" == *'"success":true'* ]]; then
    hex=${json#*'"hex":"'}

    hex=${hex%%'"'*}

    [[ "$hex" =~ ^[0-9a-f]+$ ]] || { echo "Error: bad hex" >&2; exit 1; }

    printf '%s' "${hex^^}" | qrencode -t ANSIUTF8 -l M -m 2
else
    msg=${json#*'"message":"'}

    msg=${msg%%'"'*}

    echo "Error: $msg" >&2
    exit 1
fi
