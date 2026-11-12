// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {ConcreteOnboardableToken} from "../../src/examples/asset-compliance/ConcreteOnboardableToken.sol";

contract DeployConcreteOnboardableToken is Script {
    address public constant PREDICATE_SIGNER = 0x363c256D368277BBFaf6EaF65beE123a7AdbA464;

    function run() external returns (ConcreteOnboardableToken token) {
        address admin = vm.envAddress("ADMIN");
        address freezeManager = vm.envOr("FREEZE_MANAGER", PREDICATE_SIGNER);
        address whitelistOwner = vm.envOr("WHITELIST_OWNER", PREDICATE_SIGNER);

        string memory name_ = vm.envOr("TOKEN_NAME", string("Concrete Onboardable USD"));
        string memory symbol_ = vm.envOr("TOKEN_SYMBOL", string("coUSD"));

        vm.startBroadcast();
        token = new ConcreteOnboardableToken(name_, symbol_, admin, freezeManager, whitelistOwner);
        vm.stopBroadcast();

        console2.log("ConcreteOnboardableToken:", address(token));
        console2.log("DEFAULT_ADMIN_ROLE ->", admin);
        console2.log("FREEZE_MANAGER_ROLE ->", freezeManager);
        console2.log("owner (whitelist) ->", whitelistOwner);
    }
}
