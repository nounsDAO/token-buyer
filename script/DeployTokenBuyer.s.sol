// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import 'forge-std/Script.sol';
import { TokenBuyer } from '../src/TokenBuyer.sol';
import { PriceFeed } from '../src/PriceFeed.sol';
import { Payer } from '../src/Payer.sol';
import { DeployUSDCMainnet } from './DeployUSDC.s.sol';
import { MAINNET_USDC, MAINNET_USDC_DECIMALS, TECHPOD_MULTISIG, VERBS_OPERATOR } from './Constants.s.sol';

contract DeployTokenBuyer is Script {
    uint256 constant USD_POSITION_IN_USD = 1_000_000;
    address constant MAINNET_PAYER = 0x94A63a8391b8d7d188d48994c4564f0946EbA000;
    address constant MAINNET_PRICE_FEED = 0x4050Cd1eDDB589fe26B62F8859968cC9a415cE7F;

    function run() public {
        vm.startBroadcast();

        uint8 decimals = MAINNET_USDC_DECIMALS;

        PriceFeed priceFeed = PriceFeed(MAINNET_PRICE_FEED);
        Payer payer = Payer(MAINNET_PAYER);

        new TokenBuyer(
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
