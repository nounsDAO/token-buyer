// SPDX-License-Identifier: GPL-3.0

/// @title ERC20 Token Payer

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

pragma solidity ^0.8.15;

import { Ownable } from 'openzeppelin-contracts/contracts/access/Ownable.sol';
import { IERC20Metadata } from 'openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import { SafeERC20 } from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import { Math } from 'openzeppelin-contracts/contracts/utils/math/Math.sol';
import { IOUToken } from './IOUToken.sol';

/**
 * @notice Use this contract to send ERC20 payments, where the ERC20 balance is supplied by {TokenBuyer}. In case of a payment
 * that exceeds the current balance, {Payer} mints {IOUToken}s to the recipient; those tokens can later be redeemed for the payment
 * ERC20 token once there's sufficient balance.
 */
contract Payer is Ownable {
    using SafeERC20 for IERC20Metadata;

    error DecimalsMismatch(uint8 paymentDecimals, uint8 iouDecimals);

    /// @notice the ERC20 token the owner of this contract wishes to perform payments in.
    IERC20Metadata public immutable paymentToken;

    /// @notice the ERC20 token that represents this contracts liabilities in `paymentToken`. Assumed to have 18 decimals.
    IOUToken public immutable iouToken;

    address public buyer;

    constructor(
        address _owner,
        IERC20Metadata _paymentToken,
        IOUToken _iouToken
    ) {
        if (_paymentToken.decimals() != _iouToken.decimals()) {
            revert DecimalsMismatch(_paymentToken.decimals(), _iouToken.decimals());
        }

        paymentToken = _paymentToken;
        iouToken = _iouToken;
        _transferOwnership(_owner);
    }

    /**
     * @param account the account to send or mint to.
     * @param amount the amount of tokens `account` should receive, in {paymentToken} decimals.
     */
    function sendOrMint(address account, uint256 amount) external onlyOwner {
        uint256 paymentTokenBalance = paymentToken.balanceOf(address(this));

        if (amount <= paymentTokenBalance) {
            paymentToken.safeTransfer(account, amount);
        } else if (paymentTokenBalance > 0) {
            paymentToken.safeTransfer(account, paymentTokenBalance);
            iouToken.mint(account, amount - paymentTokenBalance);
        } else {
            iouToken.mint(account, amount);
        }
    }

    function withdrawPaymentToken() external onlyOwner {
        paymentToken.safeTransfer(owner(), paymentToken.balanceOf(address(this)));
    }

    /**
     * @notice Redeem `account`'s IOU tokens in exchange for `paymentToken` in a best-effort approach, meaning it will
     * attempt to redeem as much as possible up to `account`'s IOU balance, without reverting even if the amount is zero.
     * Any account can redeem on behalf of `account`.
     * @dev this function burns the IOU token balance that gets exchanged for `paymentToken`.
     * @param account the account whose IOU tokens to redeem in exchange for `paymentToken`s.
     */
    function redeem(address account) external {
        uint256 amount = Math.min(iouToken.balanceOf(account), paymentToken.balanceOf(address(this)));
        _redeem(account, amount);
    }

    function redeem(address account, uint256 amount) external {
        _redeem(account, amount);
    }

    function _redeem(address account, uint256 amount) internal {
        if (amount > 0) {
            iouToken.burn(account, amount);
            paymentToken.safeTransfer(account, amount);
        }
    }
}
