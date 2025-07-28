// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

interface IPredicateProtected {
    function getPredicateProxy() external view returns (address);
    function setPredicateProxy(
        address _predicateProxyAddress
    ) external;
    function enablePredicateProxy() external;
    function disablePredicateProxy() external;
}
