// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "forge-std/Test.sol";
import "../src/PriceAggregatorUniV3.sol";
import {IPriceAggregator} from "../src/interfaces/IPriceAggregator.sol";
import {MockPriceAggregator} from "./mocks/MockPriceAggregator.sol";
import {MockUniswapV3Pool} from "./mocks/MockUniswapV3Pool.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";

contract PriceAggregatorUniV3Test is Test {
    address _owner;
    address _usdc;
    address _weth;
    uint256 _defaultTwapPeriod;
    IPriceAggregator _priceAgg;
    PriceAggregatorUniV3 _priceAggImpl;
    MockUniswapV3Pool _wethPool;

    function setUp() public {
        _owner = makeAddr("owner");
        _usdc = makeAddr("usdc");
        _weth = makeAddr("weth");
        _wethPool = new MockUniswapV3Pool(_weth, _usdc, 3000);
        _defaultTwapPeriod = 5;
        _priceAggImpl = new PriceAggregatorUniV3(_owner, _weth, _usdc, _defaultTwapPeriod);
        _priceAgg = IPriceAggregator(address(_priceAggImpl));
        vm.prank(_owner);
        _priceAggImpl.setUSDCPoolForToken(_weth, address(_wethPool));
    }

    function testConstructorArgs() public {
        assertTrue(_owner == Ownable(address(_priceAgg)).owner());
        assertTrue(_weth == _priceAggImpl.WETH());
        assertTrue(_usdc == _priceAggImpl.USDC());
        assertTrue(_defaultTwapPeriod == _priceAggImpl.defaultTWAPPeriod());
    }

    function testOwnerOveriddenPoolForRoute() public {
        MockUniswapV3Pool wethPool = new MockUniswapV3Pool(_weth, _usdc, 4000);
        vm.prank(_owner);
        _priceAggImpl.setUSDCPoolForToken(_weth, address(wethPool));
        assertTrue(address(wethPool) == _priceAggImpl.getPoolForRoute(_weth, _usdc));
    }

    function testNotOwnerOveriddenPoolForRoute() public {
        MockUniswapV3Pool wethPool = new MockUniswapV3Pool(_weth, _usdc, 4000);
        vm.expectRevert();
        _priceAggImpl.setUSDCPoolForToken(_weth, address(wethPool));
    }

    function testRemoveTokenNotOwner() public {
        vm.expectRevert();
        _priceAggImpl.removeToken(_weth);
    }

    function testRemoveToken() public {
        vm.prank(_owner);
        _priceAggImpl.removeToken(_weth);
        assertFalse(_priceAgg.isTokenSupported(_weth));
    }

    function testTokenIDSupported() public {
        assertTrue(_priceAgg.isTokenSupported(_weth));
        assertFalse(_priceAgg.isTokenSupported(address(69)));
    }

    function testOwnerSetDefaultTwapPeriod() public {
        uint256 newPeriod = 10;
        vm.prank(_owner);
        _priceAggImpl.setDefaultTWAPPeriod(newPeriod);
        assertTrue(newPeriod == _priceAggImpl.defaultTWAPPeriod());
    }

    function testNotOwnerSetDefaultTwapPeriod() public {
        uint256 newPeriod = 10;
        vm.expectRevert();
        _priceAggImpl.setDefaultTWAPPeriod(newPeriod);
    }

    function getPriceTokenNotSupported() public {
        vm.expectRevert();
        _priceAgg.getPrice(address(69), 100);
    }

    function testOwnerAddingTokenSupport() public {
        address _wbtc = makeAddr("wbtc");
        MockUniswapV3Pool wbtcPool = new MockUniswapV3Pool(_wbtc, _usdc, 4000);
        vm.prank(_owner);
        _priceAggImpl.setUSDCPoolForToken(_wbtc, address(wbtcPool));
        assertTrue(address(wbtcPool) == _priceAggImpl.getPoolForRoute(_wbtc, _usdc));
    }

    function testNotOwnerAddingTokenSupport() public {
        address _wbtc = makeAddr("wbtc");
        MockUniswapV3Pool wbtcPool = new MockUniswapV3Pool(_wbtc, _usdc, 4000);
        vm.expectRevert();
        _priceAggImpl.setUSDCPoolForToken(_wbtc, address(wbtcPool));
    }
}

contract OwnershipPriceAggregatorUniV3Test is Test {
    address _owner;
    address _usdc;
    address _weth;
    uint256 _defaultTwapPeriod;
    PriceAggregatorUniV3 _priceAggImpl;

    function setUp() public {
        _owner = makeAddr("owner");
        _usdc = makeAddr("usdc");
        _weth = makeAddr("weth");
        _defaultTwapPeriod = 5;
        _priceAggImpl = new PriceAggregatorUniV3(_owner, _weth, _usdc, _defaultTwapPeriod);
    }

    function testOwnerIsInitializedFromConstructor() public {
        Ownable ownablePriceAgg = Ownable(address(_priceAggImpl));
        assertTrue(_owner == ownablePriceAgg.owner());
    }

    function testRandomAccountCannotTransferOwnership() public {
        vm.expectRevert();
        vm.prank(address(44));
        Ownable ownablePriceAgg = Ownable(address(_priceAggImpl));
        ownablePriceAgg.transferOwnership(address(33));
    }

    function testOwnerCanTransferOwnership() public {
        Ownable ownablePriceAgg = Ownable(address(_priceAggImpl));
        vm.prank(_owner);
        ownablePriceAgg.transferOwnership(address(33));
        assertTrue(address(33) == ownablePriceAgg.owner());
    }
}
