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
import { Pausable } from 'openzeppelin-contracts/contracts/security/Pausable.sol';
import { IERC20Metadata } from 'openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import { SafeERC20 } from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import { ReentrancyGuard } from 'openzeppelin-contracts/contracts/security/ReentrancyGuard.sol';
import { Math } from 'openzeppelin-contracts/contracts/utils/math/Math.sol';
import { IPriceFeed } from './IPriceFeed.sol';
import { IBuyETHCallback } from './IBuyETHCallback.sol';
import { IPayer } from './IPayer.sol';

/**
 * @notice Use this contract to exchange ETH for any ERC20 token at oracle prices.
 * @dev Inspired by https://github.com/banteg/yfi-buyer.
 */
contract TokenBuyer is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20Metadata;

    error FailedSendingETH(bytes data);
    error FailedWithdrawingETH(bytes data);
    error ReceivedInsufficientTokens(uint256 expected, uint256 actual);
    error OnlyAdmin();
    error OnlyAdminOrOwner();
    error InvalidBotIncentiveBPs();
    error InvalidBaselinePaymentTokenAmount();

    event SoldETH(address indexed to, uint256 ethOut, uint256 tokenIn);
    event BotIncentiveBPsSet(uint16 oldBPs, uint16 newBPs);
    event BaselinePaymentTokenAmountSet(uint256 oldAmount, uint256 newAmount);
    event ETHWithdrawn(address indexed to, uint256 amount);
    event MinAdminBotIncentiveBPsSet(uint16 oldBPs, uint16 newBPs);
    event MaxAdminBotIncentiveBPsSet(uint16 oldBPs, uint16 newBPs);
    event MinAdminBaselinePaymentTokenAmountSet(uint256 oldAmount, uint256 newAmount);
    event MaxAdminBaselinePaymentTokenAmountSet(uint256 oldAmount, uint256 newAmount);
    event PriceFeedSet(address oldFeed, address newFeed);
    event PayerSet(address oldPayer, address newPayer);
    event AdminSet(address oldAdmin, address newAdmin);

    /// @notice the ERC20 token the owner of this contract wishes to perform payments in.
    IERC20Metadata public immutable paymentToken;

    /// @notice 10**paymentTokenDecimals, for the calculation for ETH price
    uint256 public immutable paymentTokenDecimalsDigits;

    /**
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
      STORAGE VARIABLES
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    /// @notice the contract used to fetch the price of `paymentToken` in ETH.
    IPriceFeed public priceFeed;

    /// @notice the minimum `paymentToken` balance this contract should aim to hold, in WAD format.
    uint256 public baselinePaymentTokenAmount;

    uint256 public minAdminBaselinePaymentTokenAmount;

    uint256 public maxAdminBaselinePaymentTokenAmount;

    /// @notice the amount of basis points to increase `paymentToken` price by, to increase the incentive to transact with this contract.
    uint16 public botIncentiveBPs;

    uint16 public minAdminBotIncentiveBPs;

    uint16 public maxAdminBotIncentiveBPs;

    address public admin;

    IPayer public payer;

    modifier onlyAdmin() {
        if (admin != msg.sender) {
            revert OnlyAdmin();
        }
        _;
    }

    modifier onlyAdminOrOwner() {
        if (admin != msg.sender && owner() != msg.sender) {
            revert OnlyAdminOrOwner();
        }
        _;
    }

    constructor(
        IERC20Metadata _paymentToken,
        IPriceFeed _priceFeed,
        uint256 _baselinePaymentTokenAmount,
        uint256 _minAdminBaselinePaymentTokenAmount,
        uint256 _maxAdminBaselinePaymentTokenAmount,
        uint16 _botIncentiveBPs,
        uint16 _minAdminBotIncentiveBPs,
        uint16 _maxAdminBotIncentiveBPs,
        address _owner,
        address _admin,
        address _payer
    ) {
        paymentToken = _paymentToken;
        paymentTokenDecimalsDigits = 10**_paymentToken.decimals();
        priceFeed = _priceFeed;

        baselinePaymentTokenAmount = _baselinePaymentTokenAmount;
        minAdminBaselinePaymentTokenAmount = _minAdminBaselinePaymentTokenAmount;
        maxAdminBaselinePaymentTokenAmount = _maxAdminBaselinePaymentTokenAmount;

        botIncentiveBPs = _botIncentiveBPs;
        minAdminBotIncentiveBPs = _minAdminBotIncentiveBPs;
        maxAdminBotIncentiveBPs = _maxAdminBotIncentiveBPs;

        _transferOwnership(_owner);
        admin = _admin;

        payer = IPayer(_payer);
    }

    /**
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
      EXTERNAL TRANSACTIONS
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    /**
     * @notice Buy ETH from this contract in exchange for the ERC20 {paymentToken} this token wants to acquire. The price
     * is determined using `priceFeed` plus `botIncentiveBPs` basis points.
     * @dev if `tokenAmount > tokenAmountNeeded()` uses the maximum amount possible.
     * @param tokenAmount the amount of ERC20 tokens msg.sender wishes to sell to this contract in exchange for ETH, in token decimals.
     */
    function buyETH(uint256 tokenAmount) external nonReentrant whenNotPaused {
        uint256 amount = Math.min(tokenAmount, tokenAmountNeeded());

        IPayer _payer = payer;
        paymentToken.safeTransferFrom(msg.sender, address(_payer), amount);
        _payer.payBackDebt(amount);

        uint256 ethAmount = ethAmountPerTokenAmount(amount);
        safeSendETH(msg.sender, ethAmount, '');

        emit SoldETH(msg.sender, ethAmount, amount);
    }

    /**
     * @notice Buy ETH from this contract in exchange for the ERC20 {paymentToken} this token wants to acquire. The price
     * is determined using {priceFeed} plus {botIncentiveBPs} basis points.
     * @dev if `tokenAmount > tokenAmountNeeded()` uses the maximum amount possible. This function sends ETH to the `to` address
     * by calling the callback function IBuyETHCallback#buyETHCallback.
     * @param tokenAmount the amount of ERC20 tokens msg.sender wishes to sell to this contract in exchange for ETH, in token decimals.
     * @param to the address to send ETH to by calling the callback function on it
     * @param data arbitrary data passed through by the caller, usually used for callback verification
     */
    function buyETH(
        uint256 tokenAmount,
        address to,
        bytes calldata data
    ) external nonReentrant whenNotPaused {
        uint256 amount = Math.min(tokenAmount, tokenAmountNeeded());
        address _payer = address(payer);
        uint256 balanceBefore = paymentToken.balanceOf(_payer);
        uint256 ethAmount = ethAmountPerTokenAmount(amount);

        IBuyETHCallback(to).buyETHCallback{ value: ethAmount }(msg.sender, amount, data);

        uint256 tokensReceived = paymentToken.balanceOf(_payer) - balanceBefore;
        if (tokensReceived < amount) {
            revert ReceivedInsufficientTokens(amount, tokensReceived);
        }
        payer.payBackDebt(amount);

        emit SoldETH(to, ethAmount, amount);
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
        IPayer _payer = payer;
        uint256 _tokensAvailable = paymentToken.balanceOf(address(_payer));
        uint256 totalDebt = _payer.totalDebt();
        unchecked {
            uint256 neededTokens = baselinePaymentTokenAmount + totalDebt;
            if (_tokensAvailable > neededTokens) {
                return 0;
            }
            return neededTokens - _tokensAvailable;
        }
    }

    function ethAmountPerTokenAmount(uint256 tokenAmount) public view returns (uint256) {
        unchecked {
            return (tokenAmount * price()) / paymentTokenDecimalsDigits;
        }
    }

    function price() public view returns (uint256) {
        unchecked {
            return (priceFeed.price() * (botIncentiveBPs + 10_000)) / 10_000;
        }
    }

    /**
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
      ADMIN or OWNER TRANSACTIONS
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    function setBotIncentiveBPs(uint16 newBotIncentiveBPs) external onlyAdminOrOwner {
        if (
            admin == msg.sender &&
            (newBotIncentiveBPs < minAdminBotIncentiveBPs || newBotIncentiveBPs > maxAdminBotIncentiveBPs)
        ) {
            revert InvalidBotIncentiveBPs();
        }

        emit BotIncentiveBPsSet(botIncentiveBPs, newBotIncentiveBPs);

        botIncentiveBPs = newBotIncentiveBPs;
    }

    /**
     * @param newBaselinePaymentTokenAmount the new `baselinePaymentTokenAmount` in token decimals.
     */
    function setBaselinePaymentTokenAmount(uint256 newBaselinePaymentTokenAmount) external onlyAdminOrOwner {
        if (
            admin == msg.sender &&
            (newBaselinePaymentTokenAmount < minAdminBaselinePaymentTokenAmount ||
                newBaselinePaymentTokenAmount > maxAdminBaselinePaymentTokenAmount)
        ) {
            revert InvalidBaselinePaymentTokenAmount();
        }

        emit BaselinePaymentTokenAmountSet(baselinePaymentTokenAmount, newBaselinePaymentTokenAmount);

        baselinePaymentTokenAmount = newBaselinePaymentTokenAmount;
    }

    function pause() external onlyAdminOrOwner {
        _pause();
    }

    function unpause() external onlyAdminOrOwner {
        _unpause();
    }

    function withdrawETH() external onlyAdminOrOwner {
        uint256 amount = address(this).balance;
        address to = owner();

        (bool sent, bytes memory data) = to.call{ value: amount }('');
        if (!sent) {
            revert FailedWithdrawingETH(data);
        }

        emit ETHWithdrawn(to, amount);
    }

    /**
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
      OWNER TRANSACTIONS
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    function setMinAdminBotIncentiveBPs(uint16 newMinAdminBotIncentiveBPs) external onlyOwner {
        emit MinAdminBotIncentiveBPsSet(minAdminBotIncentiveBPs, newMinAdminBotIncentiveBPs);

        minAdminBotIncentiveBPs = newMinAdminBotIncentiveBPs;
    }

    function setMaxAdminBotIncentiveBPs(uint16 newMaxAdminBotIncentiveBPs) external onlyOwner {
        emit MaxAdminBotIncentiveBPsSet(maxAdminBotIncentiveBPs, newMaxAdminBotIncentiveBPs);

        maxAdminBotIncentiveBPs = newMaxAdminBotIncentiveBPs;
    }

    function setMinAdminBaselinePaymentTokenAmount(uint256 newMinAdminBaselinePaymentTokenAmount) external onlyOwner {
        emit MinAdminBaselinePaymentTokenAmountSet(
            minAdminBaselinePaymentTokenAmount,
            newMinAdminBaselinePaymentTokenAmount
        );

        minAdminBaselinePaymentTokenAmount = newMinAdminBaselinePaymentTokenAmount;
    }

    function setMaxAdminBaselinePaymentTokenAmount(uint256 newMaxAdminBaselinePaymentTokenAmount) external onlyOwner {
        emit MaxAdminBaselinePaymentTokenAmountSet(
            maxAdminBaselinePaymentTokenAmount,
            newMaxAdminBaselinePaymentTokenAmount
        );

        maxAdminBaselinePaymentTokenAmount = newMaxAdminBaselinePaymentTokenAmount;
    }

    function setPriceFeed(IPriceFeed newPriceFeed) external onlyOwner {
        emit PriceFeedSet(address(priceFeed), address(newPriceFeed));

        priceFeed = newPriceFeed;
    }

    function setPayer(address newPayer) external onlyOwner {
        emit PayerSet(address(payer), newPayer);

        payer = IPayer(newPayer);
    }

    function setAdmin(address newAdmin) external onlyOwner {
        emit AdminSet(admin, newAdmin);

        admin = newAdmin;
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
        (bool sent, bytes memory returnData) = to.call{ value: ethAmount }(data);
        if (!sent) {
            revert FailedSendingETH(returnData);
        }
    }
}