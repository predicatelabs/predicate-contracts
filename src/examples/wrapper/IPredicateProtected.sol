// SPDX-License-Identifier: MIT
// Tells the Solidity compiler to compile only from v0.8.13 to v0.9.0
pragma solidity ^0.8.12;

interface IPredicateProtected {
    function getPredicateWrapper() external view returns (address);
    function setPredicateWrapper(
        address _predicateWrapperAddress
    ) external;
    function enablePredicateWrapper() external;
    function disablePredicateWrapper() external;
}
