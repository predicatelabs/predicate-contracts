// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {PredicateClient} from "../../mixins/PredicateClient.sol";
import {Attestation} from "../../interfaces/IPredicateRegistry.sol";

contract MetaCoin is PredicateClient, Ownable {
    mapping(address => uint256) public balances;

    event Transfer(address indexed _from, address indexed _to, uint256 _value);

    constructor(address _owner, address _registry, string memory _policyID) Ownable(_owner) {
        balances[_owner] = 10_000_000_000_000;
        _initPredicateClient(_registry, _policyID);
    }

    function sendCoin(address _receiver, uint256 _amount, Attestation calldata _attestation) external payable {
        bytes memory encodedSigAndArgs = abi.encodeWithSignature("_sendCoin(address,uint256)", _receiver, _amount);
        require(
            _authorizeTransaction(_attestation, encodedSigAndArgs, msg.sender, msg.value),
            "MetaCoin: unauthorized transaction"
        );

        // business logic function that is protected
        _sendCoin(_receiver, _amount);
    }

    function setPolicyID(
        string memory _policyID
    ) external onlyOwner {
        _setPolicyID(_policyID);
    }

    function setRegistry(
        address _registry
    ) public onlyOwner {
        _setRegistry(_registry);
    }

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
