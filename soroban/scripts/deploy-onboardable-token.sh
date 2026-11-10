#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOROBAN_DIR="$(dirname "$SCRIPT_DIR")"

PREDICATE_SIGNER="GCDJXKIZODN7SISUQYLIP2PDIRAGASCGV7P62ABEJE7M7ISAZVHD6SFL"

NETWORK="${STELLAR_NETWORK:-testnet}"
TOKEN_NAME="${TOKEN_NAME:-Onboardable USD}"
TOKEN_SYMBOL="${TOKEN_SYMBOL:-oUSD}"

if [[ $# -lt 1 || $# -gt 5 ]]; then
  echo "Usage: $0 <identity> [admin] [onboarder] [block_operator] [unblock_operator]"
  echo ""
  echo "  identity          Stellar CLI identity name (deployer)"
  echo "  admin             Admin address (default: identity's address)"
  echo "  onboarder         Onboarder address (default: Predicate's enforcement address)"
  echo "  block_operator    Block operator address (default: Predicate's enforcement address)"
  echo "  unblock_operator  Unblock operator address (default: Predicate's enforcement address)"
  exit 1
fi

IDENTITY="$1"
ADMIN_ADDRESS="${2:-$(stellar keys address "$IDENTITY")}"
ONBOARDER_ADDRESS="${3:-$PREDICATE_SIGNER}"
BLOCKER_ADDRESS="${4:-$PREDICATE_SIGNER}"
UNBLOCKER_ADDRESS="${5:-$PREDICATE_SIGNER}"

echo "Building example-onboardable-token..."
cd "$SOROBAN_DIR"
cargo build --release --target wasm32-unknown-unknown -p example-onboardable-token

WASM_PATH="$SOROBAN_DIR/target/wasm32-unknown-unknown/release/example_onboardable_token.wasm"

if [ ! -f "$WASM_PATH" ]; then
  echo "ERROR: WASM not found at $WASM_PATH"
  exit 1
fi

echo "WASM size: $(wc -c < "$WASM_PATH" | tr -d ' ') bytes"

echo ""
echo "Deploying OnboardableToken to $NETWORK..."

TOKEN_ID=$(stellar contract deploy \
  --wasm "$WASM_PATH" \
  --source "$IDENTITY" \
  --network "$NETWORK" \
  -- \
  --name "$TOKEN_NAME" \
  --symbol "$TOKEN_SYMBOL" \
  --admin "$ADMIN_ADDRESS" \
  --onboarder "$ONBOARDER_ADDRESS" \
  --block_operator "$BLOCKER_ADDRESS" \
  --unblock_operator "$UNBLOCKER_ADDRESS")

echo ""
echo "=== Onboardable Token Deployment Complete ==="
echo "  Network:          $NETWORK"
echo "  Token:            $TOKEN_ID"
echo "  Name / symbol:    $TOKEN_NAME / $TOKEN_SYMBOL"
echo "  Admin:            $ADMIN_ADDRESS"
echo "  Onboarder:        $ONBOARDER_ADDRESS"
echo "  Block operator:   $BLOCKER_ADDRESS"
echo "  Unblock operator: $UNBLOCKER_ADDRESS"
echo ""
echo "Usage:"
echo "  # Onboard a wallet (onboarder only):"
echo "  stellar contract invoke --id $TOKEN_ID --source <ONBOARDER> --network $NETWORK --send=yes -- onboard_user --user <ADDRESS> --operator <ONBOARDER>"
echo ""
echo "  # Mint to an onboarded wallet (admin only):"
echo "  stellar contract invoke --id $TOKEN_ID --source <ADMIN> --network $NETWORK --send=yes -- mint --to <ADDRESS> --amount 1000000"
echo ""
echo "  # Check onboarding:"
echo "  stellar contract invoke --id $TOKEN_ID --source $IDENTITY --network $NETWORK -- is_onboarded --account <ADDRESS>"
