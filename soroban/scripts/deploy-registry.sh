#!/usr/bin/env bash
set -euo pipefail

# Deploy PredicateRegistry to Stellar testnet
#
# Prerequisites:
#   - stellar CLI installed
#   - An identity configured: stellar keys generate <name> --network testnet
#
# Usage:
#   ./deploy-registry.sh <identity> [attester_pubkey_hex]
#
# Examples:
#   ./deploy-registry.sh deployer
#   ./deploy-registry.sh deployer abc123...  # also register an attester

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOROBAN_DIR="$(dirname "$SCRIPT_DIR")"

NETWORK="testnet"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <identity> [attester_pubkey_hex]"
  echo ""
  echo "  identity             Stellar CLI identity name (from 'stellar keys')"
  echo "  attester_pubkey_hex  Optional: Ed25519 attester public key (64 hex chars)"
  echo "                       to register immediately after deployment"
  exit 1
fi

IDENTITY="$1"
ATTESTER_PK="${2:-}"
OWNER_ADDRESS=$(stellar keys address "$IDENTITY")

# --- Build ---

echo "Building predicate-registry..."
cd "$SOROBAN_DIR"
cargo build --release --target wasm32-unknown-unknown -p predicate-registry

WASM_PATH="$SOROBAN_DIR/target/wasm32-unknown-unknown/release/predicate_registry.wasm"

if [ ! -f "$WASM_PATH" ]; then
  echo "ERROR: WASM not found at $WASM_PATH"
  exit 1
fi

echo "WASM size: $(wc -c < "$WASM_PATH" | tr -d ' ') bytes"

# --- Deploy ---

echo ""
echo "Deploying PredicateRegistry to $NETWORK..."
echo "  Owner: $OWNER_ADDRESS"

REGISTRY_ID=$(stellar contract deploy \
  --wasm "$WASM_PATH" \
  --source "$IDENTITY" \
  --network "$NETWORK" \
  -- \
  --owner "$OWNER_ADDRESS")

echo "Registry deployed: $REGISTRY_ID"

# --- Register attester (optional) ---

if [ -n "$ATTESTER_PK" ]; then
  echo ""
  echo "Registering attester: $ATTESTER_PK"
  stellar contract invoke \
    --id "$REGISTRY_ID" \
    --source "$IDENTITY" \
    --network "$NETWORK" \
    --send=yes \
    -- \
    register_attester \
    --owner "$OWNER_ADDRESS" \
    --attester "$ATTESTER_PK"
  echo "Attester registered."
fi

echo ""
echo "=== Registry Deployment Complete ==="
echo "  Network:   $NETWORK"
echo "  Registry:  $REGISTRY_ID"
echo "  Owner:     $OWNER_ADDRESS"
if [ -n "$ATTESTER_PK" ]; then
  echo "  Attester:  $ATTESTER_PK"
fi
echo ""
echo "Next steps:"
echo "  1. Register attesters (if not done above):"
echo "     stellar contract invoke --id $REGISTRY_ID --source $IDENTITY --network $NETWORK --send=yes -- register_attester --owner $OWNER_ADDRESS --attester <HEX_PUBKEY>"
echo ""
echo "  2. Deploy a compliant contract and pass this registry address to it."
