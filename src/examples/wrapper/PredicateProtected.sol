// SPDX-License-Identifier: MIT
// Tells the Solidity compiler to compile only from v0.8.13 to v0.9.0
pragma solidity ^0.8.12;

import {IPredicateClient, PredicateMessage} from "../../interfaces/IPredicateClient.sol";
import {PredicateClientWrapper} from "./PredicateClientWrapper.sol";
import {IPredicateProtected} from "./IPredicateProtected.sol";

abstract contract PredicateProtected is IPredicateProtected {
    // note: this should be namespaced storage in a real impl
    bool private _predicateWrapperEnabled;
    PredicateClientWrapper private _predicateWrapper;

    event PredicateWrapperSet(address indexed _predicateWrapper);
    event PredicateWrapperEnabled();
    event PredicateWrapperDisabled();

    modifier withPredicate(
        address _sender,
        address _receiver,
        uint256 _amount,
        uint256 _value,
        PredicateMessage calldata _message
    ) {
        if (_predicateWrapperEnabled) {
            require(address(_predicateWrapper) != address(0), "PredicateProtected: predicate wrapper not set");
            _predicateWrapper.sendCoinPredicate(_sender, _receiver, _amount, _value, _message);
        }
        _;
    }

    function getPredicateWrapper() external view returns (address) {
        return address(_predicateWrapper);
    }

    function _setPredicateWrapper(
        address _predicateWrapperAddress
    ) internal {
        _predicateWrapper = PredicateClientWrapper(_predicateWrapperAddress);
        emit PredicateWrapperSet(_predicateWrapperAddress);
    }

    function _enablePredicateWrapper() internal {
        _predicateWrapperEnabled = true;
        emit PredicateWrapperEnabled();
    }

    function _disablePredicateWrapper() internal {
        _predicateWrapperEnabled = false;
        emit PredicateWrapperDisabled();
    }
}
