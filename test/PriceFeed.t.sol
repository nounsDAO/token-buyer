// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import 'forge-std/Test.sol';
import { SafeCast } from 'openzeppelin-contracts/contracts/utils/math/SafeCast.sol';
import { PriceFeed } from '../src/PriceFeed.sol';
import { TestChainlinkAggregator } from './helpers/TestChainlinkAggregator.sol';

contract PriceFeedTest is Test {
    uint256 constant STALE_AFTER = 42 hours;
    uint256 constant PRICE_UPPER_BOUND = 100_000e18; // i.e. 100K tokens buy 1 ETH
    uint256 constant PRICE_LOWER_BOUND = 100e18; // i.e. 100 tokens buy 1 ETH

    PriceFeed feed;
    TestChainlinkAggregator chainlink;

    function setUp() public {
        chainlink = new TestChainlinkAggregator(18);
        feed = new PriceFeed(chainlink, STALE_AFTER, PRICE_LOWER_BOUND, PRICE_UPPER_BOUND);
    }

    function test_price_decimalsEqualWAD() public {
        chainlink.setDecimals(18);
        chainlink.setLatestRound(200e18, block.timestamp);
        feed = new PriceFeed(chainlink, STALE_AFTER, PRICE_LOWER_BOUND, PRICE_UPPER_BOUND);

        assertEq(feed.price(), 200e18);
    }

    function test_price_decimalsBelowWAD() public {
        chainlink.setDecimals(16);
        chainlink.setLatestRound(1_000e16, block.timestamp);
        feed = new PriceFeed(chainlink, STALE_AFTER, PRICE_LOWER_BOUND, PRICE_UPPER_BOUND);

        assertEq(feed.price(), 1_000e18);
    }

    function test_price_decimalsAboveWAD() public {
        chainlink.setDecimals(21);
        chainlink.setLatestRound(1_000e21, block.timestamp);
        feed = new PriceFeed(chainlink, STALE_AFTER, PRICE_LOWER_BOUND, PRICE_UPPER_BOUND);

        assertEq(feed.price(), 1_000e18);
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

    function test_price_revertsBelowLowerBound() public {
        int256 invalidLowPrice = SafeCast.toInt256(PRICE_LOWER_BOUND - 1);
        chainlink.setLatestRound(invalidLowPrice, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(PriceFeed.InvalidPrice.selector, invalidLowPrice));
        feed.price();
    }

    function test_price_revertsAboveUpperBound() public {
        int256 invalidHighPrice = SafeCast.toInt256(PRICE_UPPER_BOUND + 1);
        chainlink.setLatestRound(invalidHighPrice, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(PriceFeed.InvalidPrice.selector, invalidHighPrice));
        feed.price();
    }
}
