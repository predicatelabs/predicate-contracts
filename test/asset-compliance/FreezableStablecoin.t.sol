// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {IFreezable} from "../../src/interfaces/IFreezable.sol";
import {FreezableStablecoin} from "../../src/examples/asset-compliance/FreezableStablecoin.sol";

/// @notice Tests the asset-compliance invariants of {FreezableStablecoin}, with emphasis on
///         role separation: Predicate's FREEZE_MANAGER_ROLE must NOT be able to seize/mint/pause/upgrade.
contract FreezableStablecoinTest is Test {
    // Local mirror of the event for expectEmit matching.
    event ForcedTransfer(address indexed from, address indexed to, uint256 amount);

    FreezableStablecoin internal token;

    address internal admin = makeAddr("admin");
    address internal predicateFreezer = makeAddr("predicateFreezer"); // FREEZE_MANAGER_ROLE (Predicate)
    address internal pauser = makeAddr("pauser");
    address internal seizer = makeAddr("seizer"); // FORCED_TRANSFER_MANAGER_ROLE (issuer)
    address internal minter = makeAddr("minter");
    address internal burner = makeAddr("burner");
    address internal treasury = makeAddr("treasury");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    // Role IDs cached in setUp. Reading them via an external call between vm.prank and the target
    // call would consume the prank, so they are resolved once here.
    bytes32 internal roleFreeze;
    bytes32 internal roleSeize;
    bytes32 internal rolePause;
    bytes32 internal roleMint;
    bytes32 internal roleAdmin;

    uint256 internal constant INITIAL = 1_000_000e6;

    function setUp() public {
        FreezableStablecoin impl = new FreezableStablecoin();
        bytes memory initData = abi.encodeCall(
            FreezableStablecoin.initialize,
            ("Compliant USD", "cUSD", admin, predicateFreezer, pauser, seizer, minter, burner)
        );
        token = FreezableStablecoin(address(new ERC1967Proxy(address(impl), initData)));

        roleFreeze = token.FREEZE_MANAGER_ROLE();
        roleSeize = token.FORCED_TRANSFER_MANAGER_ROLE();
        rolePause = token.PAUSER_ROLE();
        roleMint = token.MINTER_ROLE();
        roleAdmin = token.DEFAULT_ADMIN_ROLE();

        vm.prank(minter);
        token.mint(alice, INITIAL);
    }

    /* ============ Freeze blocks send AND receive ============ */

    function test_freeze_blocksSend() public {
        vm.prank(predicateFreezer);
        token.freeze(alice);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        token.transfer(bob, 1e6);
    }

    function test_freeze_blocksReceive() public {
        vm.prank(predicateFreezer);
        token.freeze(bob);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, bob));
        token.transfer(bob, 1e6);
    }

    function test_freeze_blocksTransferFromWhenOwnerFrozen() public {
        vm.prank(alice);
        token.approve(bob, 1e6);
        vm.prank(predicateFreezer);
        token.freeze(alice);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        token.transferFrom(alice, bob, 1e6);
    }

    function test_freeze_blocksTransferFromWhenSpenderFrozen() public {
        // A frozen spender must not be able to move a third party's funds, even with an allowance.
        vm.prank(alice);
        token.approve(bob, 1e6);
        vm.prank(predicateFreezer);
        token.freeze(bob);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, bob));
        token.transferFrom(alice, treasury, 1e6);
    }

    function test_batchFreezeUnfreeze() public {
        address[] memory accts = new address[](2);
        accts[0] = alice;
        accts[1] = bob;

        vm.prank(predicateFreezer);
        token.freezeAccounts(accts);
        assertTrue(token.isFrozen(alice));
        assertTrue(token.isFrozen(bob));

        vm.prank(predicateFreezer);
        token.unfreezeAccounts(accts);
        assertFalse(token.isFrozen(alice));
        assertFalse(token.isFrozen(bob));
    }

    /* ============ Seize (forced transfer) ============ */

    function test_seize_movesFrozenBalance() public {
        vm.prank(predicateFreezer);
        token.freeze(alice);

        vm.expectEmit(true, true, false, true, address(token));
        emit ForcedTransfer(alice, treasury, INITIAL);

        vm.prank(seizer);
        token.forceTransfer(alice, treasury, INITIAL);

        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(treasury), INITIAL);
    }

    function test_seize_requiresFrozenSource() public {
        vm.prank(seizer);
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountNotFrozen.selector, alice));
        token.forceTransfer(alice, treasury, 1e6);
    }

    function test_seize_worksWhilePaused() public {
        vm.prank(predicateFreezer);
        token.freeze(alice);
        vm.prank(pauser);
        token.pause();

        vm.prank(seizer);
        token.forceTransfer(alice, treasury, INITIAL);
        assertEq(token.balanceOf(treasury), INITIAL);
    }

    /* ============ Pause ============ */

    function test_pause_blocksTransfers() public {
        vm.prank(pauser);
        token.pause();
        vm.prank(alice);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        token.transfer(bob, 1e6);
    }

    /* ============ Role separation (the core invariant) ============ */

    function test_roleSeparation_freezeManagerCannotSeize() public {
        vm.prank(predicateFreezer);
        token.freeze(alice);
        vm.prank(predicateFreezer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, predicateFreezer, roleSeize
            )
        );
        token.forceTransfer(alice, treasury, 1e6);
    }

    function test_roleSeparation_freezeManagerCannotMint() public {
        vm.prank(predicateFreezer);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, predicateFreezer, roleMint)
        );
        token.mint(predicateFreezer, 1e6);
    }

    function test_roleSeparation_freezeManagerCannotPause() public {
        vm.prank(predicateFreezer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, predicateFreezer, rolePause
            )
        );
        token.pause();
    }

    function test_roleSeparation_freezeManagerCannotUpgrade() public {
        address newImpl = address(new FreezableStablecoin());
        vm.prank(predicateFreezer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, predicateFreezer, roleAdmin
            )
        );
        token.upgradeToAndCall(newImpl, "");
    }

    function test_roleSeparation_seizerCannotFreeze() public {
        vm.prank(seizer);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, seizer, roleFreeze)
        );
        token.freeze(alice);
    }

    /* ============ Revocation kill-switch ============ */

    function test_revokeFreezeManager_disablesFreeze() public {
        vm.prank(admin);
        token.revokeRole(roleFreeze, predicateFreezer);

        vm.prank(predicateFreezer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, predicateFreezer, roleFreeze
            )
        );
        token.freeze(alice);
    }

    /* ============ Sanity ============ */

    function test_normalTransferSucceeds() public {
        vm.prank(alice);
        token.transfer(bob, 10e6);
        assertEq(token.balanceOf(bob), 10e6);
        assertEq(token.balanceOf(alice), INITIAL - 10e6);
    }

    function test_decimalsIsSix() public {
        assertEq(token.decimals(), 6);
    }
}
