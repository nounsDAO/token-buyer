// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import 'forge-std/Test.sol';
import { TokenBuyer } from '../src/TokenBuyer.sol';
import { Payer } from '../src/Payer.sol';
import { TestERC20 } from './helpers/TestERC20.sol';
import { IOUToken } from '../src/IOUToken.sol';
import { TestPriceFeed } from './helpers/TestPriceFeed.sol';
import { MaliciousBuyer, TokenBuyerLike } from './helpers/MaliciousBuyer.sol';

contract PayerTest is Test {
    Payer payer;
    TestERC20 paymentToken;
    IOUToken iou;
    address owner = address(42);
    address buyer = address(1337);
    address user = address(1234);

    function setUp() public {
        paymentToken = new TestERC20('Payment Token', 'PAY');
        iou = new IOUToken('IOU Token', 'IOU', 18, owner);
        payer = new Payer(owner, paymentToken, iou, buyer);

        vm.startPrank(owner);
        iou.grantRole(iou.MINTER_ROLE(), address(payer));
        iou.grantRole(iou.BURNER_ROLE(), address(payer));
        vm.stopPrank();
    }

    function test_constructor_revertsWhenIOUAndPaymenTokenHaveDifferentDecimals() public {
        uint8 differentDecimals = 42;
        TestERC20 pToken = new TestERC20('Payment Token', 'PAY');
        IOUToken iouToken = new IOUToken('IOU Token', 'IOU', differentDecimals, owner);

        vm.expectRevert(abi.encodeWithSelector(Payer.DecimalsMismatch.selector, 18, 42));
        payer = new Payer(owner, pToken, iouToken, address(0));
    }

    function test_sendOrMint_givenNoPaymentTokenBalancePayInIOUs() public {
        uint256 amount = toWAD(100_000);
        vm.prank(owner);
        payer.sendOrMint(user, amount);

        assertEq(iou.balanceOf(user), amount);
        assertEq(paymentToken.balanceOf(user), 0);
    }

    function test_sendOrMint_givenEnoughPaymentTokenPaysInToken() public {
        uint256 amount = toWAD(100_000);
        paymentToken.mint(address(payer), amount);
        vm.prank(owner);
        payer.sendOrMint(user, amount);

        assertEq(iou.balanceOf(user), 0);
        assertEq(paymentToken.balanceOf(user), amount);
    }

    function test_sendOrMint_givenPartialPaymentTokenBalancePaysInBoth() public {
        uint256 amount = toWAD(100_000);
        paymentToken.mint(address(payer), toWAD(42_000));
        vm.prank(owner);
        payer.sendOrMint(user, amount);

        assertEq(iou.balanceOf(user), toWAD(58_000));
        assertEq(paymentToken.balanceOf(user), toWAD(42_000));
    }

    function test_sendOrMint_zeroDoesntRevert() public {
        vm.prank(owner);
        payer.sendOrMint(user, 0);

        assertEq(iou.balanceOf(user), 0);
        assertEq(paymentToken.balanceOf(user), 0);
    }

    function test_redeem_givenEnoughPaymentTokenSendsFullAmount() public {
        uint256 amount = toWAD(100_000);
        vm.prank(address(payer));
        iou.mint(user, amount);
        paymentToken.mint(address(payer), amount);

        payer.redeem(user);

        assertEq(iou.balanceOf(user), 0);
        assertEq(paymentToken.balanceOf(user), amount);
        assertEq(paymentToken.balanceOf(address(payer)), 0);
    }

    function test_redeem_givenPartialPaymentTokenSendsPartialAmount() public {
        uint256 amount = toWAD(100_000);
        vm.prank(address(payer));
        iou.mint(user, amount);
        paymentToken.mint(address(payer), amount - 1);

        payer.redeem(user);

        assertEq(iou.balanceOf(user), 1);
        assertEq(paymentToken.balanceOf(user), amount - 1);
        assertEq(paymentToken.balanceOf(address(payer)), 0);
    }

    function test_redeem_givenNoPaymentTokenSendsNothing() public {
        uint256 amount = toWAD(100_000);
        vm.prank(address(payer));
        iou.mint(user, amount);

        payer.redeem(user);

        assertEq(iou.balanceOf(user), amount);
        assertEq(paymentToken.balanceOf(user), 0);
    }

    function test_redeem_givenNoIOUBalanceSendsNothing() public {
        paymentToken.mint(address(payer), toWAD(100_000));

        payer.redeem(user);

        assertEq(iou.balanceOf(user), 0);
        assertEq(paymentToken.balanceOf(user), 0);
        assertEq(paymentToken.balanceOf(address(payer)), toWAD(100_000));
    }

    function test_redeem_withExplicitAmount_givenNoIOUBalanceDoesNothing() public {
        paymentToken.mint(address(payer), toWAD(100_000));

        payer.redeem(user, toWAD(100_000));

        assertEq(iou.balanceOf(user), 0);
        assertEq(paymentToken.balanceOf(user), 0);
        assertEq(paymentToken.balanceOf(address(payer)), toWAD(100_000));
    }

    function test_redeem_withExplicitAmount_givenAmountHigherThanIOUsRedeemsIOUBalance() public {
        paymentToken.mint(address(payer), toWAD(100_000));
        vm.prank(address(payer));
        iou.mint(user, toWAD(42_000));

        payer.redeem(user, toWAD(69_000));

        assertEq(iou.balanceOf(user), 0);
        assertEq(paymentToken.balanceOf(user), toWAD(42_000));
        assertEq(paymentToken.balanceOf(address(payer)), toWAD(58_000));
    }

    function test_redeem_withExplicitAmount_givenAmountHigherThanIOUsAndPaymentTokenBalanceRedeemsAllTokenBalance()
        public
    {
        paymentToken.mint(address(payer), toWAD(42_000));
        vm.prank(address(payer));
        iou.mint(user, toWAD(69_000));

        payer.redeem(user, toWAD(100_000));

        assertEq(iou.balanceOf(user), toWAD(27_000));
        assertEq(paymentToken.balanceOf(user), toWAD(42_000));
        assertEq(paymentToken.balanceOf(address(payer)), 0);
    }

    function toWAD(uint256 amount) public pure returns (uint256) {
        return amount * 10**18;
    }
}
