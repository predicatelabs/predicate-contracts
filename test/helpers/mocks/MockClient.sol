// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import {PredicateClient} from "src/mixins/PredicateClient.sol";
import {IPredicateManager} from "src/interfaces/IPredicateManager.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockClient is PredicateClient, Ownable {
    uint256 public counter;

    constructor(address _owner, address _serviceManager, string memory _policyID) Ownable(_owner) {
        _initPredicateClient(_serviceManager, _policyID);
    }

    function incrementCounter() external onlyPredicateServiceManager {
        counter++;
    }

    // @inheritdoc IPredicateClient
    function setPolicy(
        string calldata _policyID
    ) external onlyOwner {
        _setPolicy(_policyID);
    }

    // @inheritdoc IPredicateClient
    function setPredicateManager(
        address _predicateManager
    ) public onlyOwner {
        _setPredicateManager(_predicateManager);
    }

    fallback() external payable {
        revert("");
    }

    receive() external payable {
        revert("");
    }
}
