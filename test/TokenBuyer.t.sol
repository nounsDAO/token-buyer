// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import 'forge-std/Test.sol';
import { TokenBuyer } from '../src/TokenBuyer.sol';
import { TestERC20 } from './helpers/TestERC20.sol';
import { IOUToken } from '../src/IOUToken.sol';
import { TestPriceFeed } from './helpers/TestPriceFeed.sol';

contract TokenBuyerTest is Test {
    TokenBuyer buyer;
    TestERC20 paymentToken;
    IOUToken iou;
    TestPriceFeed priceFeed;
    uint256 baselinePaymentTokenAmount = 0;
    uint16 botIncentiveBPs = 0;

    address owner = address(42);

    function setUp() public {
        paymentToken = new TestERC20('Payment Token', 'PAY');
        iou = new IOUToken('IOU Token', 'IOU', owner);
        priceFeed = new TestPriceFeed();

        buyer = new TokenBuyer(paymentToken, 18, iou, priceFeed, baselinePaymentTokenAmount, botIncentiveBPs, owner);

        vm.startPrank(owner);
        iou.grantRole(iou.MINTER_ROLE(), address(buyer));
        iou.grantRole(iou.BURNER_ROLE(), address(buyer));
        vm.stopPrank();
    }

    function test_setPriceFeed_revertsForNonOwner() public {
        TestPriceFeed newFeed = new TestPriceFeed();

        vm.expectRevert('Ownable: caller is not the owner');
        buyer.setPriceFeed(newFeed);
    }

    function test_setPriceFeed_worksForOwner() public {
        TestPriceFeed newFeed = new TestPriceFeed();

        assertTrue(address(newFeed) != address(buyer.priceFeed()));

        vm.prank(owner);
        buyer.setPriceFeed(newFeed);

        assertEq(address(buyer.priceFeed()), address(newFeed));
    }

    function test_tokenAmountNeeded_baselineAmountOnly() public {
        vm.prank(owner);
        buyer.setBaselinePaymentTokenAmount(toWAD(100_000));

        assertEq(buyer.tokenAmountNeeded(), toWAD(100_000));
    }

    function test_tokenAmountNeeded_iouSupplyOnly() public {
        vm.prank(address(buyer));
        iou.mint(address(1), toWAD(42_000));

        assertEq(buyer.tokenAmountNeeded(), toWAD(42_000));
    }

    function test_tokenAmountNeeded_paymentTokenBalanceOnly() public {
        paymentToken.mint(address(buyer), toWAD(42_000));

        assertEq(buyer.tokenAmountNeeded(), 0);
    }

    function test_tokenAmountNeeded_baselineAndPaymentTokenBalance() public {
        vm.prank(owner);
        buyer.setBaselinePaymentTokenAmount(toWAD(100_000));
        paymentToken.mint(address(buyer), toWAD(42_000));

        assertEq(buyer.tokenAmountNeeded(), toWAD(58_000));
    }

    function test_tokenAmountNeeded_baselineAndPaymentTokenBalanceAndIOUSupply() public {
        vm.prank(owner);
        buyer.setBaselinePaymentTokenAmount(toWAD(100_000));
        paymentToken.mint(address(buyer), toWAD(42_000));
        vm.prank(address(buyer));
        iou.mint(address(1), toWAD(11_000));

        assertEq(buyer.tokenAmountNeeded(), toWAD(69_000));
    }

    function test_price_botIncentiveZero() public {
        priceFeed.setPrice(1234 gwei);
        priceFeed.setDecimals(18);

        (uint256 price, uint8 decimals) = buyer.price();

        assertEq(price, 1234 gwei);
        assertEq(decimals, 18);
    }

    function test_price_botIncentive50BPs() public {
        vm.prank(owner);
        buyer.setBotIncentiveBPs(50);

        priceFeed.setPrice(4242 gwei);
        priceFeed.setDecimals(18);

        (uint256 price, uint8 decimals) = buyer.price();

        // 4263.21 gwei
        assertEq(price, 426321 * 10**7);
        assertEq(decimals, 18);
    }

    function test_price_botIncentive2X() public {
        vm.prank(owner);
        buyer.setBotIncentiveBPs(10_000);

        priceFeed.setPrice(4242 gwei);
        priceFeed.setDecimals(18);

        (uint256 price, uint8 decimals) = buyer.price();

        assertEq(price, 8484 gwei);
        assertEq(decimals, 18);
    }

    function toWAD(uint256 amount) public pure returns (uint256) {
        return amount * 10**18;
    }
}
