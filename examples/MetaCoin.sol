// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MetaCoin is Ownable {
    mapping(address => uint256) public balances;

    event Transfer(address indexed _from, address indexed _to, uint256 _value);

    constructor(
        address _owner
    ) Ownable(_owner) {
        balances[_owner] = 10_000_000_000_000;
    }

    function sendCoin(address _receiver, uint256 _amount) external payable {
        _sendCoin(_receiver, _amount);
    }

    // business logic function that is protected
    function _sendCoin(address _receiver, uint256 _amount) internal {
        require(balances[msg.sender] >= _amount, "MetaCoin: insufficient balance");
        balances[msg.sender] -= _amount;
        balances[_receiver] += _amount;
        emit Transfer(msg.sender, _receiver, _amount);
    }

    function getBalance(
        address _addr
    ) public view returns (uint256) {
        return balances[_addr];
    }
}
