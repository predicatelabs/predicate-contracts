// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {PredicateClientProxy} from "./PredicateClientProxy.sol";
import {IPredicateProtected} from "./IPredicateProtected.sol";

abstract contract PredicateProtected is IPredicateProtected {
    /// @notice Struct to contain stateful values for PredicateProtected-type contracts
    /// @custom:storage-location erc7201:predicate.storage.PredicateProtected
    struct PredicateProtectedStorage {
        bool predicateProxyEnabled;
        PredicateClientProxy predicateProxy;
    }

    /// @notice the storage slot for the PredicateProtectedStorage struct
    /// @dev keccak256(abi.encode(uint256(keccak256("predicate.storage.PredicateProtected")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _PREDICATE_PROTECTED_STORAGE_SLOT =
        0x5e2f89b9a8b8c33b0c4efeb789eb49ad0c1a074e1e2f1c94e31ab1f8f1e00800;

    event PredicateProxySet(address indexed _predicateProxy);
    event PredicateProxyEnabled();
    event PredicateProxyDisabled();

    function _getPredicateProtectedStorage() private pure returns (PredicateProtectedStorage storage $) {
        assembly {
            $.slot := _PREDICATE_PROTECTED_STORAGE_SLOT
        }
    }

    modifier onlyPredicateProxy() {
        PredicateProtectedStorage storage $ = _getPredicateProtectedStorage();
        if ($.predicateProxyEnabled) {
            require(address($.predicateProxy) != address(0), "PredicateProtected: predicate proxy not set");
            require(
                msg.sender == address($.predicateProxy),
                "PredicateProtected: only predicate proxy can call this function"
            );
        }
        _;
    }

    function getPredicateProxy() external view returns (address) {
        return address(_getPredicateProtectedStorage().predicateProxy);
    }

    function _setPredicateProxy(
        address _predicateProxyAddress
    ) internal {
        PredicateProtectedStorage storage $ = _getPredicateProtectedStorage();
        $.predicateProxy = PredicateClientProxy(_predicateProxyAddress);
        emit PredicateProxySet(_predicateProxyAddress);
    }

    function _enablePredicateProxy() internal {
        PredicateProtectedStorage storage $ = _getPredicateProtectedStorage();
        $.predicateProxyEnabled = true;
        emit PredicateProxyEnabled();
    }

    function _disablePredicateProxy() internal {
        PredicateProtectedStorage storage $ = _getPredicateProtectedStorage();
        $.predicateProxyEnabled = false;
        emit PredicateProxyDisabled();
    }
}
