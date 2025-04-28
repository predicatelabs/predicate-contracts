// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {Test, console} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {ServiceManager} from "../../../src/ServiceManager.sol";
import {SignatureWithSaltAndExpiry} from "../../../src/interfaces/IPredicateManager.sol";
import {PredicateClient} from "../../../src/mixins/PredicateClient.sol";
import {MockClient} from "../mocks/MockClient.sol";
import {MockProxy} from "../mocks/MockProxy.sol";
import {MockProxyAdmin} from "../mocks/MockProxyAdmin.sol";
import {MockStakeRegistry} from "../mocks/MockStakeRegistry.sol";
import {MockDelegationManager} from "../mocks/MockDelegationManager.sol";
import {IPauserRegistry} from "./../../helpers/eigenlayer/interfaces/IPauserRegistry.sol";
import {IDelegationManager} from "./../../helpers/eigenlayer/interfaces/IDelegationManager.sol";
import {MockStrategyManager} from "../mocks/MockStrategyManager.sol";
import {MockEigenPodManager} from "../mocks/MockEigenPodManager.sol";

contract TestStorage is Test {
    //Events
    event SetPolicy(address indexed client, string indexed policy);
    event RemovePolicy(address indexed client, string indexed policy);
    event OperatorRegistered(address indexed operator);
    event OperatorRemoved(address indexed operator);
    event OperatorsStakesUpdated(address[][] indexed operatorsPerQuorum, bytes indexed quorumNumbers);
    event StrategyAdded(address indexed strategy);
    event StrategyRemoved(address indexed strategy);
    event TaskExecuted(bytes32 indexed taskHash);

    //Interfaces
    MockProxyAdmin delegationManagerAdmin;
    MockDelegationManager delegationManager;
    MockDelegationManager delegationManagerImplementation;
    MockProxyAdmin serviceManagerAdmin;
    ServiceManager serviceManager;
    ServiceManager serviceManagerImplementation;
    MockClient client;
    MockStakeRegistry stakeRegistry;
    MockStrategyManager strategyManager;
    MockEigenPodManager eigenPodManager;
    Ownable ownableClientInterface;
    Ownable ownableServiceManagerInterface;

    //Addresses
    address aggregator = makeAddr("aggregator");
    address operator = makeAddr("operator");
    address randomAddr = makeAddr("randomAddr");
    address strategyAddrOne = makeAddr("strategyAddrOne");
    address strategyAddrTwo = makeAddr("strategyAddrTwo");
    address owner = makeAddr("owner");
    address operatorAddr = makeAddr("operatorAddr");
    address operatorTwoAddr = makeAddr("operatorTwoAddr");
    address slasher = makeAddr("slasher");
    address pauserRegistry = makeAddr("pauserRegistry");

    //TODO change "Alias" semantic to "
    address operatorOne;
    address operatorOneAlias;
    address operatorTwo;
    address operatorTwoAlias;
    address newAlias;
    address testSender;
    address testReceiver;

    //Integers
    uint256 operatorOnePk;
    uint256 operatorOneAliasPk;
    uint256 operatorTwoPk;
    uint256 operatorTwoAliasPk;
    uint256 testSenderPk;
    uint256 testReceiverPk;

    //Strings
    string policyID = "test-policy";

    //Signatures
    SignatureWithSaltAndExpiry operatorSignature;
    SignatureWithSaltAndExpiry operatorTwoSignature;
}
