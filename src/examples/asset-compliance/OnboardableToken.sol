// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import {Freezable} from "../../Freezable.sol";

contract OnboardableToken is ERC20Upgradeable, Freezable {
    bytes32 public constant WHITELIST_MANAGER_ROLE = keccak256("WHITELIST_MANAGER_ROLE");

    mapping(address account => bool allowed) private _allowed;

    event WhitelistUpdated(address indexed account, bool allowed);

    error OnlyWhitelistManager(address whitelistManager);
    error AddressNotAllowed(address _address);
    error ZeroAddress();

    constructor(
        string memory name_,
        string memory symbol_,
        address admin,
        address freezeManager,
        address whitelistManager
    ) initializer {
        if (admin == address(0) || whitelistManager == address(0)) revert ZeroAddress();

        __ERC20_init(name_, symbol_);
        __AccessControl_init();
        __Freezable_init(freezeManager);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(WHITELIST_MANAGER_ROLE, whitelistManager);
    }

    function version() external pure returns (string memory) {
        return "1.0.0";
    }

    function isAllowed(
        address account
    ) public view returns (bool) {
        return _allowed[account];
    }

    function addToWhitelist(
        address[] calldata accounts
    ) external {
        _checkWhitelistManager();
        for (uint256 i; i < accounts.length; ++i) {
            _setAllowed(accounts[i], true);
        }
    }

    function revokeFromWhitelist(
        address[] calldata accounts
    ) external {
        _checkWhitelistManager();
        for (uint256 i; i < accounts.length; ++i) {
            _setAllowed(accounts[i], false);
        }
    }

    function mint(
        address to,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _mint(to, amount);
    }

    function burn(
        address from,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _burn(from, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        bool isMint = from == address(0);
        bool isBurn = to == address(0);

        if (!isMint) _revertIfFrozen(from);
        if (!isBurn) _revertIfFrozen(to);
        if (!isMint && !isBurn) _revertIfNotAllowed(from);
        if (!isBurn) _revertIfNotAllowed(to);

        super._update(from, to, value);
    }

    function _setAllowed(
        address account,
        bool allowed
    ) internal {
        if (_allowed[account] == allowed) return;
        _allowed[account] = allowed;
        emit WhitelistUpdated(account, allowed);
    }

    function _checkWhitelistManager() internal view {
        if (!hasRole(WHITELIST_MANAGER_ROLE, _msgSender())) revert OnlyWhitelistManager(_msgSender());
    }

    function _revertIfNotAllowed(
        address account
    ) internal view {
        if (!_allowed[account]) revert AddressNotAllowed(account);
    }
}
