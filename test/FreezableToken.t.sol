// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {Test} from "forge-std/Test.sol";
import {FreezableToken} from "../src/examples/asset-compliance/FreezableToken.sol";
import {IFreezable} from "../src/interfaces/IFreezable.sol";

contract FreezableTokenTest is Test {
    FreezableToken token;

    address owner;
    address alice;
    address bob;

    uint256 constant INITIAL_SUPPLY = 1_000_000;

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        token = new FreezableToken(owner, INITIAL_SUPPLY);
    }

    function testInitialBalance() public {
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY);
    }

    function testTransfer() public {
        vm.prank(owner);
        token.transfer(alice, 100);

        assertEq(token.balanceOf(alice), 100);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - 100);
    }

    function testFreezeBlocksSender() public {
        // Transfer some tokens to alice first
        vm.prank(owner);
        token.transfer(alice, 100);

        // Freeze alice
        vm.prank(owner);
        token.freeze(alice);

        assertTrue(token.isFrozen(alice));

        // Alice cannot transfer
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        vm.prank(alice);
        token.transfer(bob, 50);
    }

    function testFreezeBlocksRecipient() public {
        // Freeze bob
        vm.prank(owner);
        token.freeze(bob);

        // Cannot transfer to frozen bob
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, bob));
        vm.prank(owner);
        token.transfer(bob, 100);
    }

    function testUnfreezeAllowsTransfer() public {
        // Transfer to alice, freeze, then unfreeze
        vm.prank(owner);
        token.transfer(alice, 100);

        vm.prank(owner);
        token.freeze(alice);

        vm.prank(owner);
        token.unfreeze(alice);

        assertFalse(token.isFrozen(alice));

        // Alice can transfer again
        vm.prank(alice);
        token.transfer(bob, 50);

        assertEq(token.balanceOf(bob), 50);
    }

    function testOnlyFreezeManagerCanFreeze() public {
        vm.expectRevert();
        vm.prank(alice);
        token.freeze(bob);
    }

    function testFreezeEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit IFreezable.Frozen(alice, block.timestamp);

        vm.prank(owner);
        token.freeze(alice);
    }
}
