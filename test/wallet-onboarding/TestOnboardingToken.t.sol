// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {IFreezable} from "../../src/interfaces/IFreezable.sol";
import {TestOnboardingToken} from "../../src/examples/wallet-onboarding/TestOnboardingToken.sol";

contract TestOnboardingTokenTest is Test {
    event WhitelistUpdated(address indexed account, bool allowed);

    TestOnboardingToken internal token;

    address internal admin = makeAddr("admin");
    address internal predicateFreezer = makeAddr("predicateFreezer");
    address internal predicateOnboarder = makeAddr("predicateOnboarder");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal stranger = makeAddr("stranger");

    uint256 internal constant AMOUNT = 1000e6;

    function setUp() public {
        token = new TestOnboardingToken("Onboarding Test USD", "otUSD", admin, predicateFreezer, predicateOnboarder);
    }

    function _onboard(
        address account
    ) internal {
        vm.prank(predicateOnboarder);
        token.addToWhitelist(_single(account));
    }

    function _offboard(
        address account
    ) internal {
        vm.prank(predicateOnboarder);
        token.revokeFromWhitelist(_single(account));
    }

    function _single(
        address account
    ) internal pure returns (address[] memory accounts) {
        accounts = new address[](1);
        accounts[0] = account;
    }

    function test_LagoonSurfaceSelectors() public {
        assertEq(TestOnboardingToken.isAllowed.selector, bytes4(keccak256("isAllowed(address)")));
        assertEq(TestOnboardingToken.addToWhitelist.selector, bytes4(keccak256("addToWhitelist(address[])")));
        assertEq(TestOnboardingToken.revokeFromWhitelist.selector, bytes4(keccak256("revokeFromWhitelist(address[])")));
        assertEq(TestOnboardingToken.version.selector, bytes4(keccak256("version()")));
        assertEq(TestOnboardingToken.OnlyWhitelistManager.selector, bytes4(keccak256("OnlyWhitelistManager(address)")));
        assertEq(TestOnboardingToken.AddressNotAllowed.selector, bytes4(keccak256("AddressNotAllowed(address)")));
    }

    function test_RolesAssigned() public {
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.FREEZE_MANAGER_ROLE(), predicateFreezer));
        assertTrue(token.hasRole(token.WHITELIST_MANAGER_ROLE(), predicateOnboarder));
        assertFalse(token.hasRole(token.WHITELIST_MANAGER_ROLE(), admin));
    }

    function test_ConstructorRejectsZeroAddresses() public {
        vm.expectRevert(TestOnboardingToken.ZeroAddress.selector);
        new TestOnboardingToken("T", "T", address(0), predicateFreezer, predicateOnboarder);

        vm.expectRevert(TestOnboardingToken.ZeroAddress.selector);
        new TestOnboardingToken("T", "T", admin, predicateFreezer, address(0));

        vm.expectRevert(IFreezable.ZeroFreezeManager.selector);
        new TestOnboardingToken("T", "T", admin, address(0), predicateOnboarder);
    }

    function test_VersionIsReadable() public {
        assertGt(bytes(token.version()).length, 0);
    }

    function testFuzz_UnlistedAddressIsNotAllowed(
        address probe
    ) public {
        assertFalse(token.isAllowed(probe));
    }

    function test_AddToWhitelistAllowsAndEmits() public {
        vm.expectEmit(true, false, false, true, address(token));
        emit WhitelistUpdated(alice, true);
        _onboard(alice);

        assertTrue(token.isAllowed(alice));
    }

    function test_AddToWhitelistIsIdempotent() public {
        _onboard(alice);

        vm.recordLogs();
        _onboard(alice);

        assertEq(vm.getRecordedLogs().length, 0);
        assertTrue(token.isAllowed(alice));
    }

    function test_RevokeFromWhitelistDisallowsAndEmits() public {
        _onboard(alice);

        vm.expectEmit(true, false, false, true, address(token));
        emit WhitelistUpdated(alice, false);
        _offboard(alice);

        assertFalse(token.isAllowed(alice));
    }

    function test_RevokeUnlistedIsNoop() public {
        vm.recordLogs();
        _offboard(alice);

        assertEq(vm.getRecordedLogs().length, 0);
        assertFalse(token.isAllowed(alice));
    }

    function test_BatchWhitelistWrites() public {
        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;

        vm.prank(predicateOnboarder);
        token.addToWhitelist(accounts);
        assertTrue(token.isAllowed(alice));
        assertTrue(token.isAllowed(bob));

        vm.prank(predicateOnboarder);
        token.revokeFromWhitelist(accounts);
        assertFalse(token.isAllowed(alice));
        assertFalse(token.isAllowed(bob));
    }

    function test_AddToWhitelistRequiresRole() public {
        address[] memory accounts = _single(alice);

        vm.expectRevert(abi.encodeWithSelector(TestOnboardingToken.OnlyWhitelistManager.selector, stranger));
        vm.prank(stranger);
        token.addToWhitelist(accounts);
    }

    function test_RevokeFromWhitelistRequiresRole() public {
        _onboard(alice);
        address[] memory accounts = _single(alice);

        vm.expectRevert(abi.encodeWithSelector(TestOnboardingToken.OnlyWhitelistManager.selector, admin));
        vm.prank(admin);
        token.revokeFromWhitelist(accounts);
    }

    function test_RoleRehearsalSucceedsForManager() public {
        address[] memory accounts = _single(address(uint160(uint256(keccak256("random probe")))));

        vm.prank(predicateOnboarder);
        (bool ok,) = address(token).call(abi.encodeCall(TestOnboardingToken.addToWhitelist, (accounts)));
        assertTrue(ok);
    }

    function test_AdminCanGrantWhitelistManager() public {
        bytes32 role = token.WHITELIST_MANAGER_ROLE();
        vm.prank(admin);
        token.grantRole(role, stranger);

        vm.prank(stranger);
        token.addToWhitelist(_single(alice));
        assertTrue(token.isAllowed(alice));
    }

    function test_MintToUnlistedReverts() public {
        vm.expectRevert(abi.encodeWithSelector(TestOnboardingToken.AddressNotAllowed.selector, alice));
        vm.prank(admin);
        token.mint(alice, AMOUNT);
    }

    function test_MintToOnboardedSucceeds() public {
        _onboard(alice);

        vm.prank(admin);
        token.mint(alice, AMOUNT);

        assertEq(token.balanceOf(alice), AMOUNT);
    }

    function test_MintRequiresAdmin() public {
        _onboard(alice);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, token.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(stranger);
        token.mint(alice, AMOUNT);
    }

    function test_TransferToUnlistedReverts() public {
        _onboard(alice);
        vm.prank(admin);
        token.mint(alice, AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(TestOnboardingToken.AddressNotAllowed.selector, bob));
        vm.prank(alice);
        token.transfer(bob, 1);
    }

    function test_FullOnboardingLifecycle() public {
        _onboard(alice);
        _onboard(bob);
        vm.prank(admin);
        token.mint(alice, AMOUNT);

        vm.prank(alice);
        token.transfer(bob, 100);
        assertEq(token.balanceOf(bob), 100);

        _offboard(alice);

        vm.expectRevert(abi.encodeWithSelector(TestOnboardingToken.AddressNotAllowed.selector, alice));
        vm.prank(alice);
        token.transfer(bob, 1);

        vm.expectRevert(abi.encodeWithSelector(TestOnboardingToken.AddressNotAllowed.selector, alice));
        vm.prank(bob);
        token.transfer(alice, 1);

        _onboard(alice);
        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.balanceOf(bob), 101);
    }

    function test_TransferFromChecksOwnerAndRecipient() public {
        _onboard(alice);
        _onboard(bob);
        vm.prank(admin);
        token.mint(alice, AMOUNT);

        vm.prank(alice);
        token.approve(stranger, 100);

        vm.prank(stranger);
        token.transferFrom(alice, bob, 50);
        assertEq(token.balanceOf(bob), 50);

        _offboard(bob);
        vm.expectRevert(abi.encodeWithSelector(TestOnboardingToken.AddressNotAllowed.selector, bob));
        vm.prank(stranger);
        token.transferFrom(alice, bob, 50);
    }

    function test_BurnIgnoresWhitelist() public {
        _onboard(alice);
        vm.prank(admin);
        token.mint(alice, AMOUNT);
        _offboard(alice);

        vm.prank(admin);
        token.burn(alice, AMOUNT);

        assertEq(token.balanceOf(alice), 0);
    }

    function test_FreezeAppliesToOnboardedAccounts() public {
        _onboard(alice);
        _onboard(bob);
        vm.prank(admin);
        token.mint(alice, AMOUNT);

        vm.prank(predicateFreezer);
        token.freezeAccounts(_single(alice));

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        vm.prank(alice);
        token.transfer(bob, 1);

        vm.prank(predicateFreezer);
        token.unfreezeAccounts(_single(alice));

        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.balanceOf(bob), 1);
    }

    function test_FrozenOnboardedRecipientCannotReceiveMint() public {
        _onboard(alice);
        vm.prank(predicateFreezer);
        token.freeze(alice);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        vm.prank(admin);
        token.mint(alice, AMOUNT);
    }

    function test_WhitelistManagerCannotFreezeOrMint() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                predicateOnboarder,
                token.FREEZE_MANAGER_ROLE()
            )
        );
        vm.prank(predicateOnboarder);
        token.freeze(alice);

        _onboard(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, predicateOnboarder, token.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(predicateOnboarder);
        token.mint(alice, AMOUNT);
    }
}
