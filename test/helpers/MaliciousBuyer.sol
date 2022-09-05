// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import { IERC20 } from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import { IBuyETHCallback } from '../../src/IBuyETHCallback.sol';
import 'forge-std/console.sol';

interface TokenBuyerLike {
    function buyETH(uint256 tokenAmountWAD) external;

    function buyETH(
        uint256 tokenAmountWAD,
        address to,
        bytes calldata data
    ) external;
}

contract MaliciousBuyer is IBuyETHCallback {
    TokenBuyerLike buyer;
    IERC20 token;
    bool calledTwice;
    bool reenterWithCallback;

    constructor(address _buyer, IERC20 _token) {
        buyer = TokenBuyerLike(_buyer);
        token = _token;
    }

    function attack(uint256 tokenAmountWAD) public {
        buyer.buyETH(tokenAmountWAD);
    }

    receive() external payable {
        uint256 balance = token.balanceOf(address(this));
        if (balance > 0 && !calledTwice) {
            calledTwice = true;
            attack(balance);
        }
    }

    function reenterBuyWithCallback(uint256 tokenAmountWAD) public {
        reenterWithCallback = true;
        buyer.buyETH(tokenAmountWAD, address(this), '');
    }

    function reenterBuyNoCallback(uint256 tokenAmountWAD) public {
        reenterWithCallback = false;
        buyer.buyETH(tokenAmountWAD, address(this), '');
    }

    function buyETHCallback(
        address caller,
        uint256 amount,
        bytes calldata data
    ) external payable {
        if (reenterWithCallback) {
            if (!calledTwice) {
                calledTwice = true;
                buyer.buyETH(amount, address(this), '');
            } else {
                token.transfer(address(buyer), amount);
            }
        } else {
            token.approve(address(buyer), amount);
            buyer.buyETH(amount);
        }
    }
}
