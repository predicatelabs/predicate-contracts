// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {Test, console} from "forge-std/Test.sol";
import {PredicateRegistry} from "src/PredicateRegistry.sol";
import {MockProxyAdmin} from "./mocks/MockProxyAdmin.sol";
import {MockProxy} from "./mocks/MockProxy.sol";

contract PredicateRegistrySetup is Test {
    // registry
    PredicateRegistry predicateRegistry;

    // implementation and proxy admin
    PredicateRegistry predicateRegistryImpl;
    MockProxyAdmin proxyAdmin;

    // owner of the contract
    address owner = makeAddr("owner");

    // attesters
    address attesterOne;
    uint256 attesterOnePk;

    address attesterTwo;
    uint256 attesterTwoPk;

    // random address
    address randomAddress;

    // policies
    string policyOne = "policyOne";
    string policyTwo = "policyTwo";

    function setUp() public virtual {
        vm.startPrank(owner);
        proxyAdmin = new MockProxyAdmin(owner);
        predicateRegistryImpl = new PredicateRegistry();
        predicateRegistry =
            PredicateRegistry(address(new MockProxy(address(predicateRegistryImpl), address(proxyAdmin))));
        predicateRegistry.initialize(owner);
        vm.stopPrank();

        (attesterOne, attesterOnePk) = makeAddrAndKey("attesterOne");
        (attesterTwo, attesterTwoPk) = makeAddrAndKey("attesterTwo");
        (randomAddress,) = makeAddrAndKey("random");
        // register attesters (only One and Two)
        vm.startPrank(owner);
        predicateRegistry.registerAttester(attesterOne);
        predicateRegistry.registerAttester(attesterTwo);
        vm.stopPrank();
    }
}
