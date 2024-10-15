// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Ownable} from "openzeppelin/access/Ownable.sol";
import {RateLimiter} from "../mixins/RateLimiter.sol";

contract MetaCoinWithRateLimit is RateLimiter {
    mapping(address => uint256) public balances;

    error InsufficientBalance(address sender, uint256 requested, uint256 available);

    event Transfer(address indexed _from, address indexed _to, uint256 _value);

    constructor() {
        balances[msg.sender] = 10_000_000_000_000;
    }

    function sendCoin(address receiver, uint256 amount) public {
        if (!this.evaluateRateLimit(address(this), amount)) {
            revert("MetaCoinWithRateLimit: rate limit exceeded");
        }
        _sendCoin(receiver, amount);
    }

    function _sendCoin(address receiver, uint256 amount) internal {
        if (balances[msg.sender] < amount) {
            revert InsufficientBalance(msg.sender, amount, balances[msg.sender]);
        }
        balances[msg.sender] -= amount;
        balances[receiver] += amount;
        emit Transfer(msg.sender, receiver, amount);
    }

    function getBalance(
        address addr
    ) public view returns (uint256) {
        return balances[addr];
    }
}
