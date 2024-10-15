// SPDX-License-Identifier: MIT
// Tells the Solidity compiler to compile only from v0.8.13 to v0.9.0
pragma solidity ^0.8.12;

import {PredicateClient} from "../mixins/PredicateClient.sol";
import {PredicateMessage} from "../interfaces/IPredicateClient.sol";

// This is just a simple example of a coin-like contract.
// It is not ERC20 compatible and cannot be expected to talk to other
// coin/token contracts.

contract MetaCoin is PredicateClient {
    mapping(address => uint256) public balances;

    event Transfer(address indexed _from, address indexed _to, uint256 _value);

    constructor(address owner, address serviceManager) {
        balances[owner] = 10_000_000_000_000;
        setServiceManager(serviceManager);
        _transferOwnership(owner);
    }

    function sendCoin(address receiver, uint256 amount, PredicateMessage calldata predicateMessage) public {
        bytes memory encodedSigAndArgs = abi.encodeWithSignature("_sendCoin(address,uint256)", receiver, amount);
        require(_authorizeTransaction(predicateMessage, encodedSigAndArgs), "MetaCoin: unauthorized transaction");

        // business logic function that is protected
        _sendCoin(receiver, amount);
    }

    // business logic function that is protected
    function _sendCoin(address receiver, uint256 amount) internal {
        require(balances[msg.sender] >= amount, "MetaCoin: insufficient balance");
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
