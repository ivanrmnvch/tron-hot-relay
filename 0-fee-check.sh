#!/bin/bash
# Can this account actually pay for the built transaction?
# TRON burns TRX for energy/bandwidth it cannot cover from frozen resources,
# and a transaction that runs out mid-execution still consumes the fee.
# tx broadcast --dry-run does NOT check this on TRON.
set -u

export TZ=UTC
NETWORK=${NETWORK:-tron:3448148188}   # NETWORK=tron:728126428 for mainnet
ACCOUNT=${1:-}
BUILD=${2:-build.json}

[ -n "$ACCOUNT" ] || { echo "usage: $0 <sender account> [build.json]"; exit 1; }
[ -s "$BUILD" ] || { echo "not found: $BUILD"; exit 1; }

TO=$(jq -r '.data.to // empty'                   "$BUILD")
CONTRACT=$(jq -r '.data.contract // empty'       "$BUILD")
NRG_NEED=$(jq -r '.data.fee.energy // 0'         "$BUILD")
NRG_PRICE=$(jq -r '.data.fee.energyPriceSun // 0' "$BUILD")
FEE_LIMIT=$(jq -r '.data.tx.raw_data.fee_limit // 0' "$BUILD")
HEXLEN=$(jq -r '.data.hex | length'              "$BUILD")

trx() { printf '%d.%06d' $(( $1 / 1000000 )) $(( $1 % 1000000 )); }

# --- recipient state: it drives the energy cost and is invisible in the amount
if [ -n "$TO" ]; then
  RINFO=$(wallet-cli account info --account "$TO" --network "$NETWORK" -o json)
  if [ "$(jq -r '.data.account.create_time // "null"' <<<"$RINFO")" = "null" ]; then
    echo "recipient  account does not exist on-chain (a TRX transfer would add a 1 TRX creation fee)"
  fi
  if [ -n "$CONTRACT" ]; then
    RBAL=$(wallet-cli token balance --contract "$CONTRACT" --account "$TO" \
             --network "$NETWORK" -o json | jq -r '.data.balance // "0"')
    if [ "$RBAL" = "0" ]; then
      echo "recipient  has never held this token -> fresh storage slot, roughly double the energy"
    else
      echo "recipient  already holds this token -> cheaper slot update"
    fi
  fi
fi

# --- sender resources
INFO=$(wallet-cli account info --account "$ACCOUNT" --network "$NETWORK" -o json)
jq -e '.success' <<<"$INFO" >/dev/null || { jq -r '.error.message' <<<"$INFO"; exit 1; }

BALANCE=$(jq -r '.data.account.balance // 0'                  <<<"$INFO")
NET_FREE=$(jq -r '.data.resources.bandwidth | .limit - .used' <<<"$INFO")
NRG_FREE=$(jq -r '.data.resources.energy    | .limit - .used' <<<"$INFO")

# signed size: unsigned bytes + 65-byte signature + protobuf overhead
NET_NEED=$(( HEXLEN / 2 + 70 ))

NRG_SHORT=$(( NRG_NEED > NRG_FREE ? NRG_NEED - NRG_FREE : 0 ))
NET_SHORT=$(( NET_NEED > NET_FREE ? NET_NEED - NET_FREE : 0 ))
NRG_BURN=$(( NRG_SHORT * NRG_PRICE ))
NET_BURN=$(( NET_SHORT * 1000 ))
TOTAL=$(( NRG_BURN + NET_BURN ))

echo "energy     need $NRG_NEED, free $NRG_FREE -> burn $(trx $NRG_BURN) TRX"
echo "bandwidth  need $NET_NEED, free $NET_FREE -> burn $(trx $NET_BURN) TRX"
echo "total fee  $(trx $TOTAL) TRX"
echo "balance    $(trx "$BALANCE") TRX"

RC=0
if [ "$NRG_BURN" -gt "$FEE_LIMIT" ]; then
  echo "FAIL: energy burn exceeds fee_limit $(trx "$FEE_LIMIT") TRX -> OUT_OF_ENERGY, fee consumed anyway"
  RC=1
fi
if [ "$TOTAL" -gt "$BALANCE" ]; then
  echo "FAIL: balance too low, short by $(trx $(( TOTAL - BALANCE ))) TRX"
  RC=1
fi
[ "$RC" -eq 0 ] && echo "OK"
exit "$RC"
