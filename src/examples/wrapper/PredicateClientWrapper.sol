// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {PredicateClient} from "../../mixins/PredicateClient.sol";
import {PredicateMessage} from "../../interfaces/IPredicateClient.sol";
import {IPredicateManager} from "../../interfaces/IPredicateManager.sol";

contract PredicateClientWrapper is PredicateClient {
    constructor(address _serviceManager, string memory _policyID) {
        _initPredicateClient(_serviceManager, _policyID);
    }

    function sendCoinPredicate(
        address _sender,
        address _receiver,
        uint256 _amount,
        uint256 _value,
        PredicateMessage calldata _message
    ) external {
        // you can do some additional checks or pre-processing here
        // ...
        bytes memory encodedSigAndArgs = abi.encodeWithSignature("_sendCoin(address,uint256)", _receiver, _amount);
        require(
            _authorizeTransaction(_message, encodedSigAndArgs, _sender, _value),
            "PredicateClientWrapper: unauthorized transaction"
        );
    }

    function setPolicy(
        string memory _policyID
    ) external {
        _setPolicy(_policyID);
    }

    function setPredicateManager(
        address _predicateManager
    ) public {
        _setPredicateManager(_predicateManager);
    }
}
