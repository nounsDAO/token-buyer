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
import { DebtQueue } from './DebtQueue.sol';

/**
 * @notice Use this contract to send ERC20 payments, where the ERC20 balance is supplied by {TokenBuyer}. In case of a payment
 * that exceeds the current balance, {Payer} mints {IOUToken}s to the recipient; those tokens can later be redeemed for the payment
 * ERC20 token once there's sufficient balance.
 */
contract PayerQueue is Ownable {
    using SafeERC20 for IERC20Metadata;
    using DebtQueue for DebtQueue.DebtDeque;

    error DecimalsMismatch(uint8 paymentDecimals, uint8 iouDecimals);

    event Redeemed(address indexed account, uint256 amount);

    /// @notice the ERC20 token the owner of this contract wishes to perform payments in.
    IERC20Metadata public immutable paymentToken;

    address public buyer;
    uint256 public totalDebt;
    DebtQueue.DebtDeque public queue;

    constructor(
        address _owner,
        IERC20Metadata _paymentToken
    ) {
        paymentToken = _paymentToken;
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
            registerDebt(account, amount - paymentTokenBalance);
        } else {
            registerDebt(account, amount);
        }
    }

    function withdrawPaymentToken() external onlyOwner {
        paymentToken.safeTransfer(owner(), paymentToken.balanceOf(address(this)));
    }

    function registerDebt(address account, uint256 amount) internal {
        queue.pushBack(DebtQueue.DebtEntry({account: account, amount: amount}));
        totalDebt += amount;
    }

    function payBackDebt(uint256 amount) public {
        while (amount > 0 && !queue.empty()) {
            DebtQueue.DebtEntry storage debt = queue.front();

            uint256 _debtAmount = debt.amount;
            if (amount < _debtAmount) {
                // Not enough to cover entire debt, pay what you can and leave
                debt.amount -= amount; // update debt left
                totalDebt -= amount;
                paymentToken.safeTransfer(debt.account, amount);
                return;
            } else {
                amount -= _debtAmount;
                totalDebt -= _debtAmount;
                paymentToken.safeTransfer(debt.account, _debtAmount);
                queue.popFront(); // remove debt entry
            }
        }
    }
}
