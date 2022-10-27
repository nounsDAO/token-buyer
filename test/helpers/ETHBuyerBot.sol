// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import 'forge-std/Test.sol';
import { IBuyETHCallback } from '../../src/IBuyETHCallback.sol';
import { IERC20 } from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

contract ETHBuyerBot is IBuyETHCallback, Test {
    address immutable payer;
    IERC20 immutable paymentToken;

    bool overrideTokenAmount;
    uint256 tokenAmountOverride;
    bytes dataToSend;
    address operator;

    constructor(
        address payer_,
        address paymentToken_,
        bytes memory dataToSend_,
        address operator_
    ) {
        payer = payer_;
        paymentToken = IERC20(paymentToken_);
        dataToSend = dataToSend_;
        operator = operator_;
    }

    function buyETHCallback(
        address caller,
        uint256 amount,
        bytes memory data
    ) external payable override {
        assertEq(caller, operator);
        assertEq(data, dataToSend);

        if (overrideTokenAmount) {
            amount = tokenAmountOverride;
        }
        paymentToken.transfer(address(payer), amount);
    }

    function setOverrideTokenAmount(bool overrideTokenAmount_) external {
        overrideTokenAmount = overrideTokenAmount_;
    }

    function setTokenAmountOverride(uint256 tokenAmountOverride_) external {
        tokenAmountOverride = tokenAmountOverride_;
    }
}
