// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import 'forge-std/Test.sol';
import { TokenBuyer } from '../src/TokenBuyer.sol';
import { TestERC20 } from './helpers/TestERC20.sol';
import { IOUToken } from '../src/IOUToken.sol';
import { TestPriceFeed } from './helpers/TestPriceFeed.sol';
import { MaliciousBuyer, TokenBuyerLike } from './helpers/MaliciousBuyer.sol';

contract TokenBuyerTest is Test {
    TokenBuyer buyer;
    TestERC20 paymentToken;
    IOUToken iou;
    TestPriceFeed priceFeed;
    uint256 baselinePaymentTokenAmount = 0;
    uint16 botIncentiveBPs = 0;

    address owner = address(42);
    address bot = address(99);
    address user = address(1234);

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

        uint256 price = buyer.price();

        assertEq(price, 1234 gwei);
    }

    function test_price_botIncentive50BPs() public {
        vm.prank(owner);
        buyer.setBotIncentiveBPs(50);

        priceFeed.setPrice(4242 gwei);

        uint256 price = buyer.price();

        // 4263.21 gwei
        assertEq(price, 426321 * 10**7);
    }

    function test_price_botIncentive2X() public {
        vm.prank(owner);
        buyer.setBotIncentiveBPs(10_000);

        priceFeed.setPrice(4242 gwei);

        uint256 price = buyer.price();

        assertEq(price, 8484 gwei);
    }

    function test_buyETH_botBuysExactBaselineAmount() public {
        // Say ETH is worth $2000, then the oracle price denominated in ETH would be
        // 1 / 2000 = 0.0005
        priceFeed.setPrice(0.0005 ether);
        vm.deal(address(buyer), 1 ether);
        paymentToken.mint(bot, toWAD(2000));
        vm.prank(owner);
        buyer.setBaselinePaymentTokenAmount(toWAD(2000));

        vm.startPrank(bot);
        paymentToken.approve(address(buyer), toWAD(2000));
        buyer.buyETH(toWAD(2000));
        vm.stopPrank();

        assertEq(bot.balance, 1 ether);
    }

    function test_buyETH_botCappedToBaselineAmount() public {
        priceFeed.setPrice(0.0005 ether);
        vm.deal(address(buyer), 1 ether);
        paymentToken.mint(bot, toWAD(4000));
        vm.prank(owner);
        buyer.setBaselinePaymentTokenAmount(toWAD(2000));

        vm.startPrank(bot);
        paymentToken.approve(address(buyer), toWAD(4000));
        buyer.buyETH(toWAD(4000));
        vm.stopPrank();

        assertEq(bot.balance, 1 ether);
        assertEq(paymentToken.balanceOf(bot), toWAD(2000));
    }

    function test_buyETH_revertsWhenContractHasInsufficientETH() public {
        priceFeed.setPrice(0.0005 ether);
        paymentToken.mint(bot, toWAD(2000));
        vm.prank(owner);
        buyer.setBaselinePaymentTokenAmount(toWAD(2000));
        assertEq(address(buyer).balance, 0);

        vm.prank(bot);
        paymentToken.approve(address(buyer), toWAD(2000));

        vm.prank(bot);
        vm.expectRevert(abi.encodeWithSelector(TokenBuyer.FailedSendingETH.selector, new bytes(0)));
        buyer.buyETH(toWAD(2000));
    }

    function test_buyETH_revertsWhenTokenApprovalInsufficient() public {
        priceFeed.setPrice(0.0005 ether);
        vm.deal(address(buyer), 1 ether);
        paymentToken.mint(bot, toWAD(2000));
        vm.prank(owner);
        buyer.setBaselinePaymentTokenAmount(toWAD(2000));

        vm.prank(bot);
        paymentToken.approve(address(buyer), toWAD(2000) - 1);

        vm.prank(bot);
        vm.expectRevert('ERC20: insufficient allowance');
        buyer.buyETH(toWAD(2000));
    }

    function test_buyETH_maliciousBuyerCantDoubleSpend() public {
        MaliciousBuyer attacker = new MaliciousBuyer(address(buyer), paymentToken);
        priceFeed.setPrice(0.0005 ether);
        vm.deal(address(buyer), 10 ether);
        paymentToken.mint(address(attacker), toWAD(4000));
        vm.prank(owner);
        buyer.setBaselinePaymentTokenAmount(toWAD(4000));

        vm.prank(address(attacker));
        paymentToken.approve(address(buyer), toWAD(4000));

        attacker.attack(toWAD(2000));

        assertEq(paymentToken.balanceOf(address(attacker)), 0);
        assertEq(address(attacker).balance, 2 ether);
    }

    function test_buyETH_maliciousBuyerCantExceedTokensNeeded() public {
        MaliciousBuyer attacker = new MaliciousBuyer(address(buyer), paymentToken);
        priceFeed.setPrice(0.0005 ether);
        vm.deal(address(buyer), 10 ether);
        paymentToken.mint(address(attacker), toWAD(4000));
        vm.prank(owner);
        buyer.setBaselinePaymentTokenAmount(toWAD(2000));

        vm.prank(address(attacker));
        paymentToken.approve(address(buyer), toWAD(4000));

        attacker.attack(toWAD(2000));

        assertEq(paymentToken.balanceOf(address(attacker)), toWAD(2000));
        assertEq(address(attacker).balance, 1 ether);
    }

    function test_sendOrMint_givenNoPaymentTokenBalancePayInIOUs() public {
        uint256 amount = toWAD(100_000);
        vm.prank(owner);
        buyer.sendOrMint(user, amount);

        assertEq(iou.balanceOf(user), amount);
        assertEq(paymentToken.balanceOf(user), 0);
    }

    function test_sendOrMint_givenEnoughPaymentTokenPaysInToken() public {
        uint256 amount = toWAD(100_000);
        paymentToken.mint(address(buyer), amount);
        vm.prank(owner);
        buyer.sendOrMint(user, amount);

        assertEq(iou.balanceOf(user), 0);
        assertEq(paymentToken.balanceOf(user), amount);
    }

    function test_sendOrMint_givenPartialPaymentTokenBalancePaysInBoth() public {
        uint256 amount = toWAD(100_000);
        paymentToken.mint(address(buyer), toWAD(42_000));
        vm.prank(owner);
        buyer.sendOrMint(user, amount);

        assertEq(iou.balanceOf(user), toWAD(58_000));
        assertEq(paymentToken.balanceOf(user), toWAD(42_000));
    }

    function test_sendOrMint_zeroDoesntRevert() public {
        vm.prank(owner);
        buyer.sendOrMint(user, 0);

        assertEq(iou.balanceOf(user), 0);
        assertEq(paymentToken.balanceOf(user), 0);
    }

    function test_redeem_givenEnoughPaymentTokenSendsFullAmount() public {
        uint256 amount = toWAD(100_000);
        vm.prank(address(buyer));
        iou.mint(user, amount);
        paymentToken.mint(address(buyer), amount);

        buyer.redeem(user);

        assertEq(iou.balanceOf(user), 0);
        assertEq(paymentToken.balanceOf(user), amount);
        assertEq(paymentToken.balanceOf(address(buyer)), 0);
    }

    function test_redeem_givenPartialPaymentTokenSendsPartialAmount() public {
        uint256 amount = toWAD(100_000);
        vm.prank(address(buyer));
        iou.mint(user, amount);
        paymentToken.mint(address(buyer), amount - 1);

        buyer.redeem(user);

        assertEq(iou.balanceOf(user), 1);
        assertEq(paymentToken.balanceOf(user), amount - 1);
        assertEq(paymentToken.balanceOf(address(buyer)), 0);
    }

    function test_redeem_givenNoPaymentTokenSendsNothing() public {
        uint256 amount = toWAD(100_000);
        vm.prank(address(buyer));
        iou.mint(user, amount);

        buyer.redeem(user);

        assertEq(iou.balanceOf(user), amount);
        assertEq(paymentToken.balanceOf(user), 0);
    }

    function test_redeem_givenNoIOUBalanceSendsNothing() public {
        paymentToken.mint(address(buyer), toWAD(100_000));

        buyer.redeem(user);

        assertEq(iou.balanceOf(user), 0);
        assertEq(paymentToken.balanceOf(user), 0);
        assertEq(paymentToken.balanceOf(address(buyer)), toWAD(100_000));
    }

    function test_redeem_withExplicitAmount_givenNoIOUBalanceDoesNothing() public {
        paymentToken.mint(address(buyer), toWAD(100_000));

        buyer.redeem(user, toWAD(100_000));

        assertEq(iou.balanceOf(user), 0);
        assertEq(paymentToken.balanceOf(user), 0);
        assertEq(paymentToken.balanceOf(address(buyer)), toWAD(100_000));
    }

    function test_redeem_withExplicitAmount_givenAmountHigherThanIOUsRedeemsIOUBalance() public {
        paymentToken.mint(address(buyer), toWAD(100_000));
        vm.prank(address(buyer));
        iou.mint(user, toWAD(42_000));

        buyer.redeem(user, toWAD(69_000));

        assertEq(iou.balanceOf(user), 0);
        assertEq(paymentToken.balanceOf(user), toWAD(42_000));
        assertEq(paymentToken.balanceOf(address(buyer)), toWAD(58_000));
    }

    function test_redeem_withExplicitAmount_givenAmountHigherThanIOUsAndPaymentTokenBalanceRedeemsAllTokenBalance()
        public
    {
        paymentToken.mint(address(buyer), toWAD(42_000));
        vm.prank(address(buyer));
        iou.mint(user, toWAD(69_000));

        buyer.redeem(user, toWAD(100_000));

        assertEq(iou.balanceOf(user), toWAD(27_000));
        assertEq(paymentToken.balanceOf(user), toWAD(42_000));
        assertEq(paymentToken.balanceOf(address(buyer)), 0);
    }

    function test_happyFlow_payingFullyInPaymentToken() public {
        priceFeed.setPrice(0.01 ether);
        vm.prank(owner);
        // 1% incentive
        buyer.setBotIncentiveBPs(100);
        // set buffer (100K)
        vm.prank(owner);
        buyer.setBaselinePaymentTokenAmount(toWAD(100_000));

        // fund bot and buyer
        paymentToken.mint(bot, toWAD(100_000));
        vm.deal(address(buyer), 1010 ether);

        // bots buy buffer (100K)
        vm.startPrank(bot);
        paymentToken.approve(address(buyer), toWAD(100_000));
        buyer.buyETH(toWAD(100_000));
        vm.stopPrank();
        assertEq(paymentToken.balanceOf(bot), 0);
        assertEq(bot.balance, 1010 ether);

        // send or mint (42K)
        vm.prank(owner);
        buyer.sendOrMint(user, toWAD(42_000));

        // user gets sent that amount right away
        assertEq(iou.balanceOf(user), 0);
        assertEq(paymentToken.balanceOf(user), toWAD(42_000));

        // fund bot and buyer again
        paymentToken.mint(bot, toWAD(42_000));
        // 424.2
        vm.deal(address(buyer), 4242 * 10**17);

        // bots can top off what's missing (bots buy 42K)
        vm.startPrank(bot);
        paymentToken.approve(address(buyer), toWAD(42_000));
        buyer.buyETH(toWAD(42_000));
        vm.stopPrank();
        assertEq(paymentToken.balanceOf(bot), 0);
        assertEq(bot.balance, 1010 ether + 4242 * 10**17);
    }

    function test_happyFlow_payingOverTheBuffer() public {
        priceFeed.setPrice(0.01 ether);
        vm.prank(owner);
        // 1% incentive
        buyer.setBotIncentiveBPs(100);
        // set buffer (100K)
        vm.prank(owner);
        buyer.setBaselinePaymentTokenAmount(toWAD(100_000));

        // fund bot and buyer
        paymentToken.mint(bot, toWAD(100_000));
        vm.deal(address(buyer), 1010 ether);

        // bots buy buffer (100K)
        vm.startPrank(bot);
        paymentToken.approve(address(buyer), toWAD(100_000));
        buyer.buyETH(toWAD(100_000));
        vm.stopPrank();
        assertEq(paymentToken.balanceOf(bot), 0);
        assertEq(bot.balance, 1010 ether);

        // send or mint (142K)
        vm.prank(owner);
        buyer.sendOrMint(user, toWAD(142_000));
        assertEq(iou.balanceOf(user), toWAD(42_000));
        assertEq(paymentToken.balanceOf(user), toWAD(100_000));

        // fund bot and buyer again
        paymentToken.mint(bot, toWAD(42_000));
        // 424.2
        vm.deal(address(buyer), 4242 * 10**17);

        // bots can top off what's missing (bots buy 42K)
        vm.startPrank(bot);
        paymentToken.approve(address(buyer), toWAD(42_000));
        buyer.buyETH(toWAD(42_000));
        vm.stopPrank();
        assertEq(paymentToken.balanceOf(bot), 0);
        assertEq(bot.balance, 1010 ether + 4242 * 10**17);

        // anyone can redeem user's remaining balance(42K)
        buyer.redeem(user);
        assertEq(iou.balanceOf(user), 0);
        assertEq(paymentToken.balanceOf(user), toWAD(142_000));

        // bots can top off what's missing (bots buy 100K)
        // fund bot and buyer again
        paymentToken.mint(bot, toWAD(100_000));
        vm.deal(address(buyer), 1010 ether);
        vm.startPrank(bot);
        paymentToken.approve(address(buyer), toWAD(100_000));
        buyer.buyETH(toWAD(100_000));
        vm.stopPrank();
        assertEq(paymentToken.balanceOf(bot), 0);
        assertEq(bot.balance, 1010 ether + 4242 * 10**17 + 1010 ether);
    }

    function toWAD(uint256 amount) public pure returns (uint256) {
        return amount * 10**18;
    }
}
