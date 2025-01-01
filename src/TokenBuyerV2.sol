// SPDX-License-Identifier: GPL-3.0

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

import { Ownable } from 'openzeppelin-contracts/contracts/access/Ownable.sol';
import { Pausable } from 'openzeppelin-contracts/contracts/security/Pausable.sol';
import { IERC20Metadata } from 'openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import { SafeERC20 } from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import { ReentrancyGuard } from 'openzeppelin-contracts/contracts/security/ReentrancyGuard.sol';
import { Math } from 'openzeppelin-contracts/contracts/utils/math/Math.sol';
import { IPriceFeed } from './IPriceFeed.sol';
import { ISwapTokensCallback } from './ISwapTokensCallback.sol';
import { IPayer } from './IPayer.sol';

/// @title TokenBuyerV2
/// @notice Buys a payment ERC20 token for another ERC20 at oracle prices
/// It limits the amount of tokens it wants to buy using 2 factors:
///     1. The amount of debt registered in a `Payer` contract
///     2. A minimal "buffer" amount of tokens it wants to maintain
contract TokenBuyerV2 is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20Metadata;

    /**
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
      ERRORS
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    error ReceivedInsufficientTokens(uint256 expected, uint256 actual);
    error OnlyAdminOrOwner();
    error InvalidBotDiscountBPs();
    error InvalidBaselinePaymentTokenAmount();

    /**
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
      EVENTS
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    event SwappedTokens(address indexed to, uint256 sellTokenOut, uint256 paymentTokenIn);
    event BotDiscountBPsSet(uint16 oldBPs, uint16 newBPs);
    event BaselinePaymentTokenAmountSet(uint256 oldAmount, uint256 newAmount);
    event MinAdminBotDiscountBPsSet(uint16 oldBPs, uint16 newBPs);
    event MaxAdminBotDiscountBPsSet(uint16 oldBPs, uint16 newBPs);
    event MinAdminBaselinePaymentTokenAmountSet(uint256 oldAmount, uint256 newAmount);
    event MaxAdminBaselinePaymentTokenAmountSet(uint256 oldAmount, uint256 newAmount);
    event PriceFeedSet(address oldFeed, address newFeed);
    event PayerSet(address oldPayer, address newPayer);
    event AdminSet(address oldAdmin, address newAdmin);

    /**
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
      IMMUTABLES
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    uint256 public constant MAX_BPS = 10_000;

    /// @notice The ERC20 token the owner of this contract wants to exchange for the sellToken
    IERC20Metadata public immutable paymentToken;

    /// @notice The ERC20 token the contract will sell in exchange for paymentToken
    IERC20Metadata public immutable sellToken;

    /// @notice 1 unit of sellToken, e.g. 10^6 for USDC
    uint256 public immutable sellTokenUnit;

    /// @notice 1 unit of paymentToken, e.g. 10^6 for USDC
    uint256 public immutable paymentTokenUnit;

    /**
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
      STORAGE VARIABLES
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    /// @notice a `Payer` contract to which `TokenBuyer` sends the ERC20 tokens. Also used for checking how much debt there is
    IPayer public payer;

    /// @notice The contract used to fetch the price of ETH in `paymentToken`
    IPriceFeed public priceFeed;

    /// @notice The minimum `paymentToken` balance the `payer` contract should have
    uint256 public baselinePaymentTokenAmount;

    /// @notice The minimum allowed value for `baselinePaymentTokenAmount`
    uint256 public minAdminBaselinePaymentTokenAmount;

    /// @notice The maximum allowed value for `baselinePaymentTokenAmount`
    uint256 public maxAdminBaselinePaymentTokenAmount;

    /// @notice the amount of basis points to decrease the price by, to increase the incentive to transact with this contract
    uint16 public botDiscountBPs;

    /// @notice The minimum discount allowed in bps
    uint16 public minAdminBotDiscountBPs;

    /// @notice The maximum discount allowed in bps
    uint16 public maxAdminBotDiscountBPs;

    /// @notice Contract admin, allowed to do certain lower risk operations
    address public admin;

    /// @notice The contract that stETH will be transfered from
    address public treasury;

    /**
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
      MODIFIERS
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    modifier onlyAdminOrOwner() {
        if (admin != msg.sender && owner() != msg.sender) {
            revert OnlyAdminOrOwner();
        }
        _;
    }

    /**
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
      CONSTRUCTOR
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    constructor(
        IPriceFeed _priceFeed,
        uint256 _baselinePaymentTokenAmount,
        uint256 _minAdminBaselinePaymentTokenAmount,
        uint256 _maxAdminBaselinePaymentTokenAmount,
        uint16 _botDiscountBPs,
        uint16 _minAdminBotDiscountBPs,
        uint16 _maxAdminBotDiscountBPs,
        address _owner,
        address _admin,
        address _payer,
        address _sellToken,
        address _treasury
    ) {
        payer = IPayer(_payer);

        address _paymentToken = address(payer.paymentToken());
        paymentToken = IERC20Metadata(_paymentToken);
        paymentTokenUnit = 10**IERC20Metadata(_paymentToken).decimals();
        priceFeed = _priceFeed;

        baselinePaymentTokenAmount = _baselinePaymentTokenAmount;
        minAdminBaselinePaymentTokenAmount = _minAdminBaselinePaymentTokenAmount;
        maxAdminBaselinePaymentTokenAmount = _maxAdminBaselinePaymentTokenAmount;

        if (
            (_botDiscountBPs > MAX_BPS) ||
            (_maxAdminBotDiscountBPs > MAX_BPS) ||
            (_minAdminBotDiscountBPs > _maxAdminBotDiscountBPs)
        ) {
            revert InvalidBotDiscountBPs();
        }
        botDiscountBPs = _botDiscountBPs;
        minAdminBotDiscountBPs = _minAdminBotDiscountBPs;
        maxAdminBotDiscountBPs = _maxAdminBotDiscountBPs;

        _transferOwnership(_owner);
        admin = _admin;
        sellToken = IERC20Metadata(_sellToken);
        sellTokenUnit = 10**IERC20Metadata(_sellToken).decimals();
        treasury = _treasury;
    }

    /**
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
      EXTERNAL TRANSACTIONS
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    /// @notice Buy `sellToken` from this contract in exchange for `paymentToken` tokens.
    /// The price is determined using `priceFeed` plus `botDiscountBPs`
    /// Immediately invokes `payer` to pay back outstanding debt
    /// @dev Caps `tokenAmount` by the amount of tokens the contract needs
    /// @param paymentTokenAmount the amount of ERC20 tokens msg.sender wishes to sell to this contract
    function swapTokens(uint256 paymentTokenAmount) external nonReentrant whenNotPaused {
        uint256 amount = Math.min(paymentTokenAmount, paymentTokenAmountNeeded());

        // Cache payer
        IPayer _payer = payer;

        // Transfer tokens from msg.sender to `payer`
        paymentToken.safeTransferFrom(msg.sender, address(_payer), amount);

        // Invoke `payer` to pay back outstanding debt
        _payer.payBackDebt(amount);

        // Send msg.sender STETH
        uint256 sellTokenAmount = sellTokenAmountPerPaymentTokenAmount(amount);
        safeSendSellToken(msg.sender, sellTokenAmount);

        emit SwappedTokens(msg.sender, sellTokenAmount, amount);
    }

    /// @notice Buy sellToken tokens from this contract in exchange for `paymentToken` tokens.
    /// The price is determined using `priceFeed` plus `botDiscountBPs`
    /// Immediately invokes `payer` to pay back outstanding debt
    /// @dev First sends sellToken to `to`, then invokes the callback afterwhich it checks it received payment tokens.
    /// This allows the caller to swap the sellToken for tokens instead of holding tokens in advance.
    /// @param paymentTokenAmount the amount of paymentToken tokens msg.sender wishes to sell to this contract in exchange for sellToken
    /// @param to the address to send sellToken to by calling the callback function on it
    /// @param data arbitrary data passed through by the caller, usually used for callback verification
    function swapTokens(
        uint256 paymentTokenAmount,
        address to,
        bytes calldata data
    ) external nonReentrant whenNotPaused {
        uint256 amount = Math.min(paymentTokenAmount, paymentTokenAmountNeeded());

        IPayer _payer = payer;

        // Starting balance of `payer`
        uint256 balanceBefore = paymentToken.balanceOf(address(_payer));

        // Send sellToken to `to`
        uint256 sellTokenAmount = sellTokenAmountPerPaymentTokenAmount(amount);
        safeSendSellToken(to, sellTokenAmount);
        ISwapTokensCallback(to).swapTokensCallback(msg.sender, amount, data);

        // Check that `payers` balance increased by the expected amount
        uint256 tokensReceived = paymentToken.balanceOf(address(_payer)) - balanceBefore;
        if (tokensReceived < amount) {
            revert ReceivedInsufficientTokens(amount, tokensReceived);
        }

        // Invoke `payer` to pay back outstanding debt
        _payer.payBackDebt(tokensReceived);

        emit SwappedTokens(to, sellTokenAmount, tokensReceived);
    }

    /**
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
      VIEW FUNCTIONS
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    /// @notice Get how much additional sellToken balance or allowance this contract needs in order to fund its current obligations plus `additionalTokens`.
    /// @param additionalTokens an additional amount of `paymentToken` liability to use in this sellToken requirement calculation.
    /// @return insufficientBalance the amount of additional sellToken the treasury needs
    /// @return insufficientAllowance the amount of additional sellToken allowance this contract needs
    function sellTokenNeeded(uint256 additionalTokens)
        public
        view
        returns (uint256 insufficientBalance, uint256 insufficientAllowance)
    {
        uint256 paymentTokenAmount = paymentTokenAmountNeeded() + additionalTokens;
        uint256 sellTokenAmount = sellTokenAmountPerPaymentTokenAmount(paymentTokenAmount);
        uint256 sellTokenBalance = sellToken.balanceOf(treasury);
        uint256 sellTokenAllowance = sellToken.allowance(treasury, address(this));
        insufficientBalance = sellTokenAmount > sellTokenBalance ? sellTokenAmount - sellTokenBalance : 0;
        insufficientAllowance = sellTokenAmount > sellTokenAllowance ? sellTokenAmount - sellTokenAllowance : 0;
    }

    /// @notice Returns the amount of payment tokens this contract is willing to swap
    /// @return amount of tokens
    function paymentTokenAmountNeeded() public view returns (uint256) {
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

    /// @notice Returns the `sellToken`/`paymentToken` price this contract is willing to swap at, including the discount
    /// @return The price, in 18 decimal format
    function price() public view returns (uint256) {
        unchecked {
            return (priceFeed.price() * (10_000 - botDiscountBPs)) / 10_000;
        }
    }

    /// @notice Returns the amount of sellToken this contract will send in exchange for `tokenAmount` payment tokens
    /// @param paymentTokenAmount the amount of paymentToken tokens
    /// @return amount of sellToken the contract will sell for `tokenAmount` of payment tokens
    function sellTokenAmountPerPaymentTokenAmount(uint256 paymentTokenAmount) public view returns (uint256) {
        unchecked {
            // Example:
            // if sellTokenUnit == 1e10 (10 decimals)
            // if paymentTokenAmount == 3400000000 (3400 USDC) (6 decimals)
            // and price() == 1745910000000000000000 (1745.91) (18 decimals)
            // ((3400000000 * 1e18 * 1e10) / 1745910000000000000000) / 1e6 = 1.947408515e10 (3400/1745.91)
            return ((paymentTokenAmount * 1e18 * sellTokenUnit) / price()) / paymentTokenUnit;
        }
    }

    /// @notice Returns the amount of payment tokens the contract can buy and the amount of sellToken it will pay for it
    /// This takes into account the current sellToken allowance this contract has and the treasury balance
    /// @return paymentTokenAmount amount of tokens the contract can buy
    /// @return sellTokenAmount amount of STETH it will pay for the tokens
    function paymentTokenAmountNeededAndSellTokenPayout() public view returns (uint256, uint256) {
        uint256 paymentTokenAmount = paymentTokenAmountNeeded();
        uint256 sellTokenAmount = sellTokenAmountPerPaymentTokenAmount(paymentTokenAmount);
        uint256 sellTokenAvailable = Math.min(
            sellToken.balanceOf(treasury),
            sellToken.allowance(treasury, address(this))
        );

        if (sellTokenAvailable >= sellTokenAmount) {
            return (paymentTokenAmount, sellTokenAmount);
        } else {
            // Tokens amount will be rounded down to avoid trying to buy more eth than available
            paymentTokenAmount = paymentTokenAmountPerSellTokenAmount(sellTokenAvailable);

            // Recalculate eth amount because tokens amount are rounded down
            sellTokenAmount = sellTokenAmountPerPaymentTokenAmount(paymentTokenAmount);

            return (paymentTokenAmount, sellTokenAmount);
        }
    }

    /// @notice Returns the amount of payment tokens the contract expects in return for sellToken
    /// @param sellTokenAmount amount of sellToken to be swapped
    /// @return amount of tokens the contract will swap sellToken for
    /// @dev result is rounded down
    function paymentTokenAmountPerSellTokenAmount(uint256 sellTokenAmount) public view returns (uint256) {
        return (sellTokenAmount * price() * paymentTokenUnit) / (1e18 * sellTokenUnit);
    }

    /**
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
      ADMIN or OWNER TRANSACTIONS
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    /// @notice Update `botDiscountBPs`
    function setBotDiscountBPs(uint16 newBotDiscountBPs) external onlyAdminOrOwner {
        // Admin is limited to min-max range, owner is not
        if (
            admin == msg.sender &&
            (newBotDiscountBPs < minAdminBotDiscountBPs || newBotDiscountBPs > maxAdminBotDiscountBPs)
        ) {
            revert InvalidBotDiscountBPs();
        }

        emit BotDiscountBPsSet(botDiscountBPs, newBotDiscountBPs);

        botDiscountBPs = newBotDiscountBPs;
    }

    /// @notice Update `baselinePaymentTokenAmount`
    /// @param newBaselinePaymentTokenAmount the new `baselinePaymentTokenAmount` in token decimals.
    function setBaselinePaymentTokenAmount(uint256 newBaselinePaymentTokenAmount) external onlyAdminOrOwner {
        // Admin is limited to min-max range, owner is not
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

    /// @notice pause ETH buying
    function pause() external onlyAdminOrOwner {
        _pause();
    }

    /// @notice unpause ETH buying
    function unpause() external onlyAdminOrOwner {
        _unpause();
    }

    /// @notice set a new Admin
    function setAdmin(address newAdmin) external onlyAdminOrOwner {
        emit AdminSet(admin, newAdmin);

        admin = newAdmin;
    }

    /**
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
      OWNER TRANSACTIONS
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    /// @notice Update minAdminBotDiscountBPs
    function setMinAdminBotDiscountBPs(uint16 newMinAdminBotDiscountBPs) external onlyOwner {
        emit MinAdminBotDiscountBPsSet(minAdminBotDiscountBPs, newMinAdminBotDiscountBPs);

        minAdminBotDiscountBPs = newMinAdminBotDiscountBPs;
    }

    /// @notice Update maxAdminBotDiscountBPs
    function setMaxAdminBotDiscountBPs(uint16 newMaxAdminBotDiscountBPs) external onlyOwner {
        emit MaxAdminBotDiscountBPsSet(maxAdminBotDiscountBPs, newMaxAdminBotDiscountBPs);

        maxAdminBotDiscountBPs = newMaxAdminBotDiscountBPs;
    }

    /// @notice Update minAdminBaselinePaymentTokenAmount
    function setMinAdminBaselinePaymentTokenAmount(uint256 newMinAdminBaselinePaymentTokenAmount) external onlyOwner {
        emit MinAdminBaselinePaymentTokenAmountSet(
            minAdminBaselinePaymentTokenAmount,
            newMinAdminBaselinePaymentTokenAmount
        );

        minAdminBaselinePaymentTokenAmount = newMinAdminBaselinePaymentTokenAmount;
    }

    /// @notice Update maxAdminBaselinePaymentTokenAmount
    function setMaxAdminBaselinePaymentTokenAmount(uint256 newMaxAdminBaselinePaymentTokenAmount) external onlyOwner {
        emit MaxAdminBaselinePaymentTokenAmountSet(
            maxAdminBaselinePaymentTokenAmount,
            newMaxAdminBaselinePaymentTokenAmount
        );

        maxAdminBaselinePaymentTokenAmount = newMaxAdminBaselinePaymentTokenAmount;
    }

    /// @notice Update priceFeed
    function setPriceFeed(IPriceFeed newPriceFeed) external onlyOwner {
        emit PriceFeedSet(address(priceFeed), address(newPriceFeed));

        priceFeed = newPriceFeed;
    }

    /// @notice Update `payer`
    function setPayer(address newPayer) external onlyOwner {
        emit PayerSet(address(payer), newPayer);

        payer = IPayer(newPayer);
    }

    /**
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
      INTERNAL FUNCTIONS
     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    function safeSendSellToken(address to, uint256 amount) internal {
        sellToken.safeTransferFrom(treasury, to, amount);
    }
}
