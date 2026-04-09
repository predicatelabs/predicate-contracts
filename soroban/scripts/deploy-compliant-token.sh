#!/usr/bin/env bash
set -euo pipefail

# Deploy example-compliant-token to Stellar testnet
#
# Prerequisites:
#   - stellar CLI installed
#   - A PredicateRegistry already deployed (use deploy-registry.sh)
#
# Usage:
#   ./deploy-compliant-token.sh <identity> <registry_contract_id> <policy_id>
#
# Example:
#   ./deploy-compliant-token.sh deployer CABC...XYZ x-a1b2c3d4e5f6g7h8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOROBAN_DIR="$(dirname "$SCRIPT_DIR")"

NETWORK="testnet"
NETWORK_PASSPHRASE="Test SDF Network ; September 2015"

if [ $# -lt 3 ]; then
  echo "Usage: $0 <identity> <registry_contract_id> <policy_id>"
  echo ""
  echo "  identity              Stellar CLI identity name"
  echo "  registry_contract_id  Deployed PredicateRegistry contract ID (C...)"
  echo "  policy_id             Policy identifier (e.g. x-a1b2c3d4e5f6g7h8)"
  exit 1
fi

IDENTITY="$1"
REGISTRY_ID="$2"
POLICY_ID="$3"
ADMIN_ADDRESS=$(stellar keys address "$IDENTITY")

# --- Build ---

echo "Building example-compliant-token..."
cd "$SOROBAN_DIR"
cargo build --release --target wasm32-unknown-unknown -p example-compliant-token

WASM_PATH="$SOROBAN_DIR/target/wasm32-unknown-unknown/release/example_compliant_token.wasm"

if [ ! -f "$WASM_PATH" ]; then
  echo "ERROR: WASM not found at $WASM_PATH"
  exit 1
fi

echo "WASM size: $(wc -c < "$WASM_PATH" | tr -d ' ') bytes"

# --- Deploy ---

echo ""
echo "Deploying CompliantToken to $NETWORK..."
echo "  Admin:     $ADMIN_ADDRESS"
echo "  Registry:  $REGISTRY_ID"
echo "  Policy:    $POLICY_ID"
echo "  Network:   $NETWORK_PASSPHRASE"

TOKEN_ID=$(stellar contract deploy \
  --wasm "$WASM_PATH" \
  --source "$IDENTITY" \
  --network "$NETWORK" \
  -- \
  --admin "$ADMIN_ADDRESS" \
  --registry "$REGISTRY_ID" \
  --policy_id "$POLICY_ID" \
  --network "$NETWORK_PASSPHRASE")

echo "Token deployed: $TOKEN_ID"

# --- Register policy with the registry ---

echo ""
echo "Registering policy '$POLICY_ID' with the registry..."
stellar contract invoke \
  --id "$TOKEN_ID" \
  --source "$IDENTITY" \
  --network "$NETWORK" \
  --send=yes \
  -- \
  register_policy
echo "Policy registered."

echo ""
echo "=== Compliant Token Deployment Complete ==="
echo "  Network:   $NETWORK"
echo "  Token:     $TOKEN_ID"
echo "  Admin:     $ADMIN_ADDRESS"
echo "  Registry:  $REGISTRY_ID"
echo "  Policy:    $POLICY_ID"
echo ""
echo "Usage:"
echo "  # Mint tokens (admin only, no attestation needed):"
echo "  stellar contract invoke --id $TOKEN_ID --source $IDENTITY --network $NETWORK --send=yes -- mint --to <ADDRESS> --amount 1000000"
echo ""
echo "  # Transfer tokens (requires attestation from Predicate API):"
echo "  stellar contract invoke --id $TOKEN_ID --source $IDENTITY --network $NETWORK --send=yes -- transfer --from <FROM> --to <TO> --amount <AMT> --attestation '{...}'"
echo ""
echo "  # Check balance:"
echo "  stellar contract invoke --id $TOKEN_ID --source $IDENTITY --network $NETWORK -- balance --account <ADDRESS>"
