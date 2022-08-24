// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import 'forge-std/Test.sol';
import { PriceFeed } from '../src/PriceFeed.sol';
import { TestChainlinkAggregator } from './helpers/TestChainlinkAggregator.sol';

contract PriceFeedTest is Test {
    uint256 constant STALE_AFTER = 42 hours;

    PriceFeed feed;
    TestChainlinkAggregator chainlink;

    function setUp() public {
        chainlink = new TestChainlinkAggregator(18);
        feed = new PriceFeed(chainlink, STALE_AFTER);
    }

    function test_price_decimalsEqualWAD() public {
        chainlink.setDecimals(18);
        chainlink.setLatestRound(12345678987654321, block.timestamp);
        feed = new PriceFeed(chainlink, STALE_AFTER);

        assertEq(feed.price(), 12345678987654321);
    }

    function test_price_decimalsBelowWAD() public {
        chainlink.setDecimals(16);
        chainlink.setLatestRound(12345678987654321, block.timestamp);
        feed = new PriceFeed(chainlink, STALE_AFTER);

        assertEq(feed.price(), 1234567898765432100);
    }

    function test_price_decimalsAboveWAD() public {
        chainlink.setDecimals(21);
        chainlink.setLatestRound(12345678987654321, block.timestamp);
        feed = new PriceFeed(chainlink, STALE_AFTER);

        assertEq(feed.price(), 12345678987654);
    }

    function test_price_negativePriceReverts() public {
        chainlink.setLatestRound(-1234, block.timestamp);

        vm.expectRevert('SafeCast: value must be positive');
        feed.price();
    }

    function test_price_stalePriceReverts() public {
        uint256 staleTime = block.timestamp - STALE_AFTER - 1;
        chainlink.setLatestRound(1234, staleTime);

        vm.expectRevert(abi.encodeWithSelector(PriceFeed.StaleOracle.selector, staleTime));
        feed.price();
    }
}
