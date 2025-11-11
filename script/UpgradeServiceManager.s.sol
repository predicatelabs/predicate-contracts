// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "forge-std/Script.sol";
import {ServiceManager} from "src/ServiceManager.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * Foundry script to upgrade the TransparentUpgradeableProxy for ServiceManager.
 *
 * Required env vars:
 * - PROXY_ADMIN_PK:         Private key of the ProxyAdmin owner
 * - PROXY_ADMIN:            Address of the ProxyAdmin
 * - SERVICE_MANAGER_PROXY:  Address of the ServiceManager TransparentUpgradeableProxy
 *
 * Example:
 * forge script script/UpgradeServiceManager.s.sol:UpgradeServiceManagerScript \
 *   --rpc-url $RPC_URL \
 *   --private-key $PROXY_ADMIN_PK \
 *   --broadcast -vvvv
 */
contract UpgradeServiceManagerScript is Script {
    function run() external {
        uint256 proxyAdminPk = vm.envUint("PK");
        address proxyAdminAddr = vm.envAddress("PROXY_ADMIN");
        address proxyAddr = vm.envAddress("SERVICE_MANAGER_PROXY");

        vm.startBroadcast(proxyAdminPk);

        ServiceManager newImplementation = new ServiceManager();

        // can't use this for Multisig 
        // ProxyAdmin(proxyAdminAddr).upgradeAndCall(
        //     ITransparentUpgradeableProxy(payable(proxyAddr)),
        //     address(newImplementation),
        //     bytes("")
        // );

        vm.stopBroadcast();
    }
}


