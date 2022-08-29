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
import { SafeCast } from 'openzeppelin-contracts/contracts/utils/math/SafeCast.sol';

/**
 * @notice Provides price data to {TokenBuyer}.
 */
contract PriceFeed is IPriceFeed {
    using SafeCast for int256;

    uint256 constant WAD_DECIMALS = 18;

    error StaleOracle(uint256 updatedAt);

    AggregatorV3Interface public immutable chainlink;
    uint8 public immutable decimals;
    uint256 public immutable staleAfter;
    uint256 public immutable decimalFactor;

    constructor(AggregatorV3Interface _chainlink, uint256 _staleAfter) {
        chainlink = _chainlink;
        decimals = chainlink.decimals();
        staleAfter = _staleAfter;

        uint256 decimalFactorTemp = 1;
        if (decimals < WAD_DECIMALS) {
            decimalFactorTemp = 10**(WAD_DECIMALS - decimals);
        } else if (decimals > WAD_DECIMALS) {
            decimalFactorTemp = 10**(decimals - WAD_DECIMALS);
        }
        decimalFactor = decimalFactorTemp;
    }

    /**
     * @return uin256 Token/ETH price in WAD format
     */
    function price() external view override returns (uint256) {
        (, int256 chainlinkPrice, , uint256 updatedAt, ) = chainlink.latestRoundData();

        if (updatedAt < block.timestamp - staleAfter) {
            revert StaleOracle(updatedAt);
        }

        return toWAD(chainlinkPrice.toUint256());
    }

    function toWAD(uint256 chainlinkPrice) internal view returns (uint256) {
        if (decimals == WAD_DECIMALS) {
            return chainlinkPrice;
        } else if (decimals < WAD_DECIMALS) {
            return chainlinkPrice * decimalFactor;
        } else {
            return chainlinkPrice / decimalFactor;
        }
    }
}
