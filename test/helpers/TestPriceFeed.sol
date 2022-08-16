// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import { IPriceFeed } from '../../src/IPriceFeed.sol';

contract TestPriceFeed is IPriceFeed {
    constructor() {}

    function price() external pure returns (uint256, uint8) {
        return (0, 18);
    }
}
