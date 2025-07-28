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
    
    // attestors
    address attestorOne;
    uint256 attestorOnePk;

    address attestorTwo;
    uint256 attestorTwoPk;

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

        (attestorOne, attestorOnePk) = makeAddrAndKey("attestorOne");
        (attestorTwo, attestorTwoPk) = makeAddrAndKey("attestorTwo");
        (randomAddress,) = makeAddrAndKey("random");
        // register attestors (only One and Two)
        vm.startPrank(owner);
        predicateRegistry.registerAttestor(attestorOne);
        predicateRegistry.registerAttestor(attestorTwo);
        vm.stopPrank();

        // enable policies
        vm.startPrank(owner);
        predicateRegistry.enablePolicy(policyOne);
        predicateRegistry.enablePolicy(policyTwo);
        vm.stopPrank();
    }
}
