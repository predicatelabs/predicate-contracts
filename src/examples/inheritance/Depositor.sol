// SPDX-License-Identifier: MIT
// Tells the Solidity compiler to compile only from v0.8.13 to v0.9.0
pragma solidity ^0.8.12;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {PredicateClient} from "../../mixins/PredicateClient.sol";
import {PredicateMessage} from "../../interfaces/IPredicateClient.sol";
import {IPredicateManager} from "../../interfaces/IPredicateManager.sol";

contract Depositor is PredicateClient, Ownable {
    mapping(address => uint256) public balances;

    event Transfer(address indexed _from, address indexed _to, uint256 _value);

    constructor(address _owner, address _serviceManager, string memory _policyID) Ownable(_owner) {
        balances[_owner] = 10_000_000_000_000;
        _initPredicateClient(_serviceManager, _policyID);
    }

    function deposit(bytes32 _depositor, PredicateMessage calldata _message) external payable {
        bytes memory encodedSigAndArgs = abi.encodeWithSignature("_deposit(bytes32)", _depositor);
        require(
            _authorizeTransaction(_message, encodedSigAndArgs, msg.sender, msg.value),
            "MetaCoin: unauthorized transaction"
        );
    }

    function setPolicy(
        string memory _policyID
    ) external onlyOwner {
        _setPolicy(_policyID);
    }

    function setPredicateManager(
        address _predicateManager
    ) public onlyOwner {
        _setPredicateManager(_predicateManager);
    }

    function getBalance(
        address _addr
    ) public view returns (uint256) {
        return balances[_addr];
    }
}
