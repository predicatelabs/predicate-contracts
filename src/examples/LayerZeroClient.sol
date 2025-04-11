// SPDX-License-Identifier: MIT
// Tells the Solidity compiler to compile only from v0.8.13 to v0.9.0
pragma solidity ^0.8.12;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PredicateClient} from "../mixins/PredicateClient.sol";

contract PlumeLayerZeroClient is PredicateClient, Ownable {
    constructor(address _serviceManager, string memory _policyID, address _owner) Ownable(_owner) {
        _initPredicateClient(_serviceManager, _policyID);
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
