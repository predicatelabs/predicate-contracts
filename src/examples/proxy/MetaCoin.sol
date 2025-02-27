// SPDX-License-Identifier: MIT
// Tells the Solidity compiler to compile only from v0.8.13 to v0.9.0
pragma solidity ^0.8.12;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PredicateProtected} from "./PredicateProtected.sol";

contract MetaCoin is Ownable, PredicateProtected {
    mapping(address => uint256) public balances;

    event Transfer(address indexed _from, address indexed _to, uint256 _value);

    constructor(address _owner, address _predicateProxyAddress) Ownable(_owner) {
        balances[_owner] = 10_000_000_000_000;
        _setPredicateProxy(_predicateProxyAddress);
    }

    function sendCoin(address _sender, address _receiver, uint256 _amount) external payable onlyPredicateProxy {
        _sendCoin(_sender, _receiver, _amount);
    }

    function _sendCoin(address _sender, address _receiver, uint256 _amount) internal {
        require(balances[_sender] >= _amount, "MetaCoin: insufficient balance");
        balances[_sender] -= _amount;
        balances[_receiver] += _amount;
        emit Transfer(_sender, _receiver, _amount);
    }

    function getBalance(
        address _addr
    ) public view returns (uint256) {
        return balances[_addr];
    }

    function setPredicateProxy(
        address _predicateProxyAddress
    ) external onlyOwner {
        _setPredicateProxy(_predicateProxyAddress);
    }

    function enablePredicateProxy() external onlyOwner {
        _enablePredicateProxy();
    }

    function disablePredicateProxy() external onlyOwner {
        _disablePredicateProxy();
    }
}
