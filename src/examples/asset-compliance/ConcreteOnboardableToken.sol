// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import {Freezable} from "../../Freezable.sol";

contract ConcreteOnboardableToken is ERC20Upgradeable, Freezable, OwnableUpgradeable {
    mapping(address user => bool whitelisted) private _whitelisted;

    event WhitelistSet(address indexed user, bool indexed isWhitelisted);

    error AddressNotWhitelisted(address user);
    error ZeroAddress();

    constructor(
        string memory name_,
        string memory symbol_,
        address admin,
        address freezeManager,
        address whitelistOwner
    ) initializer {
        if (admin == address(0) || whitelistOwner == address(0)) revert ZeroAddress();

        __ERC20_init(name_, symbol_);
        __AccessControl_init();
        __Freezable_init(freezeManager);
        __Ownable_init(whitelistOwner);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function isWhitelisted(
        address user
    ) public view returns (bool) {
        return _whitelisted[user];
    }

    function whitelistUsers(
        address[] calldata users
    ) external onlyOwner {
        for (uint256 i; i < users.length; ++i) {
            _setWhitelisted(users[i], true);
        }
    }

    function unWhitelistUsers(
        address[] calldata users
    ) external onlyOwner {
        for (uint256 i; i < users.length; ++i) {
            _setWhitelisted(users[i], false);
        }
    }

    function userDepositCap() external pure returns (uint256) {
        return type(uint256).max;
    }

    function VAULT() external view returns (address) {
        return address(this);
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
        if (!isMint && !isBurn) _revertIfNotWhitelisted(from);
        if (!isBurn) _revertIfNotWhitelisted(to);

        super._update(from, to, value);
    }

    function _setWhitelisted(
        address user,
        bool whitelisted
    ) internal {
        if (user == address(0)) revert ZeroAddress();
        if (_whitelisted[user] == whitelisted) return;
        _whitelisted[user] = whitelisted;
        emit WhitelistSet(user, whitelisted);
    }

    function _revertIfNotWhitelisted(
        address user
    ) internal view {
        if (!_whitelisted[user]) revert AddressNotWhitelisted(user);
    }
}
