// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Freezable} from "../../Freezable.sol";

/**
 * @title FreezableToken
 * @author Predicate Labs, Inc (https://predicate.io)
 * @notice Minimal token built on the {Freezable} base — the smallest example of enforcing a
 *         freeze list in `transfer`. See {FreezableStablecoin} for a full ERC-20 with pause,
 *         mint/burn, and seize.
 * @dev Frozen accounts can neither send nor receive. `freeze`/`unfreeze` are gated by
 *      FREEZE_MANAGER_ROLE; grant that role to Predicate's freezer to enable enforcement.
 */
contract FreezableToken is Freezable {
    mapping(address => uint256) public balances;

    event Transfer(address indexed from, address indexed to, uint256 amount);

    /**
     * @notice Initializes the token with an owner who receives initial supply and freeze manager role.
     * @param _owner Address that receives initial tokens and can freeze/unfreeze accounts.
     * @param _initialSupply Initial token supply minted to owner.
     */
    constructor(
        address _owner,
        uint256 _initialSupply
    ) {
        require(_owner != address(0), "FreezableToken: zero address owner");

        // Grant freeze manager role to owner (equivalent to __Freezable_init)
        _grantRole(FREEZE_MANAGER_ROLE, _owner);
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);

        balances[_owner] = _initialSupply;
    }

    /**
     * @notice Transfer tokens to another address.
     * @dev Reverts if sender or recipient is frozen.
     * @param _to Recipient address.
     * @param _amount Amount to transfer.
     */
    function transfer(
        address _to,
        uint256 _amount
    ) external {
        // Asset compliance: block frozen accounts
        _revertIfFrozen(msg.sender);
        _revertIfFrozen(_to);

        require(balances[msg.sender] >= _amount, "FreezableToken: insufficient balance");

        balances[msg.sender] -= _amount;
        balances[_to] += _amount;

        emit Transfer(msg.sender, _to, _amount);
    }

    /**
     * @notice Get balance of an account.
     * @param _account Address to query.
     * @return Token balance.
     */
    function balanceOf(
        address _account
    ) external view returns (uint256) {
        return balances[_account];
    }
}
