// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {PredicateMessage} from "../src/interfaces/IPredicateClient.sol";
import {Task, Attestation} from "../src/interfaces/IPredicateRegistry.sol";
import {MetaCoin} from "../src/MetaCoin.sol";
import "./helpers/PredicateRegistrySetup.sol";

contract MetaCoinTest is PredicateRegistrySetup {

    function setUp() public override {
        // setup predicate registry
        super.setUp();

        // setup test accounts
        (testSender, testSenderPk) = makeAddrAndKey("testSender");
        (testReceiver, testReceiverPk) = makeAddrAndKey("testReceiver");
        
        // deploy meta coin contract
        metaCoinContract = new MetaCoin();
        metaCoinContract.initialize(owner);
    }

    function testMetaCoinTransferWithPredicateMessage() public {
        uint256 expireByTime = block.timestamp + 100;
        string memory uuid = "unique-identifier";
        uint256 amount = 10;
        bytes32 messageHash = predicateRegistry.hashTaskWithExpiry(
            Task({
                uuid: uuid,
                msgSender: testSender,
                target: address(metaCoinContract),
                msgValue: 0,
                encodedSigAndArgs: abi.encodeWithSignature("_sendCoin(address,uint256)", testReceiver, amount),
                policyID: policyOne,
                quorumThresholdCount: 1,
                expireByTime: expireByTime
            })
        );


        return keccak256(
            abi.encode(
                _task.uuid,
                _task.msgSender,
                msg.sender,
                _task.msgValue,
                _task.encodedSigAndArgs,
                _task.policy,
                _task.expiration
            )
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
