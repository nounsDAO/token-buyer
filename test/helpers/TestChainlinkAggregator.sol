// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import { AggregatorV3Interface } from '../../src/AggregatorV3Interface.sol';

contract TestChainlinkAggregator is AggregatorV3Interface {
    uint8 public decimals;
    string public description;
    uint256 public version;
    int256 public _answer;
    uint256 public _updatedAt;

    constructor(uint8 _decimals) {
        decimals = _decimals;
    }

    // getRoundData and latestRoundData should both raise "No data present"
    // if they do not have data to report, instead of returning unset values
    // which could be misinterpreted as actual reported values.
    function getRoundData(uint80 _roundId)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {}

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        answer = _answer;
        updatedAt = _updatedAt;
    }

    function setDecimals(uint8 _decimals) public {
        decimals = _decimals;
    }

    function setLatestRound(int256 answer, uint256 updatedAt) public {
        _answer = answer;
        _updatedAt = updatedAt;
    }
}
