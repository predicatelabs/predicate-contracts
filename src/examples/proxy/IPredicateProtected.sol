// SPDX-License-Identifier: MIT
// Tells the Solidity compiler to compile only from v0.8.13 to v0.9.0
pragma solidity ^0.8.12;

interface IPredicateProtected {
    function getPredicateProxy() external view returns (address);
    function setPredicateProxy(
        address _predicateProxyAddress
    ) external;
    function enablePredicateProxy() external;
    function disablePredicateProxy() external;
}
