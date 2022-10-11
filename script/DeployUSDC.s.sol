// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import 'forge-std/Script.sol';
import { Payer } from '../src/Payer.sol';
import { TokenBuyer } from '../src/TokenBuyer.sol';
import { PriceFeed } from '../src/PriceFeed.sol';
import { AggregatorV3Interface } from '../src/AggregatorV3Interface.sol';
import { TestERC20 } from '../test/helpers/TestERC20.sol';
import { MAINNET_USDC, MAINNET_USDC_DECIMALS, TECHPOD_MULTISIG, VERBS_OPERATOR } from './Constants.s.sol';

contract DeployUSDCScript is Script {
    // PriceFeed config
    uint256 constant ETH_USD_CHAINLINK_HEARTBEAT = 1 hours;
    uint256 constant PRICE_UPPER_BOUND = 100_000e18; // max $100K / ETH
    uint256 constant PRICE_LOWER_BOUND = 100e18; // min $100 / ETH
}

contract DeployUSDCMainnet is DeployUSDCScript {
    uint256 constant USD_POSITION_IN_USD = 1_000_000;
    address constant MAINNET_ETH_USD_CHAINLINK = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    // Nouns
    address constant MAINNET_NOUNS_EXECUTOR = 0x0BC3807Ec262cB779b38D65b38158acC3bfedE10;

    function run() public {
        vm.startBroadcast();

        uint8 decimals = MAINNET_USDC_DECIMALS;

        Payer payer = new Payer(TECHPOD_MULTISIG, MAINNET_USDC);

        PriceFeed priceFeed = new PriceFeed(
            AggregatorV3Interface(MAINNET_ETH_USD_CHAINLINK),
            ETH_USD_CHAINLINK_HEARTBEAT,
            PRICE_LOWER_BOUND,
            PRICE_UPPER_BOUND
        );

        new TokenBuyer(
            MAINNET_USDC,
            priceFeed,
            USD_POSITION_IN_USD * 10**decimals, // baselinePaymentTokenAmount
            0, // minAdminBaselinePaymentTokenAmount
            2 * USD_POSITION_IN_USD * 10**decimals, // maxAdminBaselinePaymentTokenAmount
            0, // botDiscountBPs
            0, // minAdminBotDiscountBPs
            150, // maxAdminBotDiscountBPs
            TECHPOD_MULTISIG, // owner
            VERBS_OPERATOR, // admin
            address(payer)
        );

        vm.stopBroadcast();
    }
}

contract DeployUSDCGoerli is DeployUSDCScript {
    address constant GOERLI_USDC_CONTRACT = 0x07865c6E87B9F70255377e024ace6630C1Eaa37F;
    address constant GOERLI_USD_ETH_CHAINLINK = 0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e;
    uint256 constant GOERLI_USD_ETH_CHAINLINK_HEARTBEAT = 1 hours;
    uint8 constant GOERLI_USDC_DECIMALS = 6;

    function run() public {
        vm.startBroadcast();

        Payer payer = new Payer(msg.sender, GOERLI_USDC_CONTRACT);

        PriceFeed priceFeed = new PriceFeed(
            AggregatorV3Interface(GOERLI_USD_ETH_CHAINLINK),
            ETH_USD_CHAINLINK_HEARTBEAT,
            PRICE_LOWER_BOUND,
            PRICE_UPPER_BOUND
        );

        new TokenBuyer(
            GOERLI_USDC_CONTRACT,
            priceFeed,
            10_000 * 10**GOERLI_USDC_DECIMALS, // baselinePaymentTokenAmount
            0, // minAdminBaselinePaymentTokenAmount
            20_000 * 10**GOERLI_USDC_DECIMALS, // maxAdminBaselinePaymentTokenAmount
            0, // botDiscountBPs
            0, // minAdminBotDiscountBPs
            150, // maxAdminBotDiscountBPs
            msg.sender, // owner
            msg.sender, // admin
            address(payer)
        );

        vm.stopBroadcast();
    }
}
