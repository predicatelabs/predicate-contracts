// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {BasicPredicateClient} from "../../mixins/BasicPredicateClient.sol";
import {Attestation} from "../../interfaces/IPredicateRegistry.sol";

/**
 * @title BasicVault
 * @author Predicate Labs, Inc (https://predicate.io)
 * @notice Minimal example using BasicPredicateClient for simple WHO-based access control
 * @dev Demonstrates BasicPredicateClient when your policy only validates:
 *      - WHO can perform actions (allowlist/denylist)
 *      - WHEN they can act (time-based restrictions)
 *
 *      NOT for policies that need:
 *      - Function-specific rules (use AdvancedVault)
 *      - Value-based limits (use AdvancedVault)
 *      - Parameter validation (use AdvancedVault)
 */
contract BasicVault is BasicPredicateClient, Ownable {
    mapping(address => uint256) public balances;

    event Deposit(address indexed user, uint256 amount);
    event Withdrawal(address indexed user, uint256 amount);

    constructor(
        address _owner,
        address _registry,
        string memory _policyID
    ) Ownable(_owner) {
        _initPredicateClient(_registry, _policyID);
    }

    /**
     * @notice Deposit ETH - no attestation required
     */
    function deposit() external payable {
        balances[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice Withdraw with BasicPredicateClient authorization
     * @dev Policy validates WHO (sender) and target contract only.
     *      Cannot validate amount or function specifics.
     * @param _amount Amount to withdraw
     * @param _attestation Attestation from Predicate API (only from/to/chain fields)
     */
    function withdraw(
        uint256 _amount,
        Attestation calldata _attestation
    ) external {
        require(balances[msg.sender] >= _amount, "Insufficient balance");

        // Simple authorization - no encoding needed
        require(_authorizeTransaction(_attestation, msg.sender), "Unauthorized");

        balances[msg.sender] -= _amount;
        payable(msg.sender).transfer(_amount);

        emit Withdrawal(msg.sender, _amount);
    }

    /**
     * @notice Required: Set policy ID with access control
     * @dev Business logic contracts MUST implement this with proper access control
     */
    function setPolicyID(
        string memory _policyID
    ) external onlyOwner {
        _setPolicyID(_policyID);
    }

    /**
     * @notice Required: Set registry with access control
     * @dev Business logic contracts MUST implement this with proper access control
     */
    function setRegistry(
        address _registry
    ) external onlyOwner {
        _setRegistry(_registry);
    }

    /**
     * @notice Required: Expose policy ID getter
     * @dev Inherited from BasicPredicateClient - no implementation needed
     */
    // function getPolicyID() external view returns (string memory) - inherited

    /**
     * @notice Required: Expose registry getter
     * @dev Inherited from BasicPredicateClient - no implementation needed
     */
    // function getRegistry() external view returns (address) - inherited
}
