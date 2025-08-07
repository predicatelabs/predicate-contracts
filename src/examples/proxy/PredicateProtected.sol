// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {PredicateClientProxy} from "./PredicateClientProxy.sol";
import {IPredicateProtected} from "./IPredicateProtected.sol";

abstract contract PredicateProtected is IPredicateProtected {
    // note: this should be namespaced storage in a real impl
    bool private _predicateProxyEnabled;
    PredicateClientProxy private _predicateProxy;

    event PredicateProxySet(address indexed _predicateProxy);
    event PredicateProxyEnabled();
    event PredicateProxyDisabled();

    modifier onlyPredicateProxy() {
        if (_predicateProxyEnabled) {
            require(address(_predicateProxy) != address(0), "PredicateProtected: predicate proxy not set");
            require(
                msg.sender == address(_predicateProxy),
                "PredicateProtected: only predicate proxy can call this function"
            );
        }
        _;
    }

    function getPredicateProxy() external view returns (address) {
        return address(_predicateProxy);
    }

    function _setPredicateProxy(
        address _predicateProxyAddress
    ) internal {
        _predicateProxy = PredicateClientProxy(_predicateProxyAddress);
        emit PredicateProxySet(_predicateProxyAddress);
    }

    function _enablePredicateProxy() internal {
        _predicateProxyEnabled = true;
        emit PredicateProxyEnabled();
    }

    function _disablePredicateProxy() internal {
        _predicateProxyEnabled = false;
        emit PredicateProxyDisabled();
    }
}
