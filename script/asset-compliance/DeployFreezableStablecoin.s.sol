// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {FreezableStablecoin} from "../../src/examples/asset-compliance/FreezableStablecoin.sol";

/**
 * @title DeployFreezableStablecoin
 * @notice Deploys {FreezableStablecoin} behind an ERC-1967 proxy with least-privilege role holders.
 * @dev By default `FREEZE_MANAGER_ROLE` is assigned to Predicate's freezer so the asset is
 *      enrollment-ready; override any holder via env vars. Seize/mint/burn/pause default to the
 *      admin and should be moved to dedicated issuer keys in production.
 *
 * Usage:
 *   ADMIN=0x... forge script script/asset-compliance/DeployFreezableStablecoin.s.sol \
 *     --rpc-url $RPC_URL --broadcast
 */
contract DeployFreezableStablecoin is Script {
    /// @notice Predicate's authorized freezer across all EVM chains (docs.predicate.io/v2/assets).
    address public constant PREDICATE_FREEZER = 0x363c256D368277BBFaf6EaF65beE123a7AdbA464;

    function run() external returns (FreezableStablecoin token, address proxy) {
        address admin = vm.envOr("ADMIN", msg.sender);
        address freezeManager = vm.envOr("FREEZE_MANAGER", PREDICATE_FREEZER);
        address pauser = vm.envOr("PAUSER", admin);
        address seizeManager = vm.envOr("SEIZE_MANAGER", admin);
        address minter = vm.envOr("MINTER", admin);
        address burner = vm.envOr("BURNER", admin);

        string memory name_ = vm.envOr("TOKEN_NAME", string("Compliant USD"));
        string memory symbol_ = vm.envOr("TOKEN_SYMBOL", string("cUSD"));

        vm.startBroadcast();

        FreezableStablecoin impl = new FreezableStablecoin();
        bytes memory initData = abi.encodeCall(
            FreezableStablecoin.initialize, (name_, symbol_, admin, freezeManager, pauser, seizeManager, minter, burner)
        );
        ERC1967Proxy proxy_ = new ERC1967Proxy(address(impl), initData);

        vm.stopBroadcast();

        proxy = address(proxy_);
        token = FreezableStablecoin(proxy);

        console2.log("FreezableStablecoin implementation:", address(impl));
        console2.log("FreezableStablecoin proxy:", proxy);
        console2.log("FREEZE_MANAGER_ROLE -> ", freezeManager);
    }
}
