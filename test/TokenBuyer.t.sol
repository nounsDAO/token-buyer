// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import 'forge-std/Test.sol';
import { TokenBuyer } from '../src/TokenBuyer.sol';
import { Payer } from '../src/Payer.sol';
import { TestERC20 } from './helpers/TestERC20.sol';
import { TestPriceFeed } from './helpers/TestPriceFeed.sol';
import { MaliciousBuyer, TokenBuyerLike } from './helpers/MaliciousBuyer.sol';
import { IBuyETHCallback } from '../src/IBuyETHCallback.sol';
import { ETHBuyerBot } from './helpers/ETHBuyerBot.sol';

contract TokenBuyerTest is Test {
    bytes constant STUB_CALLDATA = 'stub calldata';
    bytes constant OWNABLE_ERROR_STRING = 'Ownable: caller is not the owner';
    bytes4 constant ERROR_SELECTOR = 0x08c379a0; // See: https://docs.soliditylang.org/en/v0.8.16/control-structures.html?highlight=0x08c379a0

    event SoldETH(address indexed to, uint256 ethOut, uint256 tokenIn);
    event BotDiscountBPsSet(uint16 oldBPs, uint16 newBPs);
    event BaselinePaymentTokenAmountSet(uint256 oldAmount, uint256 newAmount);
    event ETHWithdrawn(address indexed to, uint256 amount);
    event MinAdminBotDiscountBPsSet(uint16 oldBPs, uint16 newBPs);
    event MaxAdminBotDiscountBPsSet(uint16 oldBPs, uint16 newBPs);
    event MinAdminBaselinePaymentTokenAmountSet(uint256 oldAmount, uint256 newAmount);
    event MaxAdminBaselinePaymentTokenAmountSet(uint256 oldAmount, uint256 newAmount);
    event PriceFeedSet(address oldFeed, address newFeed);
    event PayerSet(address oldPayer, address newPayer);
    event AdminSet(address oldAdmin, address newAdmin);

    TokenBuyer buyer;
    Payer payer;
    TestERC20 paymentToken;
    TestPriceFeed priceFeed;
    uint256 baselinePaymentTokenAmount = 0;
    uint16 botDiscountBPs = 0;

    address owner = address(0x42);
    address admin = address(0x43);
    address bot = address(0x99);
    address user = address(0x1234);
    address botOperator = address(0x4444);
    ETHBuyerBot callbackBot;

    function setUp() public {
        vm.label(owner, 'owner');
        vm.label(admin, 'admin');
        vm.label(bot, 'bot');
        vm.label(user, 'user');
        paymentToken = new TestERC20('Payment Token', 'PAY');
        priceFeed = new TestPriceFeed();

        payer = new Payer(owner, paymentToken);

        buyer = new TokenBuyer(
            paymentToken,
            priceFeed,
            baselinePaymentTokenAmount,
            0,
            10_000_000e18,
            botDiscountBPs,
            0,
            10_000,
            owner,
            admin,
            address(payer)
        );

        callbackBot = new ETHBuyerBot(address(payer), address(paymentToken), STUB_CALLDATA, botOperator);
    }

    function test_setPriceFeed_revertsForNonOwner() public {
        TestPriceFeed newFeed = new TestPriceFeed();

        vm.expectRevert(OWNABLE_ERROR_STRING);
        buyer.setPriceFeed(newFeed);
    }

    function test_setPriceFeed_worksForOwner() public {
        TestPriceFeed newFeed = new TestPriceFeed();
        assertTrue(address(newFeed) != address(buyer.priceFeed()));
        vm.expectEmit(true, true, true, true);
        emit PriceFeedSet(address(buyer.priceFeed()), address(newFeed));

        vm.prank(owner);
        buyer.setMaxAdminBotDiscountBPs(142);

        vm.prank(owner);
        buyer.setPriceFeed(newFeed);

        assertEq(address(buyer.priceFeed()), address(newFeed));
    }

    function test_tokenAmountNeeded_baselineAmountOnly() public {
        vm.prank(owner);
        buyer.setBaselinePaymentTokenAmount(100_000e18);

        assertEq(buyer.tokenAmountNeeded(), 100_000e18);
    }

    function test_tokenAmountNeeded_debtOnly() public {
        vm.prank(address(owner));
        payer.sendOrRegisterDebt(address(1), 42_000e18);

        assertEq(buyer.tokenAmountNeeded(), 42_000e18);
    }

    function test_tokenAmountNeeded_paymentTokenBalanceOnly() public {
        paymentToken.mint(address(payer), 42_000e18);

        assertEq(buyer.tokenAmountNeeded(), 0);
    }

    function test_tokenAmountNeeded_baselineAndPaymentTokenBalance() public {
        vm.prank(owner);
        buyer.setBaselinePaymentTokenAmount(100_000e18);
        paymentToken.mint(address(payer), 42_000e18);

        assertEq(buyer.tokenAmountNeeded(), 58_000e18);
    }

    function test_tokenAmountNeeded_baselineAndPaymentTokenBalanceAndDebt() public {
        vm.prank(owner);
        buyer.setBaselinePaymentTokenAmount(100_000e18);
        vm.prank(owner);
        payer.sendOrRegisterDebt(address(1), 11_000e18);

        paymentToken.mint(address(payer), 42_000e18);

        assertEq(buyer.tokenAmountNeeded(), 69_000e18);
    }

    function test_tokenAmountNeededAndETHPayout_baselineAmountOnly() public {
        vm.prank(owner);
        buyer.setBaselinePaymentTokenAmount(100_000e18);
        priceFeed.setPrice(2000e18);

        (uint256 tokenAmount, uint256 ethAmount) = buyer.tokenAmountNeededAndETHPayout();

        assertEq(tokenAmount, 100_000e18);
        assertEq(ethAmount, 50 ether);
    }

    function test_price_botDiscountZero() public {
        priceFeed.setPrice(1234e18);

        uint256 price = buyer.price();

        assertEq(price, 1234e18);
    }

    function test_price_botDiscount50BPs() public {
        vm.prank(owner);
        buyer.setBotDiscountBPs(50);

        priceFeed.setPrice(1700e18);

        uint256 price = buyer.price();

        // 1700 * (1-0.005)
        assertEq(price, 1691.5e18);
    }

    function test_price_botDiscountHalfPrice() public {
        vm.prank(owner);
        buyer.setBotDiscountBPs(5_000);

        priceFeed.setPrice(4242e18);

        uint256 price = buyer.price();

        assertEq(price, 2121e18);
    }

    function test_buyETH_revertsWhenPaused() public {
        vm.prank(admin);
        buyer.pause();

        vm.expectRevert('Pausable: paused');
        buyer.buyETH(1234);
    }

    function test_buyETH_botBuysExactBaselineAmount() public {
        // Say ETH is worth $2000, then the oracle price denominated in ETH would be
        // 1 / 2000 = 0.0005
        priceFeed.setPrice(2000e18);
        vm.deal(address(buyer), 1 ether);
        paymentToken.mint(bot, 2000e18);
        vm.prank(owner);
        buyer.setBaselinePaymentTokenAmount(2000e18);

        vm.expectEmit(true, true, true, true);
        emit SoldETH(bot, 1 ether, 2000e18);

        vm.startPrank(bot);
        paymentToken.approve(address(buyer), 2000e18);
        buyer.buyETH(2000e18);
        vm.stopPrank();

        assertEq(bot.balance, 1 ether);
    }

    function test_buyETH_paysBackDebt() public {
        // user has debt of 2000 tokens
        vm.prank(owner);
        payer.sendOrRegisterDebt(user, 2000e18);
        assertEq(payer.debtOf(user), 2000e18);

        // bot buys ETH for 2000 tokens
        priceFeed.setPrice(2000e18);
        vm.deal(address(buyer), 1 ether);
        paymentToken.mint(bot, 2000e18);
        vm.startPrank(bot);
        paymentToken.approve(address(buyer), 2000e18);
        buyer.buyETH(2000e18);
        vm.stopPrank();

        // user has been paid
        assertEq(paymentToken.balanceOf(user), 2000e18);
        assertEq(payer.debtOf(user), 0);
    }

    function test_buyETH_botCappedToBaselineAmount() public {
        priceFeed.setPrice(2000e18);
        vm.deal(address(buyer), 1 ether);
        paymentToken.mint(bot, 4000e18);
        vm.prank(owner);
        buyer.setBaselinePaymentTokenAmount(2000e18);

        vm.expectEmit(true, true, true, true);
        emit SoldETH(bot, 1 ether, 2000e18);

        vm.startPrank(bot);
        paymentToken.approve(address(buyer), 4000e18);
        buyer.buyETH(4000e18);
        vm.stopPrank();

        assertEq(bot.balance, 1 ether);
        assertEq(paymentToken.balanceOf(bot), 2000e18);
    }

    function test_buyETH_revertsWhenContractHasInsufficientETH() public {
        priceFeed.setPrice(2000e18);
        paymentToken.mint(bot, 2000e18);
        vm.prank(owner);
        buyer.setBaselinePaymentTokenAmount(2000e18);
        assertEq(address(buyer).balance, 0);

        vm.prank(bot);
        paymentToken.approve(address(buyer), 2000e18);

        vm.prank(bot);
        vm.expectRevert(abi.encodeWithSelector(TokenBuyer.FailedSendingETH.selector, new bytes(0)));
        buyer.buyETH(2000e18);
    }

    function test_buyETH_revertsWhenTokenApprovalInsufficient() public {
        priceFeed.setPrice(2000e18);
        vm.deal(address(buyer), 1 ether);
        paymentToken.mint(bot, 2000e18);
        vm.prank(owner);
        buyer.setBaselinePaymentTokenAmount(2000e18);

        vm.prank(bot);
        paymentToken.approve(address(buyer), 2000e18 - 1);

        vm.prank(bot);
        vm.expectRevert('ERC20: insufficient allowance');
        buyer.buyETH(2000e18);
    }

    function test_buyETH_maliciousBuyerCantReenter() public {
        MaliciousBuyer attacker = new MaliciousBuyer(address(buyer), paymentToken);
        priceFeed.setPrice(2000e18);
        vm.deal(address(buyer), 10 ether);
        paymentToken.mint(address(attacker), 4000e18);
        vm.prank(owner);
        buyer.setBaselinePaymentTokenAmount(4000e18);

        vm.prank(address(attacker));
        paymentToken.approve(address(buyer), 4000e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                TokenBuyer.FailedSendingETH.selector,
                abi.encodeWithSelector(ERROR_SELECTOR, 'ReentrancyGuard: reentrant call')
            )
        );
        attacker.attack(2000e18);
    }

    function test_buyETHWithCallback_revertsWhenPaused() public {
        vm.prank(admin);
        buyer.pause();

        vm.expectRevert('Pausable: paused');
        vm.prank(botOperator);
        buyer.buyETH(2000e18, address(callbackBot), STUB_CALLDATA);
    }

    function test_buyETHWithCallback_botBuysExactBaselineAmount() public {
        priceFeed.setPrice(2000e18);
        vm.deal(address(buyer), 1 ether);
        paymentToken.mint(address(callbackBot), 2000e18);
        vm.prank(owner);
        buyer.setBaselinePaymentTokenAmount(2000e18);
        uint256 balanceBefore = address(callbackBot).balance;

        vm.expectEmit(true, true, true, true);
        emit SoldETH(address(callbackBot), 1 ether, 2000e18);

        vm.prank(botOperator);
        buyer.buyETH(2000e18, address(callbackBot), STUB_CALLDATA);

        assertEq(address(callbackBot).balance - balanceBefore, 1 ether);
    }

    function test_buyETHWithCallback_paysBackDebt() public {
        priceFeed.setPrice(2000e18);
        vm.deal(address(buyer), 1 ether);
        paymentToken.mint(address(callbackBot), 2000e18);

        vm.prank(owner);
        payer.sendOrRegisterDebt(user, 2500e18);

        uint256 balanceBefore = address(callbackBot).balance;

        vm.prank(botOperator);
        buyer.buyETH(2000e18, address(callbackBot), STUB_CALLDATA);

        assertEq(address(callbackBot).balance - balanceBefore, 1 ether);
        assertEq(paymentToken.balanceOf(user), 2000e18);
        assertEq(paymentToken.balanceOf(address(payer)), 0);
        assertEq(payer.debtOf(user), 500e18);
    }

    function test_buyETHWithCallback_botCappedToBaselineAmount() public {
        priceFeed.setPrice(2000e18);
        vm.deal(address(buyer), 1 ether);
        paymentToken.mint(address(callbackBot), 4000e18);
        vm.prank(owner);
        buyer.setBaselinePaymentTokenAmount(2000e18);
        uint256 balanceBefore = address(callbackBot).balance;

        vm.expectEmit(true, true, true, true);
        emit SoldETH(address(callbackBot), 1 ether, 2000e18);

        vm.prank(botOperator);
        buyer.buyETH(4000e18, address(callbackBot), STUB_CALLDATA);

        assertEq(address(callbackBot).balance - balanceBefore, 1 ether);
        assertEq(paymentToken.balanceOf(address(callbackBot)), 2000e18);
    }

    function test_buyETHWithCallback_revertsWhenContractHasInsufficientETH() public {
        priceFeed.setPrice(2000e18);
        paymentToken.mint(address(callbackBot), 4000e18);
        vm.prank(owner);
        buyer.setBaselinePaymentTokenAmount(2000e18);
        // 2000 tokens at 0.0005 price = 1 ether
        // setting the balance to the highest point where it should fail
        vm.deal(address(buyer), 1 ether - 1 wei);
        assertEq(address(buyer).balance, 1 ether - 1 wei);

        // EvmError: OutOfFund doesn't result in revert data
        vm.expectRevert();
        vm.prank(botOperator);
        buyer.buyETH(2000e18, address(callbackBot), STUB_CALLDATA);
    }

    function test_buyETHWithCallback_revertsWhenTokenPaymentInsufficient() public {
        priceFeed.setPrice(2000e18);
        vm.deal(address(buyer), 1 ether);
        paymentToken.mint(address(callbackBot), 2000e18);
        vm.prank(owner);
        buyer.setBaselinePaymentTokenAmount(2000e18);
        callbackBot.setTokenAmountOverride(2000e18 - 1);
        callbackBot.setOverrideTokenAmount(true);

        vm.expectRevert(abi.encodeWithSelector(TokenBuyer.ReceivedInsufficientTokens.selector, 2000e18, 2000e18 - 1));
        vm.prank(botOperator);
        buyer.buyETH(2000e18, address(callbackBot), STUB_CALLDATA);
    }

    function test_buyETHWithCallback_maliciousBuyerCantReenter() public {
        MaliciousBuyer attacker = new MaliciousBuyer(address(buyer), paymentToken);
        priceFeed.setPrice(2000e18);
        vm.deal(address(buyer), 10 ether);
        paymentToken.mint(address(attacker), 2000e18);
        vm.prank(owner);
        buyer.setBaselinePaymentTokenAmount(2000e18);

        vm.expectRevert('ReentrancyGuard: reentrant call');
        attacker.reenterBuyWithCallback(2000e18);
    }

    function test_buyETHWithCallback_maliciousBuyerCantReenterOtherBuyETHFunction() public {
        MaliciousBuyer attacker = new MaliciousBuyer(address(buyer), paymentToken);
        priceFeed.setPrice(2000e18);
        vm.deal(address(buyer), 10 ether);
        paymentToken.mint(address(attacker), 2000e18);
        vm.prank(owner);
        buyer.setBaselinePaymentTokenAmount(2000e18);

        vm.expectRevert('ReentrancyGuard: reentrant call');
        attacker.reenterBuyNoCallback(2000e18);
    }

    function test_happyFlow_payingFullyInPaymentToken() public {
        priceFeed.setPrice(100e18);
        vm.prank(owner);
        // 1% discount
        buyer.setBotDiscountBPs(100);

        assertEq(buyer.price(), 99e18);

        // set buffer
        vm.prank(owner);
        buyer.setBaselinePaymentTokenAmount(99_990e18);

        // fund bot and buyer
        paymentToken.mint(bot, 99_990e18);
        vm.deal(address(buyer), 1010 ether);

        // bots buy buffer
        vm.expectEmit(true, true, true, true);
        emit SoldETH(bot, 1010 ether, 99_990e18);
        vm.startPrank(bot);
        paymentToken.approve(address(buyer), 99_990e18);
        buyer.buyETH(99_990e18);
        vm.stopPrank();
        assertEq(paymentToken.balanceOf(bot), 0);
        assertEq(bot.balance, 1010 ether);

        // send or mint (42K)
        vm.prank(owner);
        payer.sendOrRegisterDebt(user, 42_000e18);

        // user gets sent that amount right away
        assertEq(payer.debtOf(user), 0);
        assertEq(paymentToken.balanceOf(user), 42_000e18);

        // fund bot and buyer again
        paymentToken.mint(bot, 42_000e18);

        // 42000 / 99 = 424.242424242
        vm.deal(address(buyer), 424242424242424242424);

        // bots can top off what's missing (bots buy 42K)
        vm.expectEmit(true, true, true, true);
        emit SoldETH(bot, 424242424242424242424, 42_000e18);
        vm.startPrank(bot);
        paymentToken.approve(address(buyer), 42_000e18);
        buyer.buyETH(42_000e18);
        vm.stopPrank();
        assertEq(paymentToken.balanceOf(bot), 0);
        assertEq(bot.balance, 1010 ether + 424242424242424242424);
    }

    function test_happyFlow_payingOverTheBuffer() public {
        priceFeed.setPrice(100e18);
        vm.prank(owner);
        // 1% discount
        buyer.setBotDiscountBPs(100);

        assertEq(buyer.price(), 99e18);

        // set buffer
        vm.prank(owner);
        buyer.setBaselinePaymentTokenAmount(99_990e18);

        // fund bot and buyer
        paymentToken.mint(bot, 99_990e18);
        vm.deal(address(buyer), 1010 ether);

        // bots buy buffer
        vm.expectEmit(true, true, true, true);
        emit SoldETH(bot, 1010 ether, 99_990e18);
        vm.startPrank(bot);
        paymentToken.approve(address(buyer), 99_990e18);
        buyer.buyETH(99_990e18);
        vm.stopPrank();
        assertEq(paymentToken.balanceOf(bot), 0);
        assertEq(bot.balance, 1010 ether);

        // send or mint (141,990)
        vm.prank(owner);
        payer.sendOrRegisterDebt(user, 141_990e18);
        assertEq(payer.debtOf(user), 42_000e18);
        assertEq(paymentToken.balanceOf(user), 99_990e18);

        // fund bot and buyer again
        paymentToken.mint(bot, 42_000e18);

        // 42000 / 99 = 424.242424242
        vm.deal(address(buyer), 424242424242424242424);

        // bots can top off what's missing (bots buy 42K)
        vm.expectEmit(true, true, true, true);
        emit SoldETH(bot, 424242424242424242424, 42_000e18);
        vm.startPrank(bot);
        paymentToken.approve(address(buyer), 42_000e18);
        buyer.buyETH(42_000e18);
        vm.stopPrank();
        assertEq(paymentToken.balanceOf(bot), 0);
        assertEq(bot.balance, 1010 ether + 424242424242424242424);

        // user's debt was paid
        assertEq(payer.debtOf(user), 0);
        assertEq(paymentToken.balanceOf(user), 141_990e18);

        // bots can top off what's missing (bots buy ~100K)
        // fund bot and buyer again
        paymentToken.mint(bot, 99_990e18);
        vm.deal(address(buyer), 1010 ether);
        vm.expectEmit(true, true, true, true);
        emit SoldETH(bot, 1010 ether, 99_990e18);
        vm.startPrank(bot);
        paymentToken.approve(address(buyer), 99_990e18);
        buyer.buyETH(99_990e18);
        vm.stopPrank();
        assertEq(paymentToken.balanceOf(bot), 0);
        assertEq(bot.balance, 1010 ether + 424242424242424242424 + 1010 ether);
        assertEq(paymentToken.balanceOf(address(payer)), 99_990e18);
    }

    function test_setBaselinePaymentTokenAmount_adminCall_revertsGivenInputLessThanMin() public {
        vm.prank(owner);
        buyer.setMinAdminBaselinePaymentTokenAmount(10_000);

        vm.expectRevert(abi.encodeWithSelector(TokenBuyer.InvalidBaselinePaymentTokenAmount.selector));
        vm.prank(admin);
        buyer.setBaselinePaymentTokenAmount(9999);
    }

    function test_setBaselinePaymentTokenAmount_adminCall_revertsGivenInputGreaterThanMax() public {
        vm.prank(owner);
        buyer.setMaxAdminBaselinePaymentTokenAmount(10_000);

        vm.expectRevert(abi.encodeWithSelector(TokenBuyer.InvalidBaselinePaymentTokenAmount.selector));
        vm.prank(admin);
        buyer.setBaselinePaymentTokenAmount(10_001);
    }

    function test_setBaselinePaymentTokenAmount_adminCall_worksGivenValidInput() public {
        vm.startPrank(owner);
        buyer.setMinAdminBaselinePaymentTokenAmount(10_000);
        buyer.setMaxAdminBaselinePaymentTokenAmount(100_000);
        vm.stopPrank();
        vm.expectEmit(true, true, true, true);
        emit BaselinePaymentTokenAmountSet(0, 50_000);

        vm.prank(admin);
        buyer.setBaselinePaymentTokenAmount(50_000);

        assertEq(50_000, buyer.baselinePaymentTokenAmount());
    }

    function test_setBaselinePaymentTokenAmount_ownerCall_allowsSetGivenInputLessThanMin() public {
        vm.prank(owner);
        buyer.setMinAdminBaselinePaymentTokenAmount(10_000);
        vm.expectEmit(true, true, true, true);
        emit BaselinePaymentTokenAmountSet(0, 9999);

        vm.prank(owner);
        buyer.setBaselinePaymentTokenAmount(9999);

        assertEq(9999, buyer.baselinePaymentTokenAmount());
    }

    function test_setBaselinePaymentTokenAmount_ownerCall_allowsSetGivenInputGreaterThanMax() public {
        vm.prank(owner);
        buyer.setMaxAdminBaselinePaymentTokenAmount(10_000);
        vm.expectEmit(true, true, true, true);
        emit BaselinePaymentTokenAmountSet(0, 10_001);

        vm.prank(owner);
        buyer.setBaselinePaymentTokenAmount(10_001);

        assertEq(10_001, buyer.baselinePaymentTokenAmount());
    }

    function test_setBotDiscountBPs_adminCall_revertsGivenInputLessThanMin() public {
        vm.prank(owner);
        buyer.setMinAdminBotDiscountBPs(50);

        vm.expectRevert(abi.encodeWithSelector(TokenBuyer.InvalidBotDiscountBPs.selector));
        vm.prank(admin);
        buyer.setBotDiscountBPs(49);
    }

    function test_setBotDiscountBPs_adminCall_revertsGivenInputGreaterThanMax() public {
        vm.prank(owner);
        buyer.setMaxAdminBotDiscountBPs(100);

        vm.expectRevert(abi.encodeWithSelector(TokenBuyer.InvalidBotDiscountBPs.selector));
        vm.prank(admin);
        buyer.setBotDiscountBPs(101);
    }

    function test_setBotDiscountBPs_adminCall_worksGivenValidInput() public {
        vm.prank(owner);
        buyer.setBotDiscountBPs(74);

        vm.startPrank(owner);
        buyer.setMinAdminBotDiscountBPs(50);
        buyer.setMaxAdminBotDiscountBPs(100);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit BotDiscountBPsSet(74, 75);

        vm.prank(admin);
        buyer.setBotDiscountBPs(75);

        assertEq(75, buyer.botDiscountBPs());
    }

    function test_setBotDiscountBPs_ownerCall_allowsSetGivenInputLessThanMin() public {
        vm.prank(owner);
        buyer.setMinAdminBotDiscountBPs(50);
        vm.expectEmit(true, true, true, true);
        emit BotDiscountBPsSet(0, 49);

        vm.prank(owner);
        buyer.setBotDiscountBPs(49);

        assertEq(49, buyer.botDiscountBPs());
    }

    function test_setBotDiscountBPs_ownerCall_allowsSetGivenInputGreaterThanMax() public {
        vm.prank(owner);
        buyer.setMaxAdminBotDiscountBPs(100);
        vm.expectEmit(true, true, true, true);
        emit BotDiscountBPsSet(0, 101);

        vm.prank(owner);
        buyer.setBotDiscountBPs(101);

        assertEq(101, buyer.botDiscountBPs());
    }

    function test_setAdmin_worksForOwner() public {
        address newAdmin = address(112233);
        assertFalse(newAdmin == buyer.admin());
        vm.expectEmit(true, true, true, true);
        emit AdminSet(buyer.admin(), newAdmin);

        vm.prank(owner);
        buyer.setAdmin(newAdmin);

        assertEq(newAdmin, buyer.admin());
    }

    function test_setAdmin_worksForAdmin() public {
        address newAdmin = address(112233);
        assertFalse(newAdmin == buyer.admin());
        vm.expectEmit(true, true, true, true);
        emit AdminSet(buyer.admin(), newAdmin);

        vm.prank(admin);
        buyer.setAdmin(newAdmin);

        assertEq(newAdmin, buyer.admin());
    }

    function test_setAdmin_revertsForNonOwner() public {
        vm.expectRevert(abi.encodeWithSelector(TokenBuyer.OnlyAdminOrOwner.selector));
        buyer.setAdmin(address(112233));
    }

    function test_pause_unpause_ownerCall_works() public {
        vm.prank(owner);
        buyer.pause();

        assertTrue(buyer.paused());

        vm.prank(owner);
        buyer.unpause();

        assertFalse(buyer.paused());
    }

    function test_pause_unpause_adminCall_works() public {
        vm.prank(admin);
        buyer.pause();

        assertTrue(buyer.paused());

        vm.prank(admin);
        buyer.unpause();

        assertFalse(buyer.paused());
    }

    function test_pause_unpause_revertForNonOwnerOrAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(TokenBuyer.OnlyAdminOrOwner.selector));
        buyer.pause();

        vm.expectRevert(abi.encodeWithSelector(TokenBuyer.OnlyAdminOrOwner.selector));
        buyer.unpause();
    }

    function test_setPayer_worksForOwner() public {
        address newPayer = address(112233);
        assertFalse(newPayer == address(buyer.payer()));
        vm.expectEmit(true, true, true, true);
        emit PayerSet(address(buyer.payer()), newPayer);

        vm.prank(owner);
        buyer.setPayer(newPayer);

        assertEq(newPayer, address(buyer.payer()));
    }

    function test_setPayer_revertsForNonOwner() public {
        vm.expectRevert(OWNABLE_ERROR_STRING);
        buyer.setPayer(address(112233));
    }

    function test_withdrawETH_worksForOwner() public {
        vm.deal(address(buyer), 1111 ether);
        vm.expectEmit(true, true, true, true);
        emit ETHWithdrawn(owner, 1111 ether);

        vm.prank(owner);
        buyer.withdrawETH();

        assertEq(1111 ether, owner.balance);
    }

    function test_withdrawETH_worksForAdmin() public {
        vm.deal(address(buyer), 1111 ether);
        vm.expectEmit(true, true, true, true);
        emit ETHWithdrawn(owner, 1111 ether);

        vm.prank(admin);
        buyer.withdrawETH();

        assertEq(1111 ether, owner.balance);
    }

    function test_withdrawETH_revertsForNonOwner() public {
        vm.deal(address(buyer), 1111 ether);

        vm.expectRevert(abi.encodeWithSelector(TokenBuyer.OnlyAdminOrOwner.selector));
        buyer.withdrawETH();
    }

    function test_setMinAdminBotDiscountBPs_worksForOwner() public {
        vm.expectEmit(true, true, true, true);
        emit MinAdminBotDiscountBPsSet(0, 42);

        vm.prank(owner);
        buyer.setMinAdminBotDiscountBPs(42);
    }

    function test_setMinAdminBotDiscountBPs_revertsForNonOwner() public {
        vm.expectRevert(OWNABLE_ERROR_STRING);
        buyer.setMinAdminBotDiscountBPs(42);
    }

    function test_setMaxAdminBotDiscountBPs_worksForOwner() public {
        vm.expectEmit(true, true, true, true);
        emit MaxAdminBotDiscountBPsSet(10_000, 142);

        vm.prank(owner);
        buyer.setMaxAdminBotDiscountBPs(142);
    }

    function test_setMaxAdminBotDiscountBPs_revertsForNonOwner() public {
        vm.expectRevert(OWNABLE_ERROR_STRING);
        buyer.setMaxAdminBotDiscountBPs(142);
    }

    function test_setMinAdminBaselinePaymentTokenAmount_worksForOwner() public {
        vm.expectEmit(true, true, true, true);
        emit MinAdminBaselinePaymentTokenAmountSet(0, 42);

        vm.prank(owner);
        buyer.setMinAdminBaselinePaymentTokenAmount(42);
    }

    function test_setMinAdminBaselinePaymentTokenAmount_revertsForNonOwner() public {
        vm.expectRevert(OWNABLE_ERROR_STRING);
        buyer.setMinAdminBaselinePaymentTokenAmount(42);
    }

    function test_setMaxAdminBaselinePaymentTokenAmount_worksForOwner() public {
        vm.expectEmit(true, true, true, true);
        emit MaxAdminBaselinePaymentTokenAmountSet(10_000_000e18, 142);

        vm.prank(owner);
        buyer.setMaxAdminBaselinePaymentTokenAmount(142);
    }

    function test_setMaxAdminBaselinePaymentTokenAmount_revertsForNonOwner() public {
        vm.expectRevert(OWNABLE_ERROR_STRING);
        buyer.setMaxAdminBaselinePaymentTokenAmount(42);
    }

    // Added this due to a compiler warning
    receive() external payable {}
}
