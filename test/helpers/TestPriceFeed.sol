// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { IPriceFeed } from '../../src/IPriceFeed.sol';

contract TestPriceFeed is IPriceFeed {
    uint256 _price;

    constructor() {}

    function price() external view returns (uint256) {
        return _price;
    }

    function setPrice(uint256 newPrice) external {
        _price = newPrice;
    }
}
