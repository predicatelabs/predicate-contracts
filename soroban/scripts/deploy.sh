#!/usr/bin/env bash
set -euo pipefail

# Deploy TestStablecoin to Stellar testnet
#
# Prerequisites:
#   - stellar CLI installed (https://developers.stellar.org/docs/tools/developer-tools/cli/install-cli)
#   - An identity configured: stellar keys generate <name> --network testnet
#     or import existing: stellar keys add <name> --secret-key
#
# Usage:
#   ./deploy.sh <identity> [admin_address] [manager_address] [blocker_address]
#
# Examples:
#   ./deploy.sh alice                                        # alice is admin, manager, and blocker
#   ./deploy.sh alice GA...ADMIN GA...MANAGER GA...BLOCKER   # separate roles

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOROBAN_DIR="$(dirname "$SCRIPT_DIR")"

NETWORK="testnet"
TOKEN_NAME="Test USD"
TOKEN_SYMBOL="TUSD"
INITIAL_SUPPLY="1000000000" # 1000 tokens with 6 decimals

# --- Parse args ---

if [ $# -lt 1 ]; then
  echo "Usage: $0 <identity> [admin_address] [manager_address] [blocker_address]"
  echo ""
  echo "  identity          Stellar CLI identity name (from 'stellar keys')"
  echo "  admin_address     Admin address (defaults to identity's address)"
  echo "  manager_address   Manager/compliance address (defaults to admin)"
  echo "  blocker_address   Blocker/freeze address (defaults to admin)"
  exit 1
fi

IDENTITY="$1"
ADMIN_ADDRESS="${2:-}"
MANAGER_ADDRESS="${3:-}"
BLOCKER_ADDRESS="${4:-}"

# Resolve addresses from identity if not provided
if [ -z "$ADMIN_ADDRESS" ]; then
  ADMIN_ADDRESS=$(stellar keys address "$IDENTITY")
  echo "Using identity address as admin: $ADMIN_ADDRESS"
fi

if [ -z "$MANAGER_ADDRESS" ]; then
  MANAGER_ADDRESS="$ADMIN_ADDRESS"
  echo "Using admin address as manager: $MANAGER_ADDRESS"
fi

if [ -z "$BLOCKER_ADDRESS" ]; then
  BLOCKER_ADDRESS="$ADMIN_ADDRESS"
  echo "Using admin address as blocker: $BLOCKER_ADDRESS"
fi

# --- Build ---

echo ""
echo "Building test-stablecoin..."
cd "$SOROBAN_DIR"
cargo build --release --target wasm32-unknown-unknown

echo "Optimizing WASM for Soroban VM..."
stellar contract optimize --wasm "$SOROBAN_DIR/target/wasm32-unknown-unknown/release/test_stablecoin.wasm"
WASM_PATH="$SOROBAN_DIR/target/wasm32-unknown-unknown/release/test_stablecoin.optimized.wasm"

if [ ! -f "$WASM_PATH" ]; then
  echo "ERROR: Optimized WASM not found at $WASM_PATH"
  exit 1
fi

echo "WASM size: $(wc -c < "$WASM_PATH" | tr -d ' ') bytes (optimized)"

# --- Deploy + Initialize ---

echo ""
echo "Deploying to $NETWORK (name=$TOKEN_NAME, symbol=$TOKEN_SYMBOL, supply=$INITIAL_SUPPLY)..."
CONTRACT_ID=$(stellar contract deploy \
  --wasm "$WASM_PATH" \
  --source "$IDENTITY" \
  --network "$NETWORK" \
  -- \
  --name "\"${TOKEN_NAME}\"" \
  --symbol "\"${TOKEN_SYMBOL}\"" \
  --admin "$ADMIN_ADDRESS" \
  --manager "$MANAGER_ADDRESS" \
  --blocker "$BLOCKER_ADDRESS" \
  --initial_supply "$INITIAL_SUPPLY")

echo "Contract deployed: $CONTRACT_ID"

echo ""
echo "=== Deployment complete ==="
echo "  Network:    $NETWORK"
echo "  Contract:   $CONTRACT_ID"
echo "  Admin:      $ADMIN_ADDRESS"
echo "  Manager:    $MANAGER_ADDRESS"
echo "  Blocker:    $BLOCKER_ADDRESS"
echo "  Token:      $TOKEN_NAME ($TOKEN_SYMBOL)"
echo "  Supply:     $INITIAL_SUPPLY (6 decimals = 1,000 tokens)"
