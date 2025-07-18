// SPDX-License-Identifier: MIT
// Tells the Solidity compiler to compile only from v0.8.13 to v0.9.0
pragma solidity ^0.8.12;

import {PredicateClient} from "../../mixins/PredicateClient.sol";
import {PredicateMessage} from "../../interfaces/IPredicateClient.sol";
import {IServiceManager} from "../../interfaces/IServiceManager.sol";

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

    function setServiceManager(
        address _serviceManager
    ) public {
        _setServiceManager(_serviceManager);
    }
}
