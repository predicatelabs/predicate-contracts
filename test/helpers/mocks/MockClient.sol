// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import {PredicateClient} from "src/mixins/PredicateClient.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockClient is PredicateClient, Ownable {
    uint256 public counter;

    constructor(address _owner, address _registry, string memory _policyID) Ownable(_owner) {
        _initPredicateClient(_registry, _policyID);
    }

    function incrementCounter() external onlyPredicateRegistry {
        counter++;
    }

    // @inheritdoc IPredicateClient
    function setPolicy(
        string calldata _policyID
    ) external onlyOwner {
        _setPolicy(_policyID);
    }

    // @inheritdoc IPredicateClient
    function setRegistry(
        address _registry
    ) public onlyOwner {
        _setRegistry(_registry);
    }

    fallback() external payable {
        revert("");
    }

    receive() external payable {
        revert("");
    }
}
