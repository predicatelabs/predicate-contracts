// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {TestOnboardingToken} from "../../src/examples/wallet-onboarding/TestOnboardingToken.sol";

contract DeployTestOnboardingToken is Script {
    address public constant PREDICATE_SIGNER = 0x363c256D368277BBFaf6EaF65beE123a7AdbA464;

    function run() external returns (TestOnboardingToken token) {
        address admin = vm.envAddress("ADMIN");
        address freezeManager = vm.envOr("FREEZE_MANAGER", PREDICATE_SIGNER);
        address whitelistManager = vm.envOr("WHITELIST_MANAGER", PREDICATE_SIGNER);

        string memory name_ = vm.envOr("TOKEN_NAME", string("Onboarding Test USD"));
        string memory symbol_ = vm.envOr("TOKEN_SYMBOL", string("otUSD"));

        vm.startBroadcast();
        token = new TestOnboardingToken(name_, symbol_, admin, freezeManager, whitelistManager);
        vm.stopBroadcast();

        console2.log("TestOnboardingToken:", address(token));
        console2.log("DEFAULT_ADMIN_ROLE ->", admin);
        console2.log("FREEZE_MANAGER_ROLE ->", freezeManager);
        console2.log("WHITELIST_MANAGER_ROLE ->", whitelistManager);
    }
}
