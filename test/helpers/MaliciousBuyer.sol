// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { IERC20 } from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import { IBuyETHCallback } from '../../src/IBuyETHCallback.sol';
import { ISwapTokensCallback } from '../../src/ISwapTokensCallback.sol';
import 'forge-std/console.sol';

interface TokenBuyerLike {
    function buyETH(uint256 tokenAmountWAD) external;

    function buyETH(
        uint256 tokenAmountWAD,
        address to,
        bytes calldata data
    ) external;
}

interface TokenBuyerV2Like {
    function swapTokens(uint256 tokenAmountWAD) external;

    function swapTokens(
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
        address,
        uint256 amount,
        bytes calldata
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

contract MaliciousBuyerV2 is ISwapTokensCallback {
    TokenBuyerV2Like buyer;
    IERC20 token;
    bool calledTwice;
    bool reenterWithCallback;

    constructor(address _buyer, IERC20 _token) {
        buyer = TokenBuyerV2Like(_buyer);
        token = _token;
    }

    function attack(uint256 tokenAmountWAD) public {
        buyer.swapTokens(tokenAmountWAD);
    }

    function reenterBuyWithCallback(uint256 tokenAmountWAD) public {
        reenterWithCallback = true;
        buyer.swapTokens(tokenAmountWAD, address(this), '');
    }

    function reenterBuyNoCallback(uint256 tokenAmountWAD) public {
        reenterWithCallback = false;
        buyer.swapTokens(tokenAmountWAD, address(this), '');
    }

    function swapTokensCallback(
        address,
        uint256 amount,
        bytes calldata
    ) external payable {
        if (reenterWithCallback) {
            if (!calledTwice) {
                calledTwice = true;
                buyer.swapTokens(amount, address(this), '');
            } else {
                token.transfer(address(buyer), amount);
            }
        } else {
            token.approve(address(buyer), amount);
            buyer.swapTokens(amount);
        }
    }
}
