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
 * @notice A non-custodial staking pool for DIEM tokens that enables yield generation
 *         from AI inference credit sales.
 *
 * @dev Architecture:
 * - Users deposit DIEM tokens to this contract
 * - DIEMPool stakes the DIEM to the DIEM contract (generating inference credits)
 * - The pooled credits are associated with the operator's Venice account (off-chain)
 * - Buyers pay for inference credits (off-chain), revenue flows to this contract
 * - 95% of revenue goes to stakers proportionally, 5% to the operator
 *
 * Withdrawal Flow (due to DIEM's cooldown):
 * 1. User calls requestWithdraw(amount) - initiates unstake on DIEM contract
 * 2. Wait for cooldown period (currently 1 day on DIEM contract)
 * 3. User calls completeWithdraw() - completes unstake and transfers DIEM to user
 *
 * Security Model:
 * - Non-custodial: Only the original staker can withdraw their DIEM
 * - Operator cannot withdraw staked DIEM, only their fee share
 * - All staker accounting is on-chain and verifiable
 */
contract DIEMPool is ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Fee percentage taken by operator (5% = 500 basis points)
    uint256 public constant OPERATOR_FEE_BPS = 500;

    /// @notice Basis points denominator
    uint256 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Precision for accumulated yield per share calculations
    uint256 public constant PRECISION = 1e18;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The DIEM token contract (on Base: 0xf4d97f2da56e8c3098f3a8d538db630a2606a024)
    IDIEM public immutable DIEM;

    /// @notice The token used for yield payments (e.g., USDC)
    IERC20 public immutable yieldToken;

    /// @notice Total DIEM deposited and actively staked in the pool
    uint256 public totalStaked;

    /// @notice Total DIEM currently in cooldown (requested withdrawal)
    uint256 public totalInCooldown;

    /// @notice Accumulated yield per staked DIEM (scaled by PRECISION)
    uint256 public accYieldPerShare;

    /// @notice Pending yield for operator
    uint256 public operatorPendingYield;

    /// @notice Staker info
    struct StakerInfo {
        uint256 stakedAmount; // Amount of DIEM staked and earning yield
        uint256 rewardDebt; // Reward debt for yield calculation
        uint256 pendingYield; // Unclaimed yield
        uint256 cooldownAmount; // Amount in cooldown (pending withdrawal)
        uint256 cooldownEnd; // Timestamp when cooldown ends
    }

    /// @notice Mapping of staker address to their info
    mapping(address => StakerInfo) public stakers;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposited(address indexed user, uint256 amount);
    event WithdrawRequested(address indexed user, uint256 amount, uint256 cooldownEnd);
    event WithdrawCompleted(address indexed user, uint256 amount);
    event YieldDistributed(uint256 totalAmount, uint256 stakerAmount, uint256 operatorAmount);
    event YieldClaimed(address indexed user, uint256 amount);
    event OperatorYieldClaimed(address indexed operator, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error ZeroAmount();
    error ZeroAddress();
    error InsufficientStake();
    error NoCooldownPending();
    error CooldownNotComplete();
    error NoYieldToClaim();
    error NoStakers();
    error CooldownAlreadyPending();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the DIEMPool
     * @param _diem Address of the DIEM token (0xf4d97f2da56e8c3098f3a8d538db630a2606a024 on Base)
     * @param _yieldToken Address of the yield token (e.g., USDC)
     * @param _owner Address of the operator/owner
     */
    constructor(address _diem, address _yieldToken, address _owner) Ownable(_owner) {
        if (_diem == address(0)) revert ZeroAddress();
        if (_yieldToken == address(0)) revert ZeroAddress();

        DIEM = IDIEM(_diem);
        yieldToken = IERC20(_yieldToken);
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT FUNCTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit DIEM tokens to the pool
     * @param amount Amount of DIEM to deposit
     * @dev Transfers DIEM from user, then stakes it to the DIEM contract
     */
    function deposit(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();

        // Update staker's pending yield before changing their stake
        _updateStakerYield(msg.sender);

        // Transfer DIEM from user to this contract
        IERC20(address(DIEM)).safeTransferFrom(msg.sender, address(this), amount);

        // Stake the DIEM to the DIEM contract (generates inference credits)
        DIEM.stake(amount);

        // Update staker info
        StakerInfo storage staker = stakers[msg.sender];
        staker.stakedAmount += amount;
        staker.rewardDebt = (staker.stakedAmount * accYieldPerShare) / PRECISION;

        // Update total staked
        totalStaked += amount;

        emit Deposited(msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                          WITHDRAWAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Request withdrawal of DIEM tokens (starts cooldown)
     * @param amount Amount of DIEM to withdraw
     * @dev Initiates unstake on DIEM contract. User must call completeWithdraw after cooldown.
     */
    function requestWithdraw(uint256 amount) external nonReentrant {
        StakerInfo storage staker = stakers[msg.sender];
        if (amount == 0) revert ZeroAmount();
        if (staker.stakedAmount < amount) revert InsufficientStake();
        if (staker.cooldownAmount > 0) revert CooldownAlreadyPending();

        // Update staker's pending yield before changing their stake
        _updateStakerYield(msg.sender);

        // Update staker info - move from staked to cooldown
        staker.stakedAmount -= amount;
        staker.cooldownAmount = amount;
        staker.cooldownEnd = block.timestamp + DIEM.cooldownDuration();
        staker.rewardDebt = (staker.stakedAmount * accYieldPerShare) / PRECISION;

        // Update totals
        totalStaked -= amount;
        totalInCooldown += amount;

        // Initiate unstake on DIEM contract
        DIEM.initiateUnstake(amount);

        emit WithdrawRequested(msg.sender, amount, staker.cooldownEnd);
    }

    /**
     * @notice Complete withdrawal after cooldown period
     * @dev Completes unstake on DIEM contract and transfers DIEM to user
     */
    function completeWithdraw() external nonReentrant {
        StakerInfo storage staker = stakers[msg.sender];
        if (staker.cooldownAmount == 0) revert NoCooldownPending();
        if (block.timestamp < staker.cooldownEnd) revert CooldownNotComplete();

        uint256 amount = staker.cooldownAmount;

        // Reset cooldown state
        staker.cooldownAmount = 0;
        staker.cooldownEnd = 0;
        totalInCooldown -= amount;

        // Complete unstake on DIEM contract (DIEM transfers to this contract)
        DIEM.unstake();

        // Transfer DIEM to user
        IERC20(address(DIEM)).safeTransfer(msg.sender, amount);

        emit WithdrawCompleted(msg.sender, amount);
    }

    /**
     * @notice Cancel a pending withdrawal request
     * @dev Re-stakes the cooldown amount back to active staking
     */
    function cancelWithdraw() external nonReentrant {
        StakerInfo storage staker = stakers[msg.sender];
        if (staker.cooldownAmount == 0) revert NoCooldownPending();

        // Update staker's pending yield
        _updateStakerYield(msg.sender);

        uint256 amount = staker.cooldownAmount;

        // Move back from cooldown to staked
        staker.cooldownAmount = 0;
        staker.cooldownEnd = 0;
        staker.stakedAmount += amount;
        staker.rewardDebt = (staker.stakedAmount * accYieldPerShare) / PRECISION;

        // Update totals
        totalInCooldown -= amount;
        totalStaked += amount;

        // Note: We can't cancel the unstake on DIEM contract directly
        // The DIEM will complete unstake, then we re-stake it
        // This is handled in the next deposit or by operator

        emit Deposited(msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            YIELD FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claim accumulated yield
     */
    function claimYield() external nonReentrant {
        _updateStakerYield(msg.sender);

        uint256 pending = stakers[msg.sender].pendingYield;
        if (pending == 0) revert NoYieldToClaim();

        stakers[msg.sender].pendingYield = 0;
        yieldToken.safeTransfer(msg.sender, pending);

        emit YieldClaimed(msg.sender, pending);
    }

    /*//////////////////////////////////////////////////////////////
                        YIELD DISTRIBUTION (OWNER)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Distribute yield from credit sales to the pool
     * @param amount Total yield amount in yield tokens
     * @dev Called by operator after receiving payment from credit buyers
     */
    function distributeYield(uint256 amount) external onlyOwner nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (totalStaked == 0) revert NoStakers();

        // Transfer yield tokens from operator to this contract
        yieldToken.safeTransferFrom(msg.sender, address(this), amount);

        // Calculate operator fee (5%)
        uint256 operatorFee = (amount * OPERATOR_FEE_BPS) / BPS_DENOMINATOR;
        uint256 stakerAmount = amount - operatorFee;

        // Add to operator's pending yield
        operatorPendingYield += operatorFee;

        // Update accumulated yield per share (only for actively staked, not cooldown)
        accYieldPerShare += (stakerAmount * PRECISION) / totalStaked;

        emit YieldDistributed(amount, stakerAmount, operatorFee);
    }

    /**
     * @notice Claim operator's accumulated fees
     */
    function claimOperatorYield() external onlyOwner nonReentrant {
        uint256 pending = operatorPendingYield;
        if (pending == 0) revert NoYieldToClaim();

        operatorPendingYield = 0;
        yieldToken.safeTransfer(owner(), pending);

        emit OperatorYieldClaimed(owner(), pending);
    }

    /*//////////////////////////////////////////////////////////////
                         OPERATOR MAINTENANCE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Re-stake any DIEM that completed unstake but wasn't withdrawn
     * @dev Handles edge cases where cancelWithdraw was called
     */
    function restakeUnstakedDiem() external onlyOwner nonReentrant {
        uint256 unstakedBalance = IERC20(address(DIEM)).balanceOf(address(this));
        if (unstakedBalance > 0) {
            DIEM.stake(unstakedBalance);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get staker's current staked amount
     * @param user Address of the staker
     * @return Amount of DIEM actively staked (earning yield)
     */
    function stakedAmount(address user) external view returns (uint256) {
        return stakers[user].stakedAmount;
    }

    /**
     * @notice Get staker's pending yield (including not-yet-updated)
     * @param user Address of the staker
     * @return Total pending yield
     */
    function pendingYield(address user) external view returns (uint256) {
        StakerInfo storage staker = stakers[user];

        uint256 accumulatedYield = (staker.stakedAmount * accYieldPerShare) / PRECISION;
        uint256 pendingFromAcc = 0;

        if (accumulatedYield > staker.rewardDebt) {
            pendingFromAcc = accumulatedYield - staker.rewardDebt;
        }

        return staker.pendingYield + pendingFromAcc;
    }

    /**
     * @notice Get staker's withdrawal status
     * @param user Address of the staker
     * @return amount Amount in cooldown
     * @return cooldownEnd Timestamp when cooldown ends (0 if none)
     * @return canComplete Whether completeWithdraw can be called
     */
    function withdrawalStatus(address user)
        external
        view
        returns (uint256 amount, uint256 cooldownEnd, bool canComplete)
    {
        StakerInfo storage staker = stakers[user];
        amount = staker.cooldownAmount;
        cooldownEnd = staker.cooldownEnd;
        canComplete = amount > 0 && block.timestamp >= cooldownEnd;
    }

    /**
     * @notice Get pool statistics
     * @return _totalStaked Total DIEM actively staked
     * @return _totalInCooldown Total DIEM in cooldown
     * @return _accYieldPerShare Accumulated yield per share
     * @return _operatorPendingYield Pending yield for operator
     */
    function getPoolStats()
        external
        view
        returns (
            uint256 _totalStaked,
            uint256 _totalInCooldown,
            uint256 _accYieldPerShare,
            uint256 _operatorPendingYield
        )
    {
        return (totalStaked, totalInCooldown, accYieldPerShare, operatorPendingYield);
    }

    /**
     * @notice Get the cooldown duration from DIEM contract
     */
    function getCooldownDuration() external view returns (uint256) {
        return DIEM.cooldownDuration();
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update a staker's pending yield based on accumulated yield
     * @param user Address of the staker
     */
    function _updateStakerYield(address user) internal {
        StakerInfo storage staker = stakers[user];

        if (staker.stakedAmount > 0) {
            uint256 accumulatedYield = (staker.stakedAmount * accYieldPerShare) / PRECISION;
            if (accumulatedYield > staker.rewardDebt) {
                staker.pendingYield += accumulatedYield - staker.rewardDebt;
            }
        }

        staker.rewardDebt = (staker.stakedAmount * accYieldPerShare) / PRECISION;
    }

    /*//////////////////////////////////////////////////////////////
                         EMERGENCY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Pause the contract (prevents new deposits)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Emergency withdrawal (only when paused)
     * @dev Forfeits pending yield. Only withdraws what's available in pool.
     */
    function emergencyWithdraw() external whenPaused nonReentrant {
        StakerInfo storage staker = stakers[msg.sender];
        uint256 totalUserDiem = staker.stakedAmount + staker.cooldownAmount;

        if (totalUserDiem == 0) revert ZeroAmount();

        // Update totals
        totalStaked -= staker.stakedAmount;
        totalInCooldown -= staker.cooldownAmount;

        // Reset staker info (pending yield is forfeited in emergency)
        staker.stakedAmount = 0;
        staker.cooldownAmount = 0;
        staker.cooldownEnd = 0;
        staker.rewardDebt = 0;
        staker.pendingYield = 0;

        // Transfer available DIEM balance to user
        // Note: Some DIEM may still be staked in DIEM contract
        uint256 available = IERC20(address(DIEM)).balanceOf(address(this));
        uint256 toTransfer = totalUserDiem > available ? available : totalUserDiem;

        if (toTransfer > 0) {
            IERC20(address(DIEM)).safeTransfer(msg.sender, toTransfer);
        }

        emit EmergencyWithdraw(msg.sender, toTransfer);
    }
}
