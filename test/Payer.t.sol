// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import 'forge-std/Test.sol';
import { TokenBuyer } from '../src/TokenBuyer.sol';
import { Payer } from '../src/Payer.sol';
import { TestERC20 } from './helpers/TestERC20.sol';
import { TestPriceFeed } from './helpers/TestPriceFeed.sol';
import { MaliciousBuyer, TokenBuyerLike } from './helpers/MaliciousBuyer.sol';

contract PayerTest is Test {
    event PaidBackDebt(address indexed account, uint256 amount, uint256 remainingDebt);
    event RegisteredDebt(address indexed account, uint256 amount);
    event TokensWithdrawn(address indexed account, uint256 amount);

    Payer payer;
    TestERC20 paymentToken;
    address owner = address(0x42);
    address user = address(0x1234);
    address user2 = address(0x1235);
    address user3 = address(0x1236);

    function setUp() public {
        paymentToken = new TestERC20('Payment Token', 'PAY');
        payer = new Payer(owner, address(paymentToken));
        vm.label(user, 'user');
    }

    function test_sendOrRegisterDebt_revertsWhenCalledByNonOwner() public {
        vm.expectRevert('Ownable: caller is not the owner');
        payer.sendOrRegisterDebt(user, 42);
    }

    function test_sendOrRegisterDebt_givenNoPaymentTokenBalanceRegistersDebt() public {
        uint256 amount = 100_000e18;

        vm.expectEmit(true, true, true, true);
        emit RegisteredDebt(user, amount);
        vm.prank(owner);
        payer.sendOrRegisterDebt(user, amount);

        assertEq(payer.debtOf(user), amount);
    }

    function test_sendOrRegisterDebt_givenEnoughPaymentTokenPaysInToken() public {
        uint256 amount = 100_000e18;
        paymentToken.mint(address(payer), amount);
        vm.prank(owner);
        payer.sendOrRegisterDebt(user, amount);

        assertEq(payer.debtOf(user), 0);
        assertEq(paymentToken.balanceOf(user), amount);
    }

    function test_sendOrRegisterDebt_givenPartialPaymentTokenBalancePaysInBoth() public {
        uint256 amount = 100_000e18;
        paymentToken.mint(address(payer), 42_000e18);

        vm.expectEmit(true, true, true, true);
        emit RegisteredDebt(user, 58_000e18);
        vm.prank(owner);
        payer.sendOrRegisterDebt(user, amount);

        assertEq(payer.debtOf(user), 58_000e18);
        assertEq(paymentToken.balanceOf(user), 42_000e18);
    }

    function test_withdrawPaymentToken_revertsIfNotOwner() public {
        paymentToken.mint(address(payer), 1_000);

        vm.expectRevert('Ownable: caller is not the owner');
        payer.withdrawPaymentToken();
    }

    function test_withdrawPaymentToken_sendsTokensToOwner() public {
        paymentToken.mint(address(payer), 1_000);

        vm.expectEmit(true, true, true, true);
        emit TokensWithdrawn(owner, 1_000);
        vm.prank(owner);
        payer.withdrawPaymentToken();

        assertEq(paymentToken.balanceOf(owner), 1_000);
        assertEq(paymentToken.balanceOf(address(payer)), 0);
    }

    function test_debtOf_returnsDebtOfUser() public {
        vm.prank(owner);
        payer.sendOrRegisterDebt(user, 1000);
        vm.prank(owner);
        payer.sendOrRegisterDebt(user2, 2000);

        assertEq(payer.debtOf(user), 1000);
        assertEq(payer.debtOf(user2), 2000);
        assertEq(payer.debtOf(address(0x1111)), 0);
    }

    function test_debtOf_sumsEntriesForSameUser() public {
        vm.prank(owner);
        payer.sendOrRegisterDebt(user, 1000);
        vm.prank(owner);
        payer.sendOrRegisterDebt(user, 2000);

        assertEq(payer.debtOf(user), 3000);
    }

    function test_totalDebt() public {
        vm.startPrank(owner);
        payer.sendOrRegisterDebt(user, 1000);
        payer.sendOrRegisterDebt(user2, 2000);
        payer.sendOrRegisterDebt(user3, 3000);

        assertEq(payer.totalDebt(), 6000);
    }

    function test_payBackDebt_givenEnoughPaymentTokenSendsFullAmount() public {
        uint256 amount = 100_000e18;
        vm.prank(owner);
        payer.sendOrRegisterDebt(user, amount);
        assertEq(payer.totalDebt(), amount);

        paymentToken.mint(address(payer), amount);

        vm.expectEmit(true, true, true, true);
        emit PaidBackDebt(user, amount, 0);
        payer.payBackDebt(amount);

        assertEq(payer.debtOf(user), 0);
        assertEq(paymentToken.balanceOf(user), amount);
        assertEq(paymentToken.balanceOf(address(payer)), 0);
        assertEq(payer.totalDebt(), 0);
    }

    function test_payBackDebt_givenPartialPaymentTokenSendsPartialAmount() public {
        uint256 amount = 100_000e18;
        vm.prank(owner);
        payer.sendOrRegisterDebt(user, amount);
        assertEq(payer.totalDebt(), amount);

        paymentToken.mint(address(payer), amount - 1);

        vm.expectEmit(true, true, true, true);
        emit PaidBackDebt(user, amount - 1, 1);
        payer.payBackDebt(amount - 1);

        assertEq(payer.debtOf(user), 1);
        assertEq(paymentToken.balanceOf(user), amount - 1);
        assertEq(paymentToken.balanceOf(address(payer)), 0);
        assertEq(payer.totalDebt(), 1);
    }

    function test_payBackDebt_revertsIfNoPaymentToken() public {
        uint256 amount = 100_000e18;
        vm.prank(owner);
        payer.sendOrRegisterDebt(user, amount);

        vm.expectRevert('ERC20: transfer amount exceeds balance');
        payer.payBackDebt(1);
    }

    function test_payBackDebt_sendsNothingGivenNoDebt() public {
        paymentToken.mint(address(payer), 100_000e18);

        payer.payBackDebt(100_000e18);

        assertEq(paymentToken.balanceOf(address(payer)), 100_000e18);
    }

    function test_payBackDebt_paysBackInFIFOOrder() public {
        vm.startPrank(owner);
        payer.sendOrRegisterDebt(user, 1000);
        payer.sendOrRegisterDebt(user2, 2000);
        payer.sendOrRegisterDebt(user3, 3000);
        vm.stopPrank();

        assertEq(payer.totalDebt(), 6000);

        paymentToken.mint(address(payer), 1500);

        payer.payBackDebt(1500);

        assertEq(paymentToken.balanceOf(user), 1000);
        assertEq(paymentToken.balanceOf(user2), 500);
        assertEq(payer.debtOf(user), 0);
        assertEq(payer.debtOf(user2), 1500);
        assertEq(payer.debtOf(user3), 3000);

        assertEq(payer.totalDebt(), 4500);
    }

    function test_payBackDebt_amountCanBeHigherThanTotalDebt() public {
        uint256 amount = 100_000e18;
        vm.prank(owner);
        payer.sendOrRegisterDebt(user, amount);

        paymentToken.mint(address(payer), 200_000e18);
        payer.payBackDebt(200_000e18);

        assertEq(payer.debtOf(user), 0);
        assertEq(paymentToken.balanceOf(address(payer)), 100_000e18);
    }
}
