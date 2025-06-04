// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {Test, console} from "forge-std/Test.sol";
import {SignatureWithSaltAndExpiry} from "../../../src/interfaces/IPredicateRegistry.sol";
import "./TestStorage.sol";

contract OperatorTestPrep is TestStorage {
    modifier prepOperatorRegistration(
        bool shouldRegisterWithEigenContracts
    ) {
        // First Operator Registration
        vm.startPrank(operatorOne);
        IDelegationManager.OperatorDetails memory operatorDetails = IDelegationManager.OperatorDetails({
            earningsReceiver: operatorAddr,
            delegationApprover: operatorAddr,
            stakerOptOutWindowBlocks: 0
        });

        bytes32 messageHash = delegationManager.calculateOperatorAVSRegistrationDigestHash(
            operatorOne, address(predicateRegistry), keccak256("abc"), 10_000_000_000_000
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorOnePk, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        operatorSignature =
            SignatureWithSaltAndExpiry({signature: signature, salt: keccak256("abc"), expiry: 10_000_000_000_000});
        delegationManager.registerAsOperator(operatorDetails, "metadata uri");

        (, PredicateRegistry.OperatorStatus status) = predicateRegistry.operators(operatorOne);
        assertEq(uint256(status), 0);
        if (shouldRegisterWithEigenContracts) {
            predicateRegistry.registerOperatorToAVS(operatorOneAlias, operatorSignature);
        }
        vm.stopPrank();

        // Second Operator Registration
        vm.startPrank(operatorTwo);
        IDelegationManager.OperatorDetails memory operatorTwoDetails = IDelegationManager.OperatorDetails({
            earningsReceiver: operatorTwoAddr,
            delegationApprover: operatorTwoAddr,
            stakerOptOutWindowBlocks: 0
        });

        bytes32 messageHashTwo = delegationManager.calculateOperatorAVSRegistrationDigestHash(
            operatorTwo, address(predicateRegistry), keccak256("abc"), 10_000_000_000_000
        );

        (v, r, s) = vm.sign(operatorTwoPk, messageHashTwo);
        signature = abi.encodePacked(r, s, v);

        operatorTwoSignature =
            SignatureWithSaltAndExpiry({signature: signature, salt: keccak256("abc"), expiry: 10_000_000_000_000});

        delegationManager.registerAsOperator(operatorTwoDetails, "metadata uri");
        (, status) = predicateRegistry.operators(operatorTwo);
        assertEq(uint256(status), 0);
        vm.stopPrank();

        if (shouldRegisterWithEigenContracts) {
            vm.prank(operatorTwo);
            predicateRegistry.registerOperatorToAVS(operatorTwoAlias, operatorTwoSignature);
        }

        _;
    }
}
