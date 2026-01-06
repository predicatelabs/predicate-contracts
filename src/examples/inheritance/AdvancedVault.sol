// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PredicateClient} from "../../mixins/PredicateClient.sol";
import {Attestation} from "../../interfaces/IPredicateRegistry.sol";

/**
 * @title AdvancedVault
 * @author Predicate Labs, Inc (https://predicate.io)
 * @notice Minimal example using PredicateClient for function and value-based authorization
 * @dev Demonstrates PredicateClient when your policy needs to validate:
 *      - WHICH function is called (withdraw vs transfer)
 *      - HOW MUCH value (amount limits)
 *      - WHAT parameters (recipient addresses)
 *
 *      The key difference: policies can enforce different rules per function
 */
contract AdvancedVault is PredicateClient, Ownable {
    mapping(address => uint256) public balances;

    event Deposit(address indexed user, uint256 amount);
    event Withdrawal(address indexed user, address indexed to, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 amount);

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
     * @notice Withdraw with amount validation
     * @dev Policy can enforce max withdrawal limits
     * @param _amount Amount to withdraw (validated by policy)
     * @param _attestation Must include encoded function data
     */
    function withdraw(
        uint256 _amount,
        Attestation calldata _attestation
    ) external {
        require(balances[msg.sender] >= _amount, "Insufficient balance");

        // Encode function signature and parameters for policy validation
        bytes memory encoded = abi.encodeWithSignature("_executeWithdraw(address,uint256)", msg.sender, _amount);

        // Advanced authorization with function details
        require(_authorizeTransaction(_attestation, encoded, msg.sender, 0), "Unauthorized");

        _executeWithdraw(msg.sender, _amount);
    }

    /**
     * @notice Withdraw to specific address with full parameter validation
     * @dev Policy validates BOTH recipient AND amount
     * @param _to Recipient address (validated by policy)
     * @param _amount Amount (validated by policy)
     * @param _attestation Must include encoded function data
     */
    function withdrawTo(
        address _to,
        uint256 _amount,
        Attestation calldata _attestation
    ) external {
        require(balances[msg.sender] >= _amount, "Insufficient balance");

        // Policy sees different function signature and parameters
        bytes memory encoded = abi.encodeWithSignature("_executeWithdraw(address,uint256)", _to, _amount);

        require(_authorizeTransaction(_attestation, encoded, msg.sender, 0), "Unauthorized");

        _executeWithdraw(_to, _amount);
    }

    /**
     * @notice Transfer between users - different policy rules than withdraw
     * @dev Shows how policies can have function-specific rules
     * @param _to Recipient
     * @param _amount Amount to transfer
     * @param _attestation Must include encoded transfer data
     */
    function transfer(
        address _to,
        uint256 _amount,
        Attestation calldata _attestation
    ) external {
        require(balances[msg.sender] >= _amount, "Insufficient balance");

        // Different function = different policy rules possible
        bytes memory encoded =
            abi.encodeWithSignature("_executeTransfer(address,address,uint256)", msg.sender, _to, _amount);

        require(_authorizeTransaction(_attestation, encoded, msg.sender, 0), "Unauthorized");

        _executeTransfer(msg.sender, _to, _amount);
    }

    /**
     * @notice Payable function example - policy validates msg.value
     * @dev Shows value-based authorization for payable functions
     * @param _lockPeriod Lock period parameter
     * @param _attestation Must include msg.value in validation
     */
    function depositAndLock(
        uint256 _lockPeriod,
        Attestation calldata _attestation
    ) external payable {
        require(msg.value > 0, "Must send ETH");

        bytes memory encoded =
            abi.encodeWithSignature("_executeLock(address,uint256,uint256)", msg.sender, msg.value, _lockPeriod);

        // Note: msg.value passed for validation
        require(_authorizeTransaction(_attestation, encoded, msg.sender, msg.value), "Unauthorized");

        balances[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
        // Lock logic would go here
    }

    // Internal execution functions
    function _executeWithdraw(
        address _to,
        uint256 _amount
    ) internal {
        balances[msg.sender] -= _amount;
        payable(_to).transfer(_amount);
        emit Withdrawal(msg.sender, _to, _amount);
    }

    function _executeTransfer(
        address _from,
        address _to,
        uint256 _amount
    ) internal {
        balances[_from] -= _amount;
        balances[_to] += _amount;
        emit Transfer(_from, _to, _amount);
    }

    function _executeLock(
        address _user,
        uint256 _amount,
        uint256 _period
    ) internal {
        // Lock implementation would go here
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
     * @dev Inherited from PredicateClient - no implementation needed
     */
    // function getPolicyID() external view returns (string memory) - inherited

    /**
     * @notice Required: Expose registry getter
     * @dev Inherited from PredicateClient - no implementation needed
     */
    // function getRegistry() external view returns (address) - inherited
}
