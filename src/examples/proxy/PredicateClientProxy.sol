// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {PredicateClient} from "../../mixins/PredicateClient.sol";
import {Attestation} from "../../interfaces/IPredicateRegistry.sol";

import {MetaCoin} from "./MetaCoin.sol";

contract PredicateClientProxy is PredicateClient {
    MetaCoin private _metaCoin;

    constructor(address _metaCoinContract, address _serviceManager, string memory _policyId) {
        _initPredicateClient(_serviceManager, _policyId);
        _metaCoin = MetaCoin(_metaCoinContract);
    }

    function proxySendCoin(address _receiver, uint256 _amount, Attestation calldata _attestation) external payable {
        bytes memory encodedSigAndArgs = abi.encodeWithSignature("_sendCoin(address,uint256)", _receiver, _amount);
        require(
            _authorizeTransaction(_attestation, encodedSigAndArgs, msg.sender, msg.value),
            "MetaCoin: unauthorized transaction"
        );

        _metaCoin.sendCoin{value: msg.value}(msg.sender, _receiver, _amount);
    }

    function setPolicyId(
        string memory _policyId
    ) external {
        _setPolicyId(_policyId);
    }

    function setRegistry(
        address _registry
    ) public {
        _setRegistry(_registry);
    }
}
