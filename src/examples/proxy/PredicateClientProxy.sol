// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {PredicateClient} from "../../mixins/PredicateClient.sol";
import {PredicateMessage} from "../../interfaces/IPredicateClient.sol";
import {IPredicateManager} from "../../interfaces/IPredicateManager.sol";

import {MetaCoin} from "./MetaCoin.sol";

contract PredicateClientProxy is PredicateClient {
    MetaCoin private _metaCoin;

    constructor(address _metaCoinContract, address _serviceManager, string memory _policyID) {
        _initPredicateClient(_serviceManager, _policyID);
        _metaCoin = MetaCoin(_metaCoinContract);
    }

    function proxySendCoin(address _receiver, uint256 _amount, PredicateMessage calldata _message) external payable {
        bytes memory encodedSigAndArgs = abi.encodeWithSignature("_sendCoin(address,uint256)", _receiver, _amount);
        require(
            _authorizeTransaction(_message, encodedSigAndArgs, msg.sender, msg.value),
            "MetaCoin: unauthorized transaction"
        );

        _metaCoin.sendCoin{value: msg.value}(msg.sender, _receiver, _amount);
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
