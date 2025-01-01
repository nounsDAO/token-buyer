// SPDX-License-Identifier: GPL-3.0

/// @title swapTokens Callback interface

/*********************************
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 * ░░░░░░█████████░░█████████░░░ *
 * ░░░░░░██░░░████░░██░░░████░░░ *
 * ░░██████░░░████████░░░████░░░ *
 * ░░██░░██░░░████░░██░░░████░░░ *
 * ░░██░░██░░░████░░██░░░████░░░ *
 * ░░░░░░█████████░░█████████░░░ *
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 *********************************/

pragma solidity ^0.8.17;

interface ISwapTokensCallback {
    /**
     * @notice Called on the {to} in TokenBuyerV2#swapTokens, after sending it sellTokens in exchange for {amount} TokenBuyerV2#paymentToken.
     * @param caller the `msg.sender` in TokenBuyerV2#swapTokens
     * @param amount the TokenBuyerV2#paymentToken amount caller is buying sellTokens for
     * @param data arbitrary data passed through by the caller via the TokenBuyerV2#swapTokens call
     */
    function swapTokensCallback(
        address caller,
        uint256 amount,
        bytes calldata data
    ) external payable;
}
