// SPDX-License-Identifier: MIT
// Tells the Solidity compiler to compile only from v0.8.13 to v0.9.0
pragma solidity ^0.8.12;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PredicateProtected} from "./PredicateProtected.sol";
import {PredicateMessage} from "../../interfaces/IPredicateClient.sol";

contract MetaCoin is Ownable, PredicateProtected {
    mapping(address => uint256) public balances;

    event Transfer(address indexed _from, address indexed _to, uint256 _value);

    constructor(address _owner, address _predicateWrapperAddress) Ownable(_owner) {
        balances[_owner] = 10_000_000_000_000;
        _setPredicateWrapper(_predicateWrapperAddress);
    }

    function sendCoin(
        address _receiver,
        uint256 _amount,
        PredicateMessage calldata _message
    ) external payable withPredicate(msg.sender, _receiver, _amount, msg.value, _message) {
        _sendCoin(_receiver, _amount);
    }

    function _sendCoin(address _receiver, uint256 _amount) internal {
        require(balances[msg.sender] >= _amount, "MetaCoin: insufficient balance");
        balances[msg.sender] -= _amount;
        balances[_receiver] += _amount;
        emit Transfer(msg.sender, _receiver, _amount);
    }

    function getBalance(
        address _addr
    ) external view returns (uint256) {
        return balances[_addr];
    }

    function setPredicateWrapper(
        address _predicateWrapperAddress
    ) external override onlyOwner {
        _setPredicateWrapper(_predicateWrapperAddress);
    }

    function enablePredicateWrapper() external override onlyOwner {
        _enablePredicateWrapper();
    }

    function disablePredicateWrapper() external override onlyOwner {
        _disablePredicateWrapper();
    }
}
