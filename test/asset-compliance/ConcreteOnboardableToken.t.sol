// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {IFreezable} from "../../src/interfaces/IFreezable.sol";
import {ConcreteOnboardableToken} from "../../src/examples/asset-compliance/ConcreteOnboardableToken.sol";

contract ConcreteOnboardableTokenTest is Test {
    event WhitelistSet(address indexed user, bool indexed isWhitelisted);

    ConcreteOnboardableToken internal token;

    address internal admin = makeAddr("admin");
    address internal predicateFreezer = makeAddr("predicateFreezer");
    address internal predicateOnboarder = makeAddr("predicateOnboarder");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal stranger = makeAddr("stranger");

    uint256 internal constant AMOUNT = 1000e6;

    function setUp() public {
        token = new ConcreteOnboardableToken(
            "Concrete Onboardable USD", "coUSD", admin, predicateFreezer, predicateOnboarder
        );
    }

    function _onboard(
        address account
    ) internal {
        vm.prank(predicateOnboarder);
        token.whitelistUsers(_single(account));
    }

    function _offboard(
        address account
    ) internal {
        vm.prank(predicateOnboarder);
        token.unWhitelistUsers(_single(account));
    }

    function _single(
        address account
    ) internal pure returns (address[] memory accounts) {
        accounts = new address[](1);
        accounts[0] = account;
    }

    function test_ConcreteHookSurfaceSelectors() public {
        assertEq(ConcreteOnboardableToken.isWhitelisted.selector, bytes4(keccak256("isWhitelisted(address)")));
        assertEq(ConcreteOnboardableToken.whitelistUsers.selector, bytes4(keccak256("whitelistUsers(address[])")));
        assertEq(ConcreteOnboardableToken.unWhitelistUsers.selector, bytes4(keccak256("unWhitelistUsers(address[])")));
        assertEq(ConcreteOnboardableToken.userDepositCap.selector, bytes4(keccak256("userDepositCap()")));
        assertEq(ConcreteOnboardableToken.VAULT.selector, bytes4(keccak256("VAULT()")));
        assertEq(OwnableUpgradeable.owner.selector, bytes4(keccak256("owner()")));
        assertEq(
            OwnableUpgradeable.OwnableUnauthorizedAccount.selector,
            bytes4(keccak256("OwnableUnauthorizedAccount(address)"))
        );
        assertEq(ConcreteOnboardableToken.ZeroAddress.selector, bytes4(keccak256("ZeroAddress()")));
    }

    function test_DoesNotExposeLagoonSurface() public {
        (bool ok,) = address(token).staticcall(abi.encodeWithSignature("isAllowed(address)", alice));
        assertFalse(ok);

        vm.prank(predicateOnboarder);
        (ok,) = address(token).call(abi.encodeWithSignature("addToWhitelist(address[])", _single(alice)));
        assertFalse(ok);
    }

    function test_RolesAssigned() public {
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.FREEZE_MANAGER_ROLE(), predicateFreezer));
        assertEq(token.owner(), predicateOnboarder);
        assertFalse(token.hasRole(token.DEFAULT_ADMIN_ROLE(), predicateOnboarder));
    }

    function test_ConstructorRejectsZeroAddresses() public {
        vm.expectRevert(ConcreteOnboardableToken.ZeroAddress.selector);
        new ConcreteOnboardableToken("T", "T", address(0), predicateFreezer, predicateOnboarder);

        vm.expectRevert(ConcreteOnboardableToken.ZeroAddress.selector);
        new ConcreteOnboardableToken("T", "T", admin, predicateFreezer, address(0));

        vm.expectRevert(IFreezable.ZeroFreezeManager.selector);
        new ConcreteOnboardableToken("T", "T", admin, address(0), predicateOnboarder);
    }

    function test_DetectionViewsAreReadable() public {
        assertEq(token.userDepositCap(), type(uint256).max);
        assertEq(token.VAULT(), address(token));
    }

    function testFuzz_UnlistedAddressIsNotWhitelisted(
        address probe
    ) public {
        assertFalse(token.isWhitelisted(probe));
    }

    function test_WhitelistUsersWhitelistsAndEmits() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit WhitelistSet(alice, true);
        _onboard(alice);

        assertTrue(token.isWhitelisted(alice));
    }

    function test_WhitelistUsersIsIdempotent() public {
        _onboard(alice);

        vm.recordLogs();
        _onboard(alice);

        assertEq(vm.getRecordedLogs().length, 0);
        assertTrue(token.isWhitelisted(alice));
    }

    function test_UnWhitelistUsersRemovesAndEmits() public {
        _onboard(alice);

        vm.expectEmit(true, true, false, true, address(token));
        emit WhitelistSet(alice, false);
        _offboard(alice);

        assertFalse(token.isWhitelisted(alice));
    }

    function test_UnWhitelistUnlistedIsNoop() public {
        vm.recordLogs();
        _offboard(alice);

        assertEq(vm.getRecordedLogs().length, 0);
        assertFalse(token.isWhitelisted(alice));
    }

    function test_BatchWhitelistWrites() public {
        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;

        vm.prank(predicateOnboarder);
        token.whitelistUsers(accounts);
        assertTrue(token.isWhitelisted(alice));
        assertTrue(token.isWhitelisted(bob));

        vm.prank(predicateOnboarder);
        token.unWhitelistUsers(accounts);
        assertFalse(token.isWhitelisted(alice));
        assertFalse(token.isWhitelisted(bob));
    }

    function test_WhitelistUsersRejectsZeroAddress() public {
        vm.expectRevert(ConcreteOnboardableToken.ZeroAddress.selector);
        _onboard(address(0));

        vm.expectRevert(ConcreteOnboardableToken.ZeroAddress.selector);
        _offboard(address(0));
    }

    function test_WhitelistUsersRequiresOwner() public {
        address[] memory accounts = _single(alice);

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        token.whitelistUsers(accounts);
    }

    function test_UnWhitelistUsersRequiresOwner() public {
        _onboard(alice);
        address[] memory accounts = _single(alice);

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, admin));
        vm.prank(admin);
        token.unWhitelistUsers(accounts);
    }

    function test_OwnershipTransferMovesWhitelistControl() public {
        vm.prank(predicateOnboarder);
        token.transferOwnership(stranger);

        vm.prank(stranger);
        token.whitelistUsers(_single(alice));
        assertTrue(token.isWhitelisted(alice));

        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, predicateOnboarder)
        );
        _onboard(bob);
    }

    function test_MintToUnlistedReverts() public {
        vm.expectRevert(abi.encodeWithSelector(ConcreteOnboardableToken.AddressNotWhitelisted.selector, alice));
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

    function test_FullOnboardingLifecycle() public {
        _onboard(alice);
        _onboard(bob);
        vm.prank(admin);
        token.mint(alice, AMOUNT);

        vm.prank(alice);
        token.transfer(bob, 100);
        assertEq(token.balanceOf(bob), 100);

        _offboard(alice);

        vm.expectRevert(abi.encodeWithSelector(ConcreteOnboardableToken.AddressNotWhitelisted.selector, alice));
        vm.prank(alice);
        token.transfer(bob, 1);

        vm.expectRevert(abi.encodeWithSelector(ConcreteOnboardableToken.AddressNotWhitelisted.selector, alice));
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
        vm.expectRevert(abi.encodeWithSelector(ConcreteOnboardableToken.AddressNotWhitelisted.selector, bob));
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

    function test_OwnerCannotFreezeOrMint() public {
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
