// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import 'forge-std/Script.sol';
import { IERC20Metadata } from 'openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import { Payer } from '../src/Payer.sol';
import { TokenBuyer } from '../src/TokenBuyer.sol';
import { IOUToken } from '../src/IOUToken.sol';
import { PriceFeed } from '../src/PriceFeed.sol';
import { AggregatorV3Interface } from '../src/AggregatorV3Interface.sol';
import { TestERC20 } from '../test/helpers/TestERC20.sol';

contract DeployScript is Script {
    // Nouns
    address constant MAINNET_NOUNS_EXECUTOR = 0x0BC3807Ec262cB779b38D65b38158acC3bfedE10;
    address constant TECHPOD_MULTISIG = 0x79095391743e0f017A16c388De6a6a3f175a5cD5;

    // USDC
    address constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    uint8 constant MAINNET_DECIMALS = 6;

    // PriceFeed config
    address constant MAINNET_USDC_ETH_CHAINLINK = 0x986b5E1e1755e3C2440e960477f25201B0a8bbD4;
    uint256 constant USDC_ETH_CHAINLINK_HEARTBEAT = 24 hours;
    uint256 constant PRICE_UPPER_BOUND = 0.01e18; // i.e. 100 tokens buy 1 ETH
    uint256 constant PRICE_LOWER_BOUND = 0.00001e18; // i.e. 100K tokens buy 1 ETH

    address constant RINKEBY_USDC_ETH_CHAINLINK = 0xdCA36F27cbC4E38aE16C4E9f99D39b42337F6dcf;

    // Buyer config
    uint256 constant USD_POSITION_IN_USD = 1_000_000;

    function run() public {
        // uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        // vm.startBroadcast(deployerPrivateKey);

        vm.startBroadcast();

        address owner = MAINNET_NOUNS_EXECUTOR;
        address admin = TECHPOD_MULTISIG;
        IERC20Metadata usdc = IERC20Metadata(MAINNET_USDC);
        uint8 decimals = MAINNET_DECIMALS;

        if (block.chainid != 1) {
            usdc = new TestERC20('USD Coin', 'USDC');
            owner = msg.sender;
            admin = owner;
            decimals = 18;
        }

        IOUToken iou = new IOUToken('Nouns USDC IOU', 'NOUUSDC', decimals, owner);

        Payer payer = new Payer(owner, usdc, iou);

        PriceFeed priceFeed = new PriceFeed(
            AggregatorV3Interface(block.chainid == 1 ? MAINNET_USDC_ETH_CHAINLINK : RINKEBY_USDC_ETH_CHAINLINK),
            USDC_ETH_CHAINLINK_HEARTBEAT,
            PRICE_LOWER_BOUND,
            PRICE_UPPER_BOUND
        );

        new TokenBuyer(
            usdc,
            iou,
            priceFeed,
            USD_POSITION_IN_USD * 10**decimals, // baselinePaymentTokenAmount
            0, // minAdminBaselinePaymentTokenAmount
            2 * USD_POSITION_IN_USD * 10**decimals, // maxAdminBaselinePaymentTokenAmount
            0, // botIncentiveBPs
            0, // minAdminBotIncentiveBPs
            150, // maxAdminBotIncentiveBPs
            owner,
            admin,
            address(payer)
        );

        vm.stopBroadcast();
    }
}
