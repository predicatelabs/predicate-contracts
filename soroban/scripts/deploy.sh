#!/usr/bin/env bash
set -euo pipefail

# TEST ONLY: deploy a private classic asset, its SAC, and the minimal test
# administration wrapper. This script is not suitable for production assets.
#
# Usage:
#   STELLAR_NETWORK=testnet ./deploy.sh <issuer-key> [deployer-key] \
#     [minter-address] [onboarder-address] [blocker-address] [unblocker-address]
#
# Defaults:
#   - deployer-key defaults to issuer-key
#   - every role defaults to the issuer's public address
#   - ASSET_CODE defaults to TSTUSD
#
# Mainnet requires:
#   STELLAR_NETWORK=mainnet \
#   ALLOW_MAINNET_TEST_DEPLOY=I_UNDERSTAND_TEST_ONLY \
#   ./deploy.sh ...

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOROBAN_DIR="$(dirname "$SCRIPT_DIR")"

if [[ $# -lt 1 || $# -gt 6 ]]; then
  echo "Usage: $0 <issuer-key> [deployer-key] [minter-address] [onboarder-address] [blocker-address] [unblocker-address]" >&2
  exit 1
fi

ISSUER_KEY="$1"
DEPLOYER_KEY="${2:-$ISSUER_KEY}"
NETWORK="${STELLAR_NETWORK:-testnet}"
ASSET_CODE="${ASSET_CODE:-TSTUSD}"
ISSUER_ADDRESS="$(stellar keys address "$ISSUER_KEY")"

MINTER_ADDRESS="${3:-$ISSUER_ADDRESS}"
ONBOARDER_ADDRESS="${4:-$ISSUER_ADDRESS}"
BLOCKER_ADDRESS="${5:-$ISSUER_ADDRESS}"
UNBLOCKER_ADDRESS="${6:-$ISSUER_ADDRESS}"

if [[ "$NETWORK" == "mainnet" && "${ALLOW_MAINNET_TEST_DEPLOY:-}" != "I_UNDERSTAND_TEST_ONLY" ]]; then
  echo "Refusing mainnet deployment without ALLOW_MAINNET_TEST_DEPLOY=I_UNDERSTAND_TEST_ONLY" >&2
  exit 1
fi

if [[ ! "$ASSET_CODE" =~ ^[A-Z0-9]{1,12}$ ]]; then
  echo "ASSET_CODE must contain 1-12 uppercase letters or digits" >&2
  exit 1
fi

echo "WARNING: deploying an unaudited TEST-ONLY contract."
echo "Network: $NETWORK"
echo "Asset:   $ASSET_CODE:$ISSUER_ADDRESS"
echo

echo "[1/5] Setting issuer authorization flags..."
stellar tx new set-options \
  --source-account "$ISSUER_KEY" \
  --network "$NETWORK" \
  --set-required \
  --set-revocable \
  --set-clawback-enabled

echo "[2/5] Deploying the Stellar Asset Contract..."
SAC_CONTRACT_ID="$(
  stellar contract asset deploy \
    --source-account "$DEPLOYER_KEY" \
    --network "$NETWORK" \
    --asset "$ASSET_CODE:$ISSUER_ADDRESS" |
    tr -d '\r\n'
)"

echo "[3/5] Building and optimizing the test wrapper..."
(
  cd "$SOROBAN_DIR"
  cargo build --release --target wasm32-unknown-unknown --package test-stablecoin
)
RAW_WASM="$SOROBAN_DIR/target/wasm32-unknown-unknown/release/test_stablecoin.wasm"
OPTIMIZED_WASM="$SOROBAN_DIR/target/wasm32-unknown-unknown/release/test_stablecoin.optimized.wasm"
stellar contract optimize --wasm "$RAW_WASM"

if [[ ! -f "$OPTIMIZED_WASM" ]]; then
  echo "Optimized WASM not found at $OPTIMIZED_WASM" >&2
  exit 1
fi

echo "[4/5] Deploying the test administration wrapper..."
WRAPPER_CONTRACT_ID="$(
  stellar contract deploy \
    --source-account "$DEPLOYER_KEY" \
    --network "$NETWORK" \
    --wasm "$OPTIMIZED_WASM" \
    -- \
    --sac_token "$SAC_CONTRACT_ID" \
    --minter "$MINTER_ADDRESS" \
    --onboarder "$ONBOARDER_ADDRESS" \
    --block_operator "$BLOCKER_ADDRESS" \
    --unblock_operator "$UNBLOCKER_ADDRESS" |
    tr -d '\r\n'
)"

echo "[5/5] Transferring SAC administration to the wrapper..."
stellar contract invoke \
  --source-account "$ISSUER_KEY" \
  --network "$NETWORK" \
  --id "$SAC_CONTRACT_ID" \
  -- \
  set_admin --new_admin "$WRAPPER_CONTRACT_ID"

echo
echo "Test deployment complete"
echo "  Network:          $NETWORK"
echo "  Asset:            $ASSET_CODE:$ISSUER_ADDRESS"
echo "  SAC:              $SAC_CONTRACT_ID"
echo "  Wrapper:          $WRAPPER_CONTRACT_ID"
echo "  Minter:           $MINTER_ADDRESS"
echo "  Onboarder:        $ONBOARDER_ADDRESS"
echo "  Block operator:   $BLOCKER_ADDRESS"
echo "  Unblock operator: $UNBLOCKER_ADDRESS"
