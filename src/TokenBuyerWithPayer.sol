// SPDX-License-Identifier: GPL-3.0

/// @title ERC20 Token Buyer

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
import { ReentrancyGuard } from 'openzeppelin-contracts/contracts/security/ReentrancyGuard.sol';
import { IPriceFeed } from './IPriceFeed.sol';
import { IOUToken } from './IOUToken.sol';

contract TokenBuyerWithPayer is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error FailedSendingETH(bytes data);
    error FailedWithdrawingETH(bytes data);
    error ReceivedInsufficientTokens(uint256 expected, uint256 actual);

    /// @notice the ERC20 token the owner of this contract wishes to perform payments in.
    IERC20 public immutable paymentToken;

    /// @notice 10**paymentTokenDecimals, for the calculation for ETH price
    uint256 public immutable paymentTokenDecimalsDigits;

    /// @notice the ERC20 token that represents this contracts liabilities in `paymentToken`. Assumed to have 18 decimals.
    IOUToken public immutable iouToken;

    /// @notice the contract used to fetch the price of `paymentToken` in ETH.
    IPriceFeed public priceFeed;

    /// @notice the minimum `paymentToken` balance this contract should aim to hold, in WAD format.
    uint256 public baselinePaymentTokenAmount;

    /// @notice the TODO
    uint16 public botIncentiveFactor;

    address public payer;

    constructor(
        IERC20 _paymentToken,
        uint8 _paymentTokenDecimals,
        IOUToken _iouToken,
        IPriceFeed _priceFeed,
        uint256 _baselinePaymentTokenAmount,
        uint16 _botIncentiveBPs,
        address _owner,
        address _payer
    ) {
        paymentToken = _paymentToken;
        paymentTokenDecimalsDigits = 10**_paymentTokenDecimals;
        iouToken = _iouToken;

        priceFeed = _priceFeed;
        baselinePaymentTokenAmount = _baselinePaymentTokenAmount;
        setBotIncentiveBPs(_botIncentiveBPs);
        _transferOwnership(_owner);

        payer = _payer;
    }

    /**
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
      EXTERNAL TRANSACTIONS
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    /**
     * @notice Buy ETH from this contract in exchange for the ERC20 this token wants to acquire. The price
     * is determined using `priceFeed` plus `botIncentiveBPs` basis points.
     * @dev if `tokenAmount > tokenAmountNeeded()` uses the maximum amount possible. This function allows reentry because it does
     * not allow double spending or exceeding the contract's {tokenAmountNeeded()}.
     * @param tokenAmount the amount of ERC20 tokens msg.sender wishes to sell to this contract in exchange for ETH, in token decimals.
     */
    function buyETH(uint256 tokenAmount) external nonReentrant {
        uint256 amount = min(tokenAmount, tokenAmountNeeded());

        paymentToken.safeTransferFrom(msg.sender, payer, amount);

        safeSendETH(msg.sender, ethAmountPerTokenAmount(amount), '');
    }

    function buyETH(
        uint256 tokenAmount,
        address to,
        bytes calldata data
    ) external nonReentrant {
        uint256 amount = min(tokenAmount, tokenAmountNeeded());
        uint256 balanceBefore = paymentToken.balanceOf(address(this));

        safeSendETH(to, ethAmountPerTokenAmount(amount), abi.encode(msg.sender, amount, data));

        uint256 tokensReceived = paymentToken.balanceOf(address(this)) - balanceBefore;
        if (tokensReceived < amount) {
            revert ReceivedInsufficientTokens(amount, tokensReceived);
        }

        paymentToken.safeTransfer(payer, tokensReceived);
    }

    /**
     * @notice Allow ETH top-ups.
     */
    receive() external payable {}

    /**
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
      VIEW FUNCTIONS
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    /**
     * @notice Get how much ETH this contract needs in order to fund its current obligations plus `additionalTokens`, with
     * a safety buffer `bufferBPs` basis points.
     * @param additionalTokens an additional amount of `paymentToken` liability to use in this ETH requirement calculation, in payment token decimals.
     * @param bufferBPs the number of basis points to add on top of the token liability price in ETH as a safety buffer, e.g.
     * if `bufferBPs` is 10K, the function will return twice the amount it needs according to price alone.
     * @return uint256 the amount of ETH needed to fund `additionalTokens` with a `bufferBPs` safety buffer.
     */
    function ethNeeded(uint256 additionalTokens, uint256 bufferBPs) public view returns (uint256) {
        uint256 tokenAmount = tokenAmountNeeded() + additionalTokens;
        uint256 ethCostOfTokens = ethAmountPerTokenAmount(tokenAmount);
        uint256 ethCostWithBuffer = (ethCostOfTokens * (bufferBPs + 10_000)) / 10_000;

        return ethCostWithBuffer - address(this).balance;
    }

    function tokenAmountNeededAndETHPayout() public view returns (uint256 tokenAmount, uint256 ethAmount) {
        tokenAmount = tokenAmountNeeded();
        ethAmount = ethAmountPerTokenAmount(tokenAmount);
    }

    /**
     * @return uint256 the amount of `paymentToken` this contract is willing to buy in exchange for ETH, in payment token decimals.
     */
    function tokenAmountNeeded() public view returns (uint256) {
        uint256 _paymentTokenBalance = paymentToken.balanceOf(address(this));
        uint256 iouSupply = iouToken.totalSupply();
        unchecked {
            if (_paymentTokenBalance > baselinePaymentTokenAmount + iouSupply) {
                return 0;
            }
            return baselinePaymentTokenAmount + iouSupply - _paymentTokenBalance;
        }
    }

    function ethAmountPerTokenAmount(uint256 tokenAmount) public view returns (uint256) {
        unchecked {
            return (tokenAmount * price()) / paymentTokenDecimalsDigits;
        }
    }

    function price() public view returns (uint256) {
        unchecked {
            return priceFeed.price() * botIncentiveFactor;
        }
    }

    /**
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
      OWNER TRANSACTIONS
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    function withdrawETH() external onlyOwner {
        (bool sent, bytes memory data) = owner().call{ value: address(this).balance }('');
        if (!sent) {
            revert FailedWithdrawingETH(data);
        }
    }

    function setBotIncentiveBPs(uint16 newBotIncentiveBPs) public onlyOwner {
        unchecked {
            botIncentiveFactor = (newBotIncentiveBPs + 10_000) / 10_000;
        }
    }

    /**
     * @param newBaselinePaymentTokenAmount the new `baselinePaymentTokenAmount` in token decimals.
     */
    function setBaselinePaymentTokenAmount(uint256 newBaselinePaymentTokenAmount) external onlyOwner {
        baselinePaymentTokenAmount = newBaselinePaymentTokenAmount;
    }

    function setPriceFeed(IPriceFeed newPriceFeed) external onlyOwner {
        priceFeed = newPriceFeed;
    }

    /**
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
      INTERNAL FUNCTIONS
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    function safeSendETH(
        address to,
        uint256 ethAmount,
        bytes memory data
    ) internal {
        // If contract balance is insufficient it reverts
        (bool sent, ) = to.call{ value: ethAmount }(data);
        if (!sent) {
            // TODO solve error encoding in tests to use add returned data in the error
            revert FailedSendingETH(new bytes(0));
        }
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
