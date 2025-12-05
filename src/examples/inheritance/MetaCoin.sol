// SPDX-License-Identifier: MIT
// Tells the Solidity compiler to compile only from v0.8.13 to v0.9.0
pragma solidity ^0.8.12;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {PredicateClient} from "../../mixins/PredicateClient.sol";
import {PredicateMessage} from "../../interfaces/IPredicateClient.sol";
import {IPredicateManager} from "../../interfaces/IPredicateManager.sol";

contract MetaCoin is PredicateClient, Ownable {
    mapping(address => uint256) public balances;

    event Transfer(address indexed _from, address indexed _to, uint256 _value);

    constructor(address _owner, address _serviceManager, string memory _policyID) Ownable(_owner) {
        balances[_owner] = 10_000_000_000_000;
        _initPredicateClient(_serviceManager, _policyID);
    }

    /// @notice Sends 1 MetaCoin to `_receiver`, authorized via Predicate.
    /// @param _receiver EVM address receiving the MetaCoin.
    /// @param solanaAddress 32-byte Solana public key associated with this transfer.
    function sendCoin(address _receiver, bytes32 solanaAddress, PredicateMessage calldata _message) external payable {
        bytes memory encodedSigAndArgs =
            abi.encodeWithSignature("_sendCoin(address,bytes32)", _receiver, solanaAddress);
        require(
            _authorizeTransaction(_message, encodedSigAndArgs, msg.sender, msg.value),
            "MetaCoin: unauthorized transaction"
        );

        // business logic function that is protected
        _sendCoin(_receiver, 1);
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
