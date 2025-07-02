// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {Test, console} from "forge-std/Test.sol";
import "./TestStorage.sol";
import {SimpleServiceManager} from "../../../src/SimpleServiceManager.sol";

contract SimpleServiceManagerSetup is TestStorage {
    SimpleServiceManager public simpleServiceManagerImpl;
    SimpleServiceManager public simpleServiceManager;
    MockProxyAdmin public simpleServiceManagerAdmin;

    function setUp() public virtual {
        vm.startPrank(owner);
        simpleServiceManagerAdmin = new MockProxyAdmin(owner);
        simpleServiceManagerImpl = new SimpleServiceManager();
        simpleServiceManager = SimpleServiceManager(
            address(new MockProxy(address(simpleServiceManagerImpl), address(simpleServiceManagerAdmin)))
        );
        simpleServiceManager.initialize(owner);

        string[] memory policies = new string[](1);
        policies[0] = policyID;

        uint32[] memory thresholds = new uint32[](1);
        thresholds[0] = 1;

        simpleServiceManager.syncPolicyIDs(policies, thresholds);

        client = new MockClient(owner, address(simpleServiceManager), policyID);

        (operatorOne, operatorOnePk) = makeAddrAndKey("operatorOne");
        (operatorOneAlias, operatorOneAliasPk) = makeAddrAndKey("operatorOneAlias");
        (operatorTwo, operatorTwoPk) = makeAddrAndKey("operatorTwo");
        (operatorTwoAlias, operatorTwoAliasPk) = makeAddrAndKey("operatorTwoAlias");

        address[] memory registrationKeys = new address[](2);
        address[] memory signingKeys = new address[](2);
        registrationKeys[0] = operatorOne;
        registrationKeys[1] = operatorTwo;
        signingKeys[0] = operatorOneAlias;
        signingKeys[1] = operatorTwoAlias;

        simpleServiceManager.syncOperators(registrationKeys, signingKeys, new address[](0));
        vm.stopPrank();
    }
}
