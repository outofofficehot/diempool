// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IDIEM } from "./interfaces/IDIEM.sol";

/**
 * @title DIEMPool
 * @author DIEMpool Team
 * @notice A share-based staking pool for DIEM tokens with integrated credit marketplace.
 *
 * @dev Architecture:
 *
 * STAKERS:
 * - Deposit DIEM → receive shares proportional to pool ownership
 * - Shares earn yield from credit sales (USDC)
 * - Yield accrues automatically via accRewardPerShare pattern
 * - Claim USDC anytime without affecting other stakers
 *
 * BUYERS:
 * - Purchase inference credits with USDC
 * - Price decreases throughout the day if credits go unused
 * - USDC payments flow directly to the pool
 *
 * DAILY RESET:
 * - Available credits reset at midnight UTC
 * - Triggered automatically by deposit/withdraw/buy operations
 * - Or manually via resetDay()
 *
 * WITHDRAWAL FLOW (due to DIEM's cooldown):
 * 1. requestWithdraw(amount) - starts 1-day cooldown
 * 2. completeWithdraw() - after cooldown, get DIEM back
 */
contract DIEMPool is ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Operator fee (5% = 500 basis points)
    uint256 public constant OPERATOR_FEE_BPS = 500;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Precision for share and reward calculations
    uint256 public constant PRECISION = 1e18;

    /// @notice Credit precision (1 credit = 1e6 = $1 worth of inference)
    uint256 public constant CREDIT_PRECISION = 1e6;

    /// @notice Base price: 80% of face value ($0.80 per $1 of credits)
    uint256 public constant BASE_PRICE_BPS = 8000;

    /// @notice Minimum price: 50% of face value ($0.50 per $1 of credits)
    uint256 public constant MIN_PRICE_BPS = 5000;

    /// @notice Day duration
    uint256 public constant DAY_DURATION = 1 days;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice DIEM token (Base: 0xf4d97f2da56e8c3098f3a8d538db630a2606a024)
    IDIEM public immutable DIEM;

    /// @notice USDC token for payments
    IERC20 public immutable USDC;

    // ============ Share Accounting ============

    /// @notice Total shares outstanding
    uint256 public totalShares;

    /// @notice Total DIEM actively staked (not in cooldown)
    uint256 public totalStakedDIEM;

    /// @notice Accumulated USDC reward per share (scaled by PRECISION)
    uint256 public accRewardPerShare;

    /// @notice Pending USDC for operator
    uint256 public operatorPendingUSDC;

    // ============ Credit Market ============

    /// @notice Start of the current day (UTC midnight timestamp)
    uint256 public dayStartTimestamp;

    /// @notice Credits available today (in CREDIT_PRECISION units)
    uint256 public availableCreditsToday;

    /// @notice Total credits sold today (for analytics)
    uint256 public creditsSoldToday;

    // ============ Staker Info ============

    struct StakerInfo {
        uint256 shares; // Share balance
        uint256 rewardDebt; // For calculating pending rewards
        uint256 pendingUSDC; // Unclaimed USDC yield
        uint256 stakedDIEM; // DIEM actively staked
        uint256 cooldownDIEM; // DIEM in cooldown
        uint256 cooldownEnd; // When cooldown completes
    }

    mapping(address => StakerInfo) public stakers;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposited(address indexed user, uint256 diemAmount, uint256 sharesIssued);
    event WithdrawRequested(address indexed user, uint256 diemAmount, uint256 cooldownEnd);
    event WithdrawCompleted(address indexed user, uint256 diemAmount);
    event WithdrawCancelled(address indexed user, uint256 diemAmount);
    event YieldClaimed(address indexed user, uint256 usdcAmount);
    event OperatorYieldClaimed(address indexed operator, uint256 usdcAmount);
    event CreditsPurchased(
        address indexed buyer, uint256 creditAmount, uint256 usdcPaid, uint256 pricePerCredit
    );
    event DayReset(uint256 newDayStart, uint256 availableCredits, uint256 previousDayUtilization);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error ZeroAmount();
    error ZeroAddress();
    error InsufficientStake();
    error InsufficientCredits();
    error NoCooldownPending();
    error CooldownNotComplete();
    error CooldownAlreadyPending();
    error NoYieldToClaim();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _diem, address _usdc, address _owner) Ownable(_owner) {
        if (_diem == address(0)) revert ZeroAddress();
        if (_usdc == address(0)) revert ZeroAddress();

        DIEM = IDIEM(_diem);
        USDC = IERC20(_usdc);

        // Initialize day
        dayStartTimestamp = _startOfDay(block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                            DAILY RESET
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check and reset day if needed
     * @dev Called internally by deposit, withdraw, buyCredits
     */
    function _checkAndResetDay() internal {
        if (block.timestamp >= dayStartTimestamp + DAY_DURATION) {
            uint256 previousUtilization = 0;
            if (availableCreditsToday > 0) {
                previousUtilization = (creditsSoldToday * BPS_DENOMINATOR)
                    / (availableCreditsToday + creditsSoldToday);
            }

            // Reset for new day
            dayStartTimestamp = _startOfDay(block.timestamp);

            // Available credits = totalStakedDIEM * $1/day (in CREDIT_PRECISION)
            // 1 DIEM (1e18) generates 1e6 credits per day
            availableCreditsToday = (totalStakedDIEM * CREDIT_PRECISION) / PRECISION;
            creditsSoldToday = 0;

            emit DayReset(dayStartTimestamp, availableCreditsToday, previousUtilization);
        }
    }

    /**
     * @notice Manually trigger day reset (anyone can call)
     */
    function resetDay() external {
        _checkAndResetDay();
    }

    /**
     * @notice Get start of day (midnight UTC) for a timestamp
     */
    function _startOfDay(uint256 timestamp) internal pure returns (uint256) {
        return (timestamp / DAY_DURATION) * DAY_DURATION;
    }

    /*//////////////////////////////////////////////////////////////
                            STAKER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit DIEM to the pool and receive shares
     * @param amount Amount of DIEM to deposit
     */
    function deposit(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();

        _checkAndResetDay();
        _updateStakerRewards(msg.sender);

        // Calculate shares to issue
        uint256 sharesToIssue;
        if (totalShares == 0) {
            sharesToIssue = amount; // 1:1 for first deposit
        } else {
            // Proportional to existing shares/DIEM ratio
            sharesToIssue = (amount * totalShares) / totalStakedDIEM;
        }

        // Transfer DIEM from user
        IERC20(address(DIEM)).safeTransferFrom(msg.sender, address(this), amount);

        // Stake DIEM to DIEM contract
        DIEM.stake(amount);

        // Update state
        StakerInfo storage staker = stakers[msg.sender];
        staker.shares += sharesToIssue;
        staker.stakedDIEM += amount;
        staker.rewardDebt = (staker.shares * accRewardPerShare) / PRECISION;

        totalShares += sharesToIssue;
        totalStakedDIEM += amount;

        // Update available credits for today
        availableCreditsToday += (amount * CREDIT_PRECISION) / PRECISION;

        emit Deposited(msg.sender, amount, sharesToIssue);
    }

    /**
     * @notice Request withdrawal (starts cooldown)
     * @param amount Amount of DIEM to withdraw
     */
    function requestWithdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        StakerInfo storage staker = stakers[msg.sender];
        if (staker.stakedDIEM < amount) revert InsufficientStake();
        if (staker.cooldownDIEM > 0) revert CooldownAlreadyPending();

        _checkAndResetDay();
        _updateStakerRewards(msg.sender);

        // Calculate shares to burn (proportional)
        uint256 sharesToBurn = (amount * staker.shares) / staker.stakedDIEM;

        // Update state
        staker.shares -= sharesToBurn;
        staker.stakedDIEM -= amount;
        staker.cooldownDIEM = amount;
        staker.cooldownEnd = block.timestamp + DIEM.cooldownDuration();
        staker.rewardDebt = (staker.shares * accRewardPerShare) / PRECISION;

        totalShares -= sharesToBurn;
        totalStakedDIEM -= amount;

        // Reduce available credits
        uint256 creditsToRemove = (amount * CREDIT_PRECISION) / PRECISION;
        if (creditsToRemove > availableCreditsToday) {
            availableCreditsToday = 0;
        } else {
            availableCreditsToday -= creditsToRemove;
        }

        // Initiate unstake on DIEM contract
        DIEM.initiateUnstake(amount);

        emit WithdrawRequested(msg.sender, amount, staker.cooldownEnd);
    }

    /**
     * @notice Complete withdrawal after cooldown
     */
    function completeWithdraw() external nonReentrant {
        StakerInfo storage staker = stakers[msg.sender];
        if (staker.cooldownDIEM == 0) revert NoCooldownPending();
        if (block.timestamp < staker.cooldownEnd) revert CooldownNotComplete();

        _checkAndResetDay();

        uint256 amount = staker.cooldownDIEM;
        staker.cooldownDIEM = 0;
        staker.cooldownEnd = 0;

        // Complete unstake on DIEM contract
        DIEM.unstake();

        // Transfer DIEM to user
        IERC20(address(DIEM)).safeTransfer(msg.sender, amount);

        emit WithdrawCompleted(msg.sender, amount);
    }

    /**
     * @notice Cancel pending withdrawal and re-stake
     */
    function cancelWithdraw() external nonReentrant {
        StakerInfo storage staker = stakers[msg.sender];
        if (staker.cooldownDIEM == 0) revert NoCooldownPending();

        _checkAndResetDay();
        _updateStakerRewards(msg.sender);

        uint256 amount = staker.cooldownDIEM;

        // Calculate shares to issue (at current ratio)
        uint256 sharesToIssue;
        if (totalShares == 0) {
            sharesToIssue = amount;
        } else {
            sharesToIssue = (amount * totalShares) / totalStakedDIEM;
        }

        // Update state
        staker.cooldownDIEM = 0;
        staker.cooldownEnd = 0;
        staker.shares += sharesToIssue;
        staker.stakedDIEM += amount;
        staker.rewardDebt = (staker.shares * accRewardPerShare) / PRECISION;

        totalShares += sharesToIssue;
        totalStakedDIEM += amount;

        // Add back to available credits
        availableCreditsToday += (amount * CREDIT_PRECISION) / PRECISION;

        emit WithdrawCancelled(msg.sender, amount);
    }

    /**
     * @notice Claim accrued USDC yield
     */
    function claimYield() external nonReentrant {
        _checkAndResetDay();
        _updateStakerRewards(msg.sender);

        uint256 pending = stakers[msg.sender].pendingUSDC;
        if (pending == 0) revert NoYieldToClaim();

        stakers[msg.sender].pendingUSDC = 0;
        USDC.safeTransfer(msg.sender, pending);

        emit YieldClaimed(msg.sender, pending);
    }

    /*//////////////////////////////////////////////////////////////
                          CREDIT MARKETPLACE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Buy inference credits with USDC
     * @param creditAmount Amount of credits to buy (in CREDIT_PRECISION, 1e6 = $1)
     * @return usdcCost Actual USDC paid
     */
    function buyCredits(uint256 creditAmount)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 usdcCost)
    {
        if (creditAmount == 0) revert ZeroAmount();

        _checkAndResetDay();

        if (creditAmount > availableCreditsToday) revert InsufficientCredits();

        // Calculate price
        uint256 priceBps = getCurrentPrice();
        usdcCost = (creditAmount * priceBps) / BPS_DENOMINATOR;

        // Transfer USDC from buyer
        USDC.safeTransferFrom(msg.sender, address(this), usdcCost);

        // Update credits
        availableCreditsToday -= creditAmount;
        creditsSoldToday += creditAmount;

        // Distribute USDC to stakers (minus operator fee)
        _distributeUSDC(usdcCost);

        emit CreditsPurchased(msg.sender, creditAmount, usdcCost, priceBps);
    }

    /**
     * @notice Buy credits by specifying max USDC to spend
     * @param maxUSDC Maximum USDC to spend
     * @return creditAmount Credits received
     */
    function buyCreditsWithMaxUSDC(uint256 maxUSDC)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 creditAmount)
    {
        if (maxUSDC == 0) revert ZeroAmount();

        _checkAndResetDay();

        uint256 priceBps = getCurrentPrice();

        // Calculate credits: credits = usdc * 10000 / price
        creditAmount = (maxUSDC * BPS_DENOMINATOR) / priceBps;

        if (creditAmount > availableCreditsToday) {
            creditAmount = availableCreditsToday;
        }

        if (creditAmount == 0) revert InsufficientCredits();

        // Recalculate actual cost
        uint256 actualCost = (creditAmount * priceBps) / BPS_DENOMINATOR;

        // Transfer USDC from buyer
        USDC.safeTransferFrom(msg.sender, address(this), actualCost);

        // Update credits
        availableCreditsToday -= creditAmount;
        creditsSoldToday += creditAmount;

        // Distribute USDC to stakers
        _distributeUSDC(actualCost);

        emit CreditsPurchased(msg.sender, creditAmount, actualCost, priceBps);
    }

    /**
     * @notice Get current credit price in basis points of face value
     * @return priceBps Price (e.g., 8000 = $0.80 per $1 credit)
     *
     * @dev Pricing model:
     * - Starts at BASE_PRICE (80%) at start of day
     * - Decreases toward MIN_PRICE (50%) as day progresses IF credits are unused
     * - Higher utilization = less discount
     */
    function getCurrentPrice() public view returns (uint256 priceBps) {
        // If new day needed, return base price
        if (block.timestamp >= dayStartTimestamp + DAY_DURATION) {
            return BASE_PRICE_BPS;
        }

        // Time progress through day (0 to PRECISION)
        uint256 timeProgress = ((block.timestamp - dayStartTimestamp) * PRECISION) / DAY_DURATION;

        // Utilization (0 to PRECISION)
        uint256 totalCreditsToday = availableCreditsToday + creditsSoldToday;
        uint256 utilizationPct = 0;
        if (totalCreditsToday > 0) {
            utilizationPct = (creditsSoldToday * PRECISION) / totalCreditsToday;
        }

        // Unused ratio (inverted utilization)
        uint256 unusedPct = PRECISION - utilizationPct;

        // Max discount based on time and unused credits
        // Discount increases with time AND with unused percentage
        uint256 maxDiscount = BASE_PRICE_BPS - MIN_PRICE_BPS; // 3000 bps = 30%
        uint256 discount = (maxDiscount * timeProgress * unusedPct) / (PRECISION * PRECISION);

        priceBps = BASE_PRICE_BPS - discount;
        if (priceBps < MIN_PRICE_BPS) {
            priceBps = MIN_PRICE_BPS;
        }
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Distribute incoming USDC to stakers
     */
    function _distributeUSDC(uint256 amount) internal {
        if (totalShares == 0) {
            // No stakers, all goes to operator
            operatorPendingUSDC += amount;
            return;
        }

        // Operator fee (5%)
        uint256 operatorFee = (amount * OPERATOR_FEE_BPS) / BPS_DENOMINATOR;
        uint256 stakerAmount = amount - operatorFee;

        operatorPendingUSDC += operatorFee;

        // Update accumulated reward per share
        accRewardPerShare += (stakerAmount * PRECISION) / totalShares;
    }

    /**
     * @notice Update a staker's pending rewards
     */
    function _updateStakerRewards(address user) internal {
        StakerInfo storage staker = stakers[user];

        if (staker.shares > 0) {
            uint256 accumulatedReward = (staker.shares * accRewardPerShare) / PRECISION;
            if (accumulatedReward > staker.rewardDebt) {
                staker.pendingUSDC += accumulatedReward - staker.rewardDebt;
            }
        }

        staker.rewardDebt = (staker.shares * accRewardPerShare) / PRECISION;
    }

    /*//////////////////////////////////////////////////////////////
                           OPERATOR FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claim operator's accumulated fees
     */
    function claimOperatorYield() external onlyOwner nonReentrant {
        uint256 pending = operatorPendingUSDC;
        if (pending == 0) revert NoYieldToClaim();

        operatorPendingUSDC = 0;
        USDC.safeTransfer(owner(), pending);

        emit OperatorYieldClaimed(owner(), pending);
    }

    /**
     * @notice Re-stake any liquid DIEM (edge case handling)
     */
    function restakeUnstakedDiem() external onlyOwner nonReentrant {
        uint256 balance = IERC20(address(DIEM)).balanceOf(address(this));
        if (balance > 0) {
            DIEM.stake(balance);
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get staker's pending USDC yield
     */
    function pendingYield(address user) external view returns (uint256) {
        StakerInfo storage staker = stakers[user];

        uint256 accReward = accRewardPerShare;
        uint256 accumulated = (staker.shares * accReward) / PRECISION;
        uint256 pending = staker.pendingUSDC;

        if (accumulated > staker.rewardDebt) {
            pending += accumulated - staker.rewardDebt;
        }

        return pending;
    }

    /**
     * @notice Get staker's share of the pool
     */
    function getSharePercentage(address user) external view returns (uint256 bps) {
        if (totalShares == 0) return 0;
        return (stakers[user].shares * BPS_DENOMINATOR) / totalShares;
    }

    /**
     * @notice Get withdrawal status
     */
    function withdrawalStatus(address user)
        external
        view
        returns (uint256 amount, uint256 cooldownEnd, bool canComplete)
    {
        StakerInfo storage staker = stakers[user];
        return (
            staker.cooldownDIEM,
            staker.cooldownEnd,
            staker.cooldownDIEM > 0 && block.timestamp >= staker.cooldownEnd
        );
    }

    /**
     * @notice Get credit market status
     */
    function getCreditMarketStatus()
        external
        view
        returns (
            uint256 _availableCredits,
            uint256 _creditsSold,
            uint256 _currentPrice,
            uint256 _timeRemainingInDay
        )
    {
        uint256 dayEnd = dayStartTimestamp + DAY_DURATION;
        uint256 timeRemaining = block.timestamp >= dayEnd ? 0 : dayEnd - block.timestamp;

        return (availableCreditsToday, creditsSoldToday, getCurrentPrice(), timeRemaining);
    }

    /**
     * @notice Get pool statistics
     */
    function getPoolStats()
        external
        view
        returns (
            uint256 _totalShares,
            uint256 _totalStakedDIEM,
            uint256 _accRewardPerShare,
            uint256 _operatorPendingUSDC
        )
    {
        return (totalShares, totalStakedDIEM, accRewardPerShare, operatorPendingUSDC);
    }

    /**
     * @notice Get DIEM cooldown duration
     */
    function getCooldownDuration() external view returns (uint256) {
        return DIEM.cooldownDuration();
    }
}
