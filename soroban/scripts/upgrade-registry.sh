#!/usr/bin/env bash
set -euo pipefail

# Upgrade an already-deployed PredicateRegistry to freshly-built WASM.
#
# Prerequisites:
#   - stellar CLI installed
#   - The identity used must be the registry OWNER (it signs the upgrade)
#
# Usage:
#   ./upgrade-registry.sh <identity> <registry_id> [network]
#
# Examples:
#   ./upgrade-registry.sh deployer CAMK3PPM...
#   ./upgrade-registry.sh deployer CAMK3PPM... mainnet

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOROBAN_DIR="$(dirname "$SCRIPT_DIR")"

if [ $# -lt 2 ]; then
  echo "Usage: $0 <identity> <registry_id> [network]"
  echo ""
  echo "  identity     Stellar CLI identity name; MUST be the registry owner"
  echo "  registry_id  Contract ID of the deployed PredicateRegistry"
  echo "  network      Optional network (default: testnet)"
  exit 1
fi

IDENTITY="$1"
REGISTRY_ID="$2"
NETWORK="${3:-testnet}"
OWNER_ADDRESS=$(stellar keys address "$IDENTITY")

# --- Build ---
# Use `stellar contract build` (targets wasm32v1-none). A plain
# `cargo build --target wasm32-unknown-unknown` emits reference-types WASM that
# the soroban host rejects at upload ("reference-types not enabled").

echo "Building predicate-registry..."
cd "$SOROBAN_DIR"
stellar contract build --package predicate-registry

WASM_PATH="$SOROBAN_DIR/target/wasm32v1-none/release/predicate_registry.wasm"

if [ ! -f "$WASM_PATH" ]; then
  echo "ERROR: WASM not found at $WASM_PATH"
  exit 1
fi

echo "WASM size: $(wc -c < "$WASM_PATH" | tr -d ' ') bytes"

# --- Upload (install) new WASM, capture its hash ---

echo ""
echo "Uploading new WASM to $NETWORK..."
WASM_HASH=$(stellar contract upload \
  --wasm "$WASM_PATH" \
  --source "$IDENTITY" \
  --network "$NETWORK")

echo "New WASM hash: $WASM_HASH"

# --- Invoke upgrade ---

echo ""
echo "Upgrading registry $REGISTRY_ID..."
echo "  Owner: $OWNER_ADDRESS"
stellar contract invoke \
  --id "$REGISTRY_ID" \
  --source "$IDENTITY" \
  --network "$NETWORK" \
  --send=yes \
  -- \
  upgrade \
  --owner "$OWNER_ADDRESS" \
  --new_wasm_hash "$WASM_HASH"

echo ""
echo "=== Registry Upgrade Complete ==="
echo "  Network:   $NETWORK"
echo "  Registry:  $REGISTRY_ID"
echo "  Owner:     $OWNER_ADDRESS"
echo "  New WASM:  $WASM_HASH"
