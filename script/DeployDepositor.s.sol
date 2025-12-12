// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Depositor} from "src/examples/inheritance/Depositor.sol";

contract DeployDepositorScript is Script {
    function run() external {
        // Hardcoded constructor values for Ethereum mainnet deployment
        address owner = 0x38f6001e8ac11240f903CBa56aFF72A1425ae371;
        address serviceManager = 0xf6f4A30EeF7cf51Ed4Ee1415fB3bFDAf3694B0d2;
        string memory policyId = "x-nest-prod-005";

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Depositor depositor = new Depositor(owner, serviceManager, policyId);
        console2.log("Depositor deployed at", address(depositor));

        vm.stopBroadcast();
    }
}

