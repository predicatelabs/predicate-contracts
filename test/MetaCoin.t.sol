// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./helpers/utility/TestUtils.sol";
import "./helpers/utility/MetaCoinTestSetup.sol";
import "./helpers/utility/OperatorTestPrep.sol";
import {PredicateMessage} from "../src/interfaces/IPredicateClient.sol";
import "forge-std/console.sol";

contract MetaCoinTest is OperatorTestPrep, MetaCoinTestSetup {
    modifier permissionedOperators() {
        vm.startPrank(address(this));
        address[] memory operators = new address[](2);
        operators[0] = operatorOne;
        operators[1] = operatorTwo;
        predicateRegistry.addPermissionedOperators(operators);
        vm.stopPrank();
        _;
    }

    function testMetaCoinTransferWithPredicateMessage() public permissionedOperators prepOperatorRegistration(true) {
        uint256 expireByTime = block.timestamp + 100;
        string memory taskId = "unique-identifier";
        uint256 amount = 10;

        bytes32 messageHash = predicateRegistry.hashTaskWithExpiry(
            Task({
                taskId: taskId,
                msgSender: testSender,
                target: address(metaCoinContract),
                value: 0,
                encodedSigAndArgs: abi.encodeWithSignature("_sendCoin(address,uint256)", testReceiver, amount),
                quorumThresholdCount: 1,
                expireByTime: expireByTime
            }),
            policyID
        );

        bytes memory signature;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorOneAliasPk, messageHash);
        signature = abi.encodePacked(r, s, v);

        address[] memory signerAddresses = new address[](1);
        bytes[] memory operatorSignatures = new bytes[](1);
        signerAddresses[0] = operatorOneAlias;
        operatorSignatures[0] = signature;
        PredicateMessage memory message = PredicateMessage({
            taskId: taskId,
            expireByTime: expireByTime,
            signerAddresses: signerAddresses,
            signatures: operatorSignatures
        });
        vm.prank(testSender);
        metaCoinContract.sendCoin(testReceiver, amount, message);
        assertEq(metaCoinContract.getBalance(testReceiver), 10, "receiver balance should be 10 after receiving");
        assertEq(
            metaCoinContract.getBalance(testSender), 9_999_999_999_990, "sender balance should be 9900 after sending"
        );
    }
}
