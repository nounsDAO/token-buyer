// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import 'forge-std/Test.sol';
import { TokenBuyer } from '../src/TokenBuyer.sol';
import { Payer } from '../src/Payer.sol';
import { PriceFeed } from '../src/PriceFeed.sol';
import { AggregatorV3Interface } from '../src/AggregatorV3Interface.sol';
import { IWETH } from './helpers/IWETH.sol';
import { IERC20Metadata } from 'openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import { SafeERC20 } from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import { SafeCast } from 'openzeppelin-contracts/contracts/utils/math/SafeCast.sol';
import { ISwapRouter } from './helpers/univ3/ISwapRouter.sol';
import { IUniswapV3PoolState } from './helpers/univ3/IUniswapV3PoolState.sol';
import { IUniswapV3PoolDerivedState } from './helpers/univ3/IUniswapV3PoolDerivedState.sol';
import { IUniswapV3FlashCallback } from './helpers/univ3/IUniswapV3FlashCallback.sol';
import { IUniswapV3PoolActions } from './helpers/univ3/IUniswapV3PoolActions.sol';
import { TickMath } from './helpers/univ3/TickMath.sol';

contract DAIFlashloanForkTest is Test, IUniswapV3FlashCallback {
    using SafeERC20 for IERC20Metadata;
    using SafeCast for uint256;
    using SafeCast for int256;

    string constant MAINNET_RPC_ENVVAR = 'MAINNET_RPC';
    uint256 constant MAINNET_BLOCK_NUMBER = 15367427;
    uint256 constant BLOCK_TIMESTAMP = 1660858991;
    address constant DAI_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address constant ETH_USD_CHAINLINK = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    // UNISWAP V3
    address constant SWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant UNIV3_DAI_ETH2 = 0x60594a405d53811d3BC4766596EFD80fd545A270;
    uint24 constant DAI_ETH2_POOL_FEE = 500;
    address constant UNIV3_DAI_USDC = 0x5777d92f208679DB4b9778590Fa3CAB3aC9e2168;
    uint24 constant DAI_USDC_POOL_FEE = 100;

    uint256 constant DAI_BUYER_WANTS = 100_000e18;

    address constant DAI_WHALE = 0x8EB8a3b98659Cce290402893d0123abb75E3ab28;

    // PriceFeed config
    uint256 constant PRICE_UPPER_BOUND = 100_000e18;
    uint256 constant PRICE_LOWER_BOUND = 100e18;

    IERC20Metadata dai;
    TokenBuyer buyer;
    Payer payer;
    PriceFeed priceFeed;
    uint256 baselinePaymentTokenAmount;
    uint16 botDiscountBPs;

    address owner = address(42);
    address admin = address(43);
    address bot = address(99);
    address user = address(1234);
    address anyone = address(9999);

    ISwapRouter swapRouter;

    function setUp() public {
        vm.createSelectFork(vm.envString(MAINNET_RPC_ENVVAR), MAINNET_BLOCK_NUMBER);
        vm.warp(BLOCK_TIMESTAMP);

        priceFeed = new PriceFeed(
            AggregatorV3Interface(ETH_USD_CHAINLINK),
            1 hours,
            PRICE_LOWER_BOUND,
            PRICE_UPPER_BOUND
        );
        swapRouter = ISwapRouter(SWAP_ROUTER);

        payer = new Payer(owner, DAI_ADDRESS);

        botDiscountBPs = 50;
        buyer = new TokenBuyer(
            priceFeed,
            baselinePaymentTokenAmount,
            0,
            10_000_000 * 10e18,
            botDiscountBPs,
            0,
            10_000,
            owner,
            admin,
            address(payer)
        );
    }

    function test_fullProposalFlow_partialDebtUsage() public {
        uint256 baselineDAI = DAI_BUYER_WANTS;
        uint256 proposalAmount = baselineDAI * 3;

        vm.deal(address(buyer), 1_000 ether);
        vm.prank(owner);
        buyer.setBaselinePaymentTokenAmount(baselineDAI);

        fundBotWithDAI(buyer.tokenAmountNeeded());
        sellDAIToTokenBuyer(bot, buyer.tokenAmountNeeded());

        vm.prank(owner);
        payer.sendOrRegisterDebt(user, proposalAmount);

        assertEq(dai.balanceOf(user), baselineDAI);
        assertEq(payer.debtOf(user), baselineDAI * 2);

        fundBotWithDAI(buyer.tokenAmountNeeded());
        sellDAIToTokenBuyer(bot, buyer.tokenAmountNeeded());

        assertEq(dai.balanceOf(user), proposalAmount);
        assertEq(payer.debtOf(user), 0);
    }

    function test_botUsingUniswapV3_makesGrossMargin() public {
        vm.deal(address(buyer), 1_000 ether);

        vm.prank(owner);
        buyer.setBaselinePaymentTokenAmount(DAI_BUYER_WANTS);

        IUniswapV3PoolActions(UNIV3_DAI_USDC).flash(
            user,
            DAI_BUYER_WANTS,
            0,
            abi.encode('callback verification data should go here')
        );
        // this test continues in `uniswapV3FlashCallback`
        // showing the flow a bot might execute to arbitrage using TokenBuyer and a flash loan
    }

    /// @notice Called to `msg.sender` after transferring to the recipient from IUniswapV3Pool#flash.
    function uniswapV3FlashCallback(
        uint256 fee0,
        uint256,
        bytes calldata
    ) external override {
        // in real life we would verify callback data

        assertEq(dai.balanceOf(user), DAI_BUYER_WANTS);

        sellDAIToTokenBuyer(user, DAI_BUYER_WANTS);
        uint256 grossDAI = swapETHForDAI(user, user.balance);

        uint256 flashloanPaybackAmount = DAI_BUYER_WANTS + fee0;
        vm.prank(user);
        dai.transfer(msg.sender, flashloanPaybackAmount);

        uint256 earningsBeforeGas = (grossDAI - flashloanPaybackAmount) / 1 ether;
        assertGt(earningsBeforeGas, 0);
    }

    function swapETHForDAI(address who, uint256 amountIn) internal returns (uint256 amountOut) {
        vm.startPrank(who);

        IERC20Metadata(WETH_ADDRESS).safeApprove(address(swapRouter), amountIn);
        IWETH(WETH_ADDRESS).deposit{ value: amountIn }();

        amountOut = swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: WETH_ADDRESS,
                tokenOut: DAI_ADDRESS,
                fee: DAI_ETH2_POOL_FEE,
                recipient: user,
                deadline: block.timestamp + 200,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        vm.stopPrank();
    }

    function getPriceX96FromSqrtPriceX96(uint160 sqrtPriceX96) public pure returns (uint256 priceX96) {
        return (uint256(sqrtPriceX96) * (uint256(sqrtPriceX96)) * (1e18)) >> (96 * 2);
    }

    function getSqrtTwapX96(address uniswapV3Pool, uint32 twapInterval) public view returns (uint160 sqrtPriceX96) {
        if (twapInterval == 0) {
            // return the current price if twapInterval == 0
            (sqrtPriceX96, , , , , , ) = IUniswapV3PoolState(uniswapV3Pool).slot0();
        } else {
            uint32[] memory secondsAgos = new uint32[](2);
            secondsAgos[0] = twapInterval; // from (before)
            secondsAgos[1] = 0; // to (now)

            (int56[] memory tickCumulatives, ) = IUniswapV3PoolDerivedState(uniswapV3Pool).observe(secondsAgos);

            int56 tickDiff = (tickCumulatives[1] - tickCumulatives[0]);
            sqrtPriceX96 = TickMath.getSqrtRatioAtTick(int24(tickDiff / uint256(twapInterval).toInt256().toInt56()));
        }
    }

    function fundBotWithDAI(uint256 amount) internal {
        vm.prank(DAI_WHALE);
        dai.transfer(bot, amount);
    }

    function sellDAIToTokenBuyer(address who, uint256 amount) internal {
        vm.startPrank(who);
        dai.approve(address(buyer), amount);
        buyer.buyETH(amount);
        vm.stopPrank();
    }
}
