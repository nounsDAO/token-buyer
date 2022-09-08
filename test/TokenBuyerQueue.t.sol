// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import 'forge-std/Test.sol';
import { TokenBuyerQueue } from '../src/TokenBuyerQueue.sol';
import { PayerQueue } from '../src/PayerQueue.sol';
import { TestERC20 } from './helpers/TestERC20.sol';
import { TestPriceFeed } from './helpers/TestPriceFeed.sol';

contract TokenBuyerQueueTest is Test {

    TokenBuyerQueue buyer;
    TestERC20 paymentToken;
    TestPriceFeed priceFeed;
    uint256 baselinePaymentTokenAmount = 0;
    uint16 botIncentiveBPs = 0;
    address owner = address(42);
    address admin = address(43);
    address user1 = address(44);
    address user2 = address(45);
    address bot = address(46);
    PayerQueue payer;

    function setUp() public {
        vm.label(owner, 'owner');
        vm.label(admin, 'admin');
        vm.label(user1, 'user1');
        vm.label(user2, 'user2');
        vm.label(bot, 'bot');

        paymentToken = new TestERC20('Payment Token', 'PAY');
        priceFeed = new TestPriceFeed();
        payer = new PayerQueue(owner, paymentToken);

        buyer = new TokenBuyerQueue(
            paymentToken,
            priceFeed,
            baselinePaymentTokenAmount,
            0,
            10_000_000e18,
            botIncentiveBPs,
            0,
            10_000,
            owner,
            admin,
            address(payer)
        );
    }

    function test_oneUserDebt() public {
        // Say ETH is worth $2000, then the oracle price denominated in ETH would be
        // 1 / 2000 = 0.0005
        priceFeed.setPrice(0.0005 ether);
        vm.deal(address(buyer), 1 ether);

        vm.prank(owner);
        payer.sendOrMint(user1, 2000e18);

        paymentToken.mint(bot, 2000e18);
        vm.prank(bot);
        paymentToken.approve(address(buyer), 2000e18);

        vm.prank(bot);
        buyer.buyETH(2000e18);

        assertEq(paymentToken.balanceOf(user1), 2000e18);
    }

    function test_tenUserDebt() public {
        // Say ETH is worth $2000, then the oracle price denominated in ETH would be
        // 1 / 2000 = 0.0005
        priceFeed.setPrice(0.0005 ether);
        vm.deal(address(buyer), 10 ether);

        for (uint256 i = 0; i < 10; i++) {
            vm.prank(owner);
            payer.sendOrMint(user1, 2000e18);
        }

        paymentToken.mint(bot, 20000e18);
        vm.prank(bot);
        paymentToken.approve(address(buyer), 20000e18);

        vm.prank(bot);
        buyer.buyETH(20000e18);

        assertEq(paymentToken.balanceOf(user1), 20000e18);
    }
}