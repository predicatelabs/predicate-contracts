// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "forge-std/Script.sol";
import {MetaCoin} from "../src/examples/inheritance/MetaCoin.sol";

contract DeployMetaCoin is Script {
    function run() external {
        // Deployment parameters:
        // - owner: MetaCoin owner address
        // - serviceManager: ServiceManager proxy address
        // - policyID: initial policy identifier
        address owner = 0x38f6001e8ac11240f903CBa56aFF72A1425ae371;
        address serviceManager = 0xf6f4A30EeF7cf51Ed4Ee1415fB3bFDAf3694B0d2;
        string memory policyID = "x-nest-prod-005";

        vm.startBroadcast();
        new MetaCoin(owner, serviceManager, policyID);
        vm.stopBroadcast();
    }
}


