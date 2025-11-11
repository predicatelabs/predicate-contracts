// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

interface IProxyAdmin {
    function upgrade(address proxy, address implementation) external;
    function upgradeAndCall(address proxy, address implementation, bytes calldata data) external payable;
}

/// @notice Foundry script to assist upgrading the ServiceManager via ProxyAdmin.
/// - If PRIVATE_KEY is provided, it will broadcast the upgrade transaction from that EOA.
/// - If PRIVATE_KEY is NOT provided, it will print the calldata for Gnosis Safe / multisig execution.
/// Env vars:
/// - PROXY_ADMIN: address of ProxyAdmin
/// - SERVICE_MANAGER_PROXY: address of the ServiceManager TransparentUpgradeableProxy
/// - NEW_IMPL: address of the new ServiceManager implementation
/// - INIT_DATA (optional): hex-encoded bytes for reinitializer call; when provided, uses upgradeAndCall
/// - PRIVATE_KEY (optional): hex private key to broadcast directly instead of printing calldata
contract UpgradeServiceManager is Script {
    function run() external {
        address proxyAdmin = vm.envAddress("PROXY_ADMIN");
        address proxy = vm.envAddress("SERVICE_MANAGER_PROXY");
        address newImpl = vm.envAddress("NEW_IMPL");

        bytes memory initData = _tryGetBytesEnv("INIT_DATA");
        bool useUpgradeAndCall = initData.length > 0;

        // If PRIVATE_KEY is provided, broadcast. Otherwise, print calldata for multisig.
        uint256 pk = _tryGetUintEnv("PRIVATE_KEY");
        if (pk != 0) {
            vm.startBroadcast(pk);
            if (useUpgradeAndCall) {
                IProxyAdmin(proxyAdmin).upgradeAndCall(proxy, newImpl, initData);
                console2.log("Broadcasted ProxyAdmin.upgradeAndCall");
            } else {
                IProxyAdmin(proxyAdmin).upgrade(proxy, newImpl);
                console2.log("Broadcasted ProxyAdmin.upgrade");
            }
            vm.stopBroadcast();
        } else {
            // 1) Calldata for ProxyAdmin.upgrade / upgradeAndCall (to submit via ProxyAdmin multisig)
            bytes memory adminCalldata;
            if (useUpgradeAndCall) {
                adminCalldata = abi.encodeWithSignature(
                    "upgradeAndCall(address,address,bytes)", proxy, newImpl, initData
                );
                console2.log("Use ProxyAdmin.upgradeAndCall via your multisig");
            } else {
                adminCalldata = abi.encodeWithSignature("upgrade(address,address)", proxy, newImpl);
                console2.log("Use ProxyAdmin.upgrade via your multisig");
            }
            console2.log("ProxyAdmin:", proxyAdmin);
            console2.logBytes(adminCalldata);

            // 2) If you are NOT using upgradeAndCall, you likely need a separate reinitializer call
            // from the ServiceManager OWNER multisig. Provide the proxy as the target and initData as the calldata.
            if (!useUpgradeAndCall) {
                console2.log(
                    "If your new implementation requires initialization, submit this SECOND tx from the ServiceManager OWNER multisig:"
                );
                // This assumes INIT_DATA (if provided) is already encoded for the ServiceManager reinitializer,
                // e.g. abi.encodeWithSelector(ServiceManager.reinitializeV2.selector, args...)
                if (initData.length == 0) {
                    console2.log(
                        "Note: INIT_DATA not provided. If initialization is required, set INIT_DATA and re-run to print it."
                    );
                } else {
                    console2.log("Call target (ServiceManager proxy):", proxy);
                    console2.logBytes(initData);
                }
            }
        }
    }

    function _tryGetBytesEnv(string memory key) internal returns (bytes memory data) {
        try vm.envBytes(key) returns (bytes memory v) {
            return v;
        } catch {
            return hex"";
        }
    }

    function _tryGetUintEnv(string memory key) internal returns (uint256 value) {
        try vm.envUint(key) returns (uint256 v) {
            return v;
        } catch {
            return 0;
        }
    }
}


