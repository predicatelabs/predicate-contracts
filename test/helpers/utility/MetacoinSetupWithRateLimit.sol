// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "./TestStorage.sol";
import "../DummyToken.sol";
import {MetaCoinWithRateLimit} from "../../../src/examples/MetaCoinWithRateLimit.sol";
import {RateLimitParams} from "../../../src/interfaces/IRateLimiter.sol";
import {MockPriceAggregator} from "../../mocks/MockPriceAggregator.sol";

contract MetacoinSetupWithRateLimit is TestStorage {
    MetaCoinWithRateLimit public metaCoinContract;
    MockPriceAggregator public priceAggregator;

    function setUp() public {
        (testSender, testSenderPk) = makeAddrAndKey("testSender");
        (testReceiver, testReceiverPk) = makeAddrAndKey("testReceiver");

        vm.startPrank(testSender);
        metaCoinContract = new MetaCoinWithRateLimit();

        RateLimitParams memory rateLimitParams =
            RateLimitParams({maxAmount: uint256(100e6), duration: uint256(10), batchSize: uint64(2)});
        metaCoinContract.setRateLimitParams(rateLimitParams);

        priceAggregator = new MockPriceAggregator();
        priceAggregator.setPrice(address(metaCoinContract), 1e6);
        metaCoinContract.setPriceOracle(address(priceAggregator));

        ownableClientInterface = Ownable(address(metaCoinContract));
        vm.stopPrank();
    }
}
