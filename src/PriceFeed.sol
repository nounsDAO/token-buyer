// SPDX-License-Identifier: GPL-3.0

/// @title PriceFeed

/*********************************
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 * ░░░░░░█████████░░█████████░░░ *
 * ░░░░░░██░░░████░░██░░░████░░░ *
 * ░░██████░░░████████░░░████░░░ *
 * ░░██░░██░░░████░░██░░░████░░░ *
 * ░░██░░██░░░████░░██░░░████░░░ *
 * ░░░░░░█████████░░█████████░░░ *
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 *********************************/

pragma solidity ^0.8.15;

import { IPriceFeed } from './IPriceFeed.sol';
import { AggregatorV3Interface } from './AggregatorV3Interface.sol';

contract PriceFeed is IPriceFeed {
    error StaleOracle(uint256 updatedAt);

    uint256 public constant STALE_AFTER = 4 hours;

    AggregatorV3Interface public immutable chainlink;
    uint8 public immutable decimals;

    constructor(AggregatorV3Interface _chainlink) {
        chainlink = _chainlink;
        decimals = chainlink.decimals();
    }

    /**
     * @return uin256 Token/ETH price
     * @return uint8 the price decimals
     */
    function price() external view returns (uint256, uint8) {
        (, int256 chainlinkPrice, , uint256 updatedAt, ) = chainlink.latestRoundData();

        if (updatedAt < block.timestamp - STALE_AFTER) {
            revert StaleOracle(updatedAt);
        }

        return (toUint256(chainlinkPrice), decimals);
    }

    function toUint256(int256 value) internal pure returns (uint256) {
        require(value >= 0);
        return uint256(value);
    }
}
