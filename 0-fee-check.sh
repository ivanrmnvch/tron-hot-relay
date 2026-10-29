#!/bin/bash
# Can this account actually pay for the built transaction?
# TRON burns TRX for energy/bandwidth it cannot cover from frozen resources,
# and a transaction that runs out mid-execution still consumes the fee.
# tx broadcast --dry-run does NOT check this on TRON.
set -u

export TZ=UTC
NETWORK=tron:3448148188
ACCOUNT=${1:-}
BUILD=${2:-build.json}

[ -n "$ACCOUNT" ] || { echo "usage: $0 <account> [build.json]"; exit 1; }
[ -s "$BUILD" ] || { echo "not found: $BUILD"; exit 1; }

INFO=$(wallet-cli account info --account "$ACCOUNT" --network "$NETWORK" -o json)
jq -e '.success' <<<"$INFO" >/dev/null || { jq -r '.error.message' <<<"$INFO"; exit 1; }

BALANCE=$(jq -r '.data.account.balance // 0'        <<<"$INFO")
NET_FREE=$(jq -r '.data.resources.bandwidth | .limit - .used' <<<"$INFO")
NRG_FREE=$(jq -r '.data.resources.energy    | .limit - .used' <<<"$INFO")

NRG_NEED=$(jq -r '.data.fee.energy // 0'            <<<"$(cat "$BUILD")")
NRG_PRICE=$(jq -r '.data.fee.energyPriceSun // 0'   <<<"$(cat "$BUILD")")
FEE_LIMIT=$(jq -r '.data.tx.raw_data.fee_limit // 0' <<<"$(cat "$BUILD")")
HEXLEN=$(jq -r '.data.hex | length'                 <<<"$(cat "$BUILD")")

# signed size: unsigned bytes + 65-byte signature + protobuf overhead
NET_NEED=$(( HEXLEN / 2 + 70 ))

NRG_SHORT=$(( NRG_NEED > NRG_FREE ? NRG_NEED - NRG_FREE : 0 ))
NET_SHORT=$(( NET_NEED > NET_FREE ? NET_NEED - NET_FREE : 0 ))
NRG_BURN=$(( NRG_SHORT * NRG_PRICE ))
NET_BURN=$(( NET_SHORT * 1000 ))
TOTAL=$(( NRG_BURN + NET_BURN ))

trx() { printf '%d.%06d' $(( $1 / 1000000 )) $(( $1 % 1000000 )); }

echo "energy     need $NRG_NEED, free $NRG_FREE  -> burn $(trx $NRG_BURN) TRX"
echo "bandwidth  need $NET_NEED, free $NET_FREE  -> burn $(trx $NET_BURN) TRX"
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
