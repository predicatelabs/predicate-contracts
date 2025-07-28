// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {PredicateMessage} from "../src/interfaces/IPredicateClient.sol";
import {Task, Attestation} from "../src/interfaces/IPredicateRegistry.sol";
import {MetaCoin} from "../src/examples/inheritance/MetaCoin.sol";
import "./helpers/PredicateRegistrySetup.sol";

contract MetaCoinTest is PredicateRegistrySetup {
    // meta coin contract
    MetaCoin metaCoinContract;

    // test accounts
    address testSender;
    uint256 testSenderPk;

    address testReceiver;
    uint256 testReceiverPk;

    function setUp() public override {
        // setup predicate registry
        super.setUp();

        // setup test accounts
        (testSender, testSenderPk) = makeAddrAndKey("testSender");
        (testReceiver, testReceiverPk) = makeAddrAndKey("testReceiver");
        
        // deploy meta coin contract
        metaCoinContract = new MetaCoin(owner, address(predicateRegistry), policyOne);
    }

    function testMetaCoinTransferWithAttestation() public {
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
                policy: policyOne,
                expiration: expireByTime
            })
        );

        bytes memory signature;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attestorOnePk, messageHash);
        signature = abi.encodePacked(r, s, v);

        Attestation memory attestation = Attestation({
            uuid: uuid,
            expiration: expireByTime,
            attestor: attestorOne,
            signature: signature
        });

        vm.prank(testSender);
        metaCoinContract.sendCoin(testReceiver, amount, attestation);
        assertEq(metaCoinContract.getBalance(testReceiver), 10, "receiver balance should be 10 after receiving");
        assertEq(
            metaCoinContract.getBalance(testSender), 9_999_999_999_990, "sender balance should be 9900 after sending"
        );
    }
}
