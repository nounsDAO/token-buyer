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
    event Redeemed(address indexed account, uint256 amount);

    Payer payer;
    TestERC20 paymentToken;
    IOUToken iou;
    address owner = address(42);
    address user = address(1234);

    function setUp() public {
        paymentToken = new TestERC20('Payment Token', 'PAY');
        iou = new IOUToken('IOU Token', 'IOU', 18, owner);
        payer = new Payer(owner, paymentToken, iou);

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
        payer = new Payer(owner, pToken, iouToken);
    }

    function test_sendOrMint_revertsWhenCalledByNonOwner() public {
        vm.expectRevert('Ownable: caller is not the owner');
        payer.sendOrMint(user, 42);
    }

    function test_sendOrMint_givenNoPaymentTokenBalancePayInIOUs() public {
        uint256 amount = 100_000e18;
        vm.prank(owner);
        payer.sendOrMint(user, amount);

        assertEq(iou.balanceOf(user), amount);
        assertEq(paymentToken.balanceOf(user), 0);
    }

    function test_sendOrMint_givenEnoughPaymentTokenPaysInToken() public {
        uint256 amount = 100_000e18;
        paymentToken.mint(address(payer), amount);
        vm.prank(owner);
        payer.sendOrMint(user, amount);

        assertEq(iou.balanceOf(user), 0);
        assertEq(paymentToken.balanceOf(user), amount);
    }

    function test_sendOrMint_givenPartialPaymentTokenBalancePaysInBoth() public {
        uint256 amount = 100_000e18;
        paymentToken.mint(address(payer), 42_000e18);
        vm.prank(owner);
        payer.sendOrMint(user, amount);

        assertEq(iou.balanceOf(user), 58_000e18);
        assertEq(paymentToken.balanceOf(user), 42_000e18);
    }

    function test_sendOrMint_zeroDoesntRevert() public {
        vm.prank(owner);
        payer.sendOrMint(user, 0);

        assertEq(iou.balanceOf(user), 0);
        assertEq(paymentToken.balanceOf(user), 0);
    }

    function test_redeem_givenEnoughPaymentTokenSendsFullAmount() public {
        uint256 amount = 100_000e18;
        vm.prank(address(payer));
        iou.mint(user, amount);
        paymentToken.mint(address(payer), amount);
        vm.expectEmit(true, true, true, true);
        emit Redeemed(user, amount);

        payer.redeem(user);

        assertEq(iou.balanceOf(user), 0);
        assertEq(paymentToken.balanceOf(user), amount);
        assertEq(paymentToken.balanceOf(address(payer)), 0);
    }

    function test_redeem_givenPartialPaymentTokenSendsPartialAmount() public {
        uint256 amount = 100_000e18;
        vm.prank(address(payer));
        iou.mint(user, amount);
        paymentToken.mint(address(payer), amount - 1);
        vm.expectEmit(true, true, true, true);
        emit Redeemed(user, amount - 1);

        payer.redeem(user);

        assertEq(iou.balanceOf(user), 1);
        assertEq(paymentToken.balanceOf(user), amount - 1);
        assertEq(paymentToken.balanceOf(address(payer)), 0);
    }

    function test_redeem_givenNoPaymentTokenSendsNothing() public {
        uint256 amount = 100_000e18;
        vm.prank(address(payer));
        iou.mint(user, amount);

        payer.redeem(user);

        assertEq(iou.balanceOf(user), amount);
        assertEq(paymentToken.balanceOf(user), 0);
    }

    function test_redeem_givenNoIOUBalanceSendsNothing() public {
        paymentToken.mint(address(payer), 100_000e18);

        payer.redeem(user);

        assertEq(iou.balanceOf(user), 0);
        assertEq(paymentToken.balanceOf(user), 0);
        assertEq(paymentToken.balanceOf(address(payer)), 100_000e18);
    }

    function test_redeem_withExplicitAmount_givenSufficientBalancesTransfersRequestedAmount() public {
        uint256 amount = 100_000e18;
        vm.prank(address(payer));
        iou.mint(user, amount);
        paymentToken.mint(address(payer), amount);
        vm.expectEmit(true, true, true, true);
        emit Redeemed(user, amount);

        payer.redeem(user, amount);
        assertEq(iou.balanceOf(user), 0);
        assertEq(paymentToken.balanceOf(user), amount);
        assertEq(paymentToken.balanceOf(address(payer)), 0);
    }

    function test_redeem_withExplicitAmount_revertsGivenNoIOUBalance() public {
        paymentToken.mint(address(payer), 100_000e18);

        vm.expectRevert('ERC20: burn amount exceeds balance');
        payer.redeem(user, 100_000e18);
    }

    function test_redeem_withExplicitAmount_revertsGivenAmountHigherThanIOUs() public {
        paymentToken.mint(address(payer), 100_000e18);
        vm.prank(address(payer));
        iou.mint(user, 42_000e18);

        vm.expectRevert('ERC20: burn amount exceeds balance');
        payer.redeem(user, 69_000e18);
    }

    function test_redeem_withExplicitAmount_revertsGivenAmountHigherThanPaymentTokenBalance() public {
        paymentToken.mint(address(payer), 42_000e18);
        vm.prank(address(payer));
        iou.mint(user, 69_000e18);

        vm.expectRevert('ERC20: transfer amount exceeds balance');
        payer.redeem(user, 69_000e18);
    }
}
