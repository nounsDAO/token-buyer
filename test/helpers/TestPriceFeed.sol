// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import { IPriceFeed } from '../../src/IPriceFeed.sol';

contract TestPriceFeed is IPriceFeed {
    uint256 _price;
    uint8 decimals;

    constructor() {}

    function price() external view returns (uint256, uint8) {
        return (_price, decimals);
    }

    function setPrice(uint256 newPrice) external {
        _price = newPrice;
    }

    function setDecimals(uint8 newDecimals) external {
        decimals = newDecimals;
    }
}
