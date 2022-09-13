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
import { IERC20 } from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import { Math } from 'openzeppelin-contracts/contracts/utils/math/Math.sol';
import { DebtQueue } from './libs/DebtQueue.sol';
import { IPayer } from './IPayer.sol';

/**
 * @notice Use this contract to send ERC20 payments, where the ERC20 balance is supplied by {TokenBuyer}. In case of a payment
 * that exceeds the current balance, {Payer} mints {IOUToken}s to the recipient; those tokens can later be redeemed for the payment
 * ERC20 token once there's sufficient balance.
 */
contract Payer is IPayer, Ownable {
    using SafeERC20 for IERC20;
    using DebtQueue for DebtQueue.DebtDeque;

    /**
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
      IMMUTABLES
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    /// @notice the ERC20 token the owner of this contract wishes to perform payments in.
    IERC20 public immutable paymentToken;

    /**
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
      STORAGE VARIABLES
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    uint256 public totalDebt;
    DebtQueue.DebtDeque public queue;

    /**
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
      EVENTS
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    event PaidBackDebt(address indexed account, uint256 amount, uint256 remainingDebt);
    event RegisteredDebt(address indexed account, uint256 amount);
    event TokensWithdrawn(address indexed account, uint256 amount);

    /**
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
      CONSTRUCTOR
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    constructor(address _owner, address _paymentToken) {
        paymentToken = IERC20(_paymentToken);
        _transferOwnership(_owner);
    }

    /**
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
      EXTERNAL FUNCTIONS (ONLY OWNER)
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    /**
     * @param account the account to send or mint to.
     * @param amount the amount of tokens `account` should receive, in {paymentToken} decimals.
     */
    function sendOrRegisterDebt(address account, uint256 amount) external onlyOwner {
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
        address to = owner();
        uint256 amount = paymentToken.balanceOf(address(this));
        paymentToken.safeTransfer(to, amount);

        emit TokensWithdrawn(to, amount);
    }

    /**
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
      EXTERNAL FUNCTIONS (PUBLIC)
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    /// @notice Pays back debt up to `amount` of `paymentToken`
    /// @param amount The maximum amount of tokens to send. This is expected to be the token balance of this contract
    function payBackDebt(uint256 amount) external {
        while (amount > 0 && !queue.empty()) {
            DebtQueue.DebtEntry storage debt = queue.front();

            uint256 _debtAmount = debt.amount;
            address _debtAccount = debt.account;

            if (amount < _debtAmount) {
                // Not enough to cover entire debt, pay what you can and leave
                uint256 remainingDebt = debt.amount - amount;
                debt.amount = remainingDebt; // update remaining debt
                totalDebt -= amount;
                paymentToken.safeTransfer(_debtAccount, amount);
                emit PaidBackDebt(_debtAccount, amount, remainingDebt);
                return;
            } else {
                // Enough to cover entire debt entry, pay in full and remove from queue
                amount -= _debtAmount;
                totalDebt -= _debtAmount;
                paymentToken.safeTransfer(_debtAccount, _debtAmount);
                queue.popFront(); // remove debt entry
                emit PaidBackDebt(_debtAccount, _debtAmount, 0);
            }
        }
    }

    /**
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
      VIEW FUNCTIONS
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    function debtOf(address account) external view returns (uint256 amount) {
        uint256 queueLength = queue.length();
        for (uint256 i; i < queueLength; ++i) {
            DebtQueue.DebtEntry storage debtEntry = queue.at(i);
            if (debtEntry.account == account) {
                amount += debtEntry.amount;
            }
        }
    }

    function queueAt(uint256 index) external view returns (address account, uint256 amount) {
        DebtQueue.DebtEntry storage debtEntry = queue.at(index);
        return (debtEntry.account, debtEntry.amount);
    }

    /**
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
      INTERNAL FUNCTIONS
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    function registerDebt(address account, uint256 amount) internal {
        queue.pushBack(DebtQueue.DebtEntry({ account: account, amount: amount }));
        totalDebt += amount;

        emit RegisteredDebt(account, amount);
    }
}
