// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {FreezableStablecoin} from "../../src/examples/asset-compliance/FreezableStablecoin.sol";

/**
 * @title GrantFreezeManager
 * @notice Grants / revokes / verifies Predicate's freezer on a deployed asset — the on-chain step
 *         that makes a token enforceable by Predicate asset compliance.
 * @dev `FREEZE_MANAGER_ROLE` is the ONLY authority Predicate needs. It is revocable in one
 *      transaction (`revoke`), verifiable (`check`), and never confers seize/mint/burn/pause/upgrade.
 *
 * Grant:  TOKEN=0x.. forge script script/asset-compliance/GrantFreezeManager.s.sol --sig "run()"    --rpc-url $RPC_URL --broadcast
 * Revoke: TOKEN=0x.. forge script script/asset-compliance/GrantFreezeManager.s.sol --sig "revoke()" --rpc-url $RPC_URL --broadcast
 * Check:  TOKEN=0x.. forge script script/asset-compliance/GrantFreezeManager.s.sol --sig "check()"  --rpc-url $RPC_URL
 *
 * Equivalent `cast` (mirrors https://docs.predicate.io/v2/assets/get-started):
 *   cast send <TOKEN> "grantRole(bytes32,address)" $(cast keccak "FREEZE_MANAGER_ROLE") \
 *     0x363c256D368277BBFaf6EaF65beE123a7AdbA464 --rpc-url $RPC_URL --private-key $PK
 *   cast call <TOKEN> "hasRole(bytes32,address)(bool)" $(cast keccak "FREEZE_MANAGER_ROLE") \
 *     0x363c256D368277BBFaf6EaF65beE123a7AdbA464 --rpc-url $RPC_URL
 */
contract GrantFreezeManager is Script {
    /// @notice Predicate's authorized freezer across all EVM chains.
    address public constant PREDICATE_FREEZER = 0x363c256D368277BBFaf6EaF65beE123a7AdbA464;

    function run() external {
        FreezableStablecoin token = _token();
        vm.startBroadcast();
        token.grantRole(token.FREEZE_MANAGER_ROLE(), PREDICATE_FREEZER);
        vm.stopBroadcast();
        console2.log("Granted FREEZE_MANAGER_ROLE to Predicate freezer on", address(token));
    }

    function revoke() external {
        FreezableStablecoin token = _token();
        vm.startBroadcast();
        token.revokeRole(token.FREEZE_MANAGER_ROLE(), PREDICATE_FREEZER);
        vm.stopBroadcast();
        console2.log("Revoked FREEZE_MANAGER_ROLE from Predicate freezer on", address(token));
    }

    function check() external view returns (bool granted) {
        FreezableStablecoin token = _token();
        granted = token.hasRole(token.FREEZE_MANAGER_ROLE(), PREDICATE_FREEZER);
        console2.log("Predicate freezer holds FREEZE_MANAGER_ROLE:", granted);
    }

    function _token() internal view returns (FreezableStablecoin) {
        return FreezableStablecoin(vm.envAddress("TOKEN"));
    }
}
