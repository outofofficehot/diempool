// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DIEMPool
 * @notice A staking pool for DIEM tokens that enables yield generation from AI inference credit sales.
 * 
 * Architecture:
 * - Stakers deposit DIEM tokens to this contract
 * - The pooled DIEM is associated with the operator's Venice account (off-chain)
 * - Buyers pay for inference credits (off-chain), revenue flows to this contract
 * - 95% of revenue goes to stakers proportionally, 5% to the operator
 * - Stakers can withdraw their DIEM at any time (no lockup)
 * 
 * Security Model:
 * - Non-custodial: Only the original staker can withdraw their DIEM
 * - Operator cannot withdraw staked DIEM, only their fee share
 * - All staker accounting is on-chain and verifiable
 */
contract DIEMPool is ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    // ============================================
    // Constants
    // ============================================

    /// @notice Fee percentage taken by operator (5%)
    uint256 public constant OPERATOR_FEE_BPS = 500; // 5% = 500 basis points
    uint256 public constant BPS_DENOMINATOR = 10000;

    // ============================================
    // State Variables
    // ============================================

    /// @notice The DIEM token contract
    IERC20 public immutable diemToken;

    /// @notice The token used for yield payments (e.g., USDC)
    IERC20 public immutable yieldToken;

    /// @notice Total DIEM staked in the pool
    uint256 public totalStaked;

    /// @notice Accumulated yield per staked DIEM (scaled by 1e18)
    uint256 public accYieldPerShare;

    /// @notice Pending yield for operator
    uint256 public operatorPendingYield;

    /// @notice Staker info
    struct StakerInfo {
        uint256 amount;        // Amount of DIEM staked
        uint256 rewardDebt;    // Reward debt for yield calculation
        uint256 pendingYield;  // Unclaimed yield
    }

    /// @notice Mapping of staker address to their info
    mapping(address => StakerInfo) public stakers;

    // ============================================
    // Events
    // ============================================

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event YieldDistributed(uint256 totalAmount, uint256 stakerAmount, uint256 operatorAmount);
    event YieldClaimed(address indexed user, uint256 amount);
    event OperatorYieldClaimed(address indexed operator, uint256 amount);

    // ============================================
    // Constructor
    // ============================================

    /**
     * @notice Initialize the DIEMPool
     * @param _diemToken Address of the DIEM token
     * @param _yieldToken Address of the yield token (e.g., USDC)
     * @param _owner Address of the operator/owner
     */
    constructor(
        address _diemToken,
        address _yieldToken,
        address _owner
    ) Ownable(_owner) {
        require(_diemToken != address(0), "Invalid DIEM token");
        require(_yieldToken != address(0), "Invalid yield token");
        
        diemToken = IERC20(_diemToken);
        yieldToken = IERC20(_yieldToken);
    }

    // ============================================
    // Staking Functions
    // ============================================

    /**
     * @notice Stake DIEM tokens to the pool
     * @param amount Amount of DIEM to stake
     */
    function stake(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Cannot stake 0");

        // Update staker's pending yield before changing their stake
        _updateStakerYield(msg.sender);

        // Transfer DIEM from staker to this contract
        diemToken.safeTransferFrom(msg.sender, address(this), amount);

        // Update staker info
        stakers[msg.sender].amount += amount;
        stakers[msg.sender].rewardDebt = (stakers[msg.sender].amount * accYieldPerShare) / 1e18;

        // Update total staked
        totalStaked += amount;

        emit Staked(msg.sender, amount);
    }

    /**
     * @notice Unstake DIEM tokens from the pool
     * @param amount Amount of DIEM to unstake
     */
    function unstake(uint256 amount) external nonReentrant {
        StakerInfo storage staker = stakers[msg.sender];
        require(staker.amount >= amount, "Insufficient staked amount");
        require(amount > 0, "Cannot unstake 0");

        // Update staker's pending yield before changing their stake
        _updateStakerYield(msg.sender);

        // Update staker info
        staker.amount -= amount;
        staker.rewardDebt = (staker.amount * accYieldPerShare) / 1e18;

        // Update total staked
        totalStaked -= amount;

        // Transfer DIEM back to staker
        diemToken.safeTransfer(msg.sender, amount);

        emit Unstaked(msg.sender, amount);
    }

    /**
     * @notice Claim accumulated yield
     */
    function claimYield() external nonReentrant {
        _updateStakerYield(msg.sender);

        uint256 pending = stakers[msg.sender].pendingYield;
        require(pending > 0, "No yield to claim");

        stakers[msg.sender].pendingYield = 0;
        yieldToken.safeTransfer(msg.sender, pending);

        emit YieldClaimed(msg.sender, pending);
    }

    /**
     * @notice Unstake all DIEM and claim all pending yield
     */
    function exit() external nonReentrant {
        StakerInfo storage staker = stakers[msg.sender];
        
        _updateStakerYield(msg.sender);

        uint256 stakedAmount = staker.amount;
        uint256 pendingYield = staker.pendingYield;

        // Reset staker info
        staker.amount = 0;
        staker.rewardDebt = 0;
        staker.pendingYield = 0;

        // Update total staked
        totalStaked -= stakedAmount;

        // Transfer tokens
        if (stakedAmount > 0) {
            diemToken.safeTransfer(msg.sender, stakedAmount);
            emit Unstaked(msg.sender, stakedAmount);
        }
        
        if (pendingYield > 0) {
            yieldToken.safeTransfer(msg.sender, pendingYield);
            emit YieldClaimed(msg.sender, pendingYield);
        }
    }

    // ============================================
    // Yield Distribution (Operator Only)
    // ============================================

    /**
     * @notice Distribute yield from credit sales to the pool
     * @param amount Total yield amount in yield tokens
     * @dev Called by operator after receiving payment from credit buyers
     */
    function distributeYield(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "Cannot distribute 0");
        require(totalStaked > 0, "No stakers in pool");

        // Transfer yield tokens from operator to this contract
        yieldToken.safeTransferFrom(msg.sender, address(this), amount);

        // Calculate operator fee (5%)
        uint256 operatorFee = (amount * OPERATOR_FEE_BPS) / BPS_DENOMINATOR;
        uint256 stakerAmount = amount - operatorFee;

        // Add to operator's pending yield
        operatorPendingYield += operatorFee;

        // Update accumulated yield per share
        accYieldPerShare += (stakerAmount * 1e18) / totalStaked;

        emit YieldDistributed(amount, stakerAmount, operatorFee);
    }

    /**
     * @notice Claim operator's accumulated fees
     */
    function claimOperatorYield() external onlyOwner nonReentrant {
        uint256 pending = operatorPendingYield;
        require(pending > 0, "No operator yield to claim");

        operatorPendingYield = 0;
        yieldToken.safeTransfer(owner(), pending);

        emit OperatorYieldClaimed(owner(), pending);
    }

    // ============================================
    // View Functions
    // ============================================

    /**
     * @notice Get staker's current staked amount
     */
    function stakedAmount(address user) external view returns (uint256) {
        return stakers[user].amount;
    }

    /**
     * @notice Get staker's pending yield (including not-yet-updated)
     */
    function pendingYield(address user) external view returns (uint256) {
        StakerInfo storage staker = stakers[user];
        
        uint256 accumulatedYield = (staker.amount * accYieldPerShare) / 1e18;
        uint256 pendingFromAcc = 0;
        
        if (accumulatedYield > staker.rewardDebt) {
            pendingFromAcc = accumulatedYield - staker.rewardDebt;
        }
        
        return staker.pendingYield + pendingFromAcc;
    }

    /**
     * @notice Get pool statistics
     */
    function getPoolStats() external view returns (
        uint256 _totalStaked,
        uint256 _accYieldPerShare,
        uint256 _operatorPendingYield,
        uint256 _stakerCount
    ) {
        return (
            totalStaked,
            accYieldPerShare,
            operatorPendingYield,
            0 // Note: Would need to track staker count separately if needed
        );
    }

    /**
     * @notice Estimate daily yield for a given stake amount
     * @param amount Amount of DIEM to simulate
     * @param utilizationBps Expected utilization in basis points (e.g., 7000 = 70%)
     * @return Estimated daily yield in yield tokens
     * @dev This is a helper for UI - assumes $1/day per DIEM at full utilization
     */
    function estimateDailyYield(uint256 amount, uint256 utilizationBps) external pure returns (uint256) {
        // Assuming yield token has 6 decimals (USDC)
        // $1/day per DIEM at 100% utilization, scaled by actual utilization
        // Then subtract 5% operator fee
        uint256 grossYield = (amount * utilizationBps * 1e6) / BPS_DENOMINATOR; // $1 per DIEM * utilization
        uint256 netYield = (grossYield * (BPS_DENOMINATOR - OPERATOR_FEE_BPS)) / BPS_DENOMINATOR;
        return netYield;
    }

    // ============================================
    // Internal Functions
    // ============================================

    /**
     * @notice Update a staker's pending yield based on accumulated yield
     */
    function _updateStakerYield(address user) internal {
        StakerInfo storage staker = stakers[user];
        
        if (staker.amount > 0) {
            uint256 accumulatedYield = (staker.amount * accYieldPerShare) / 1e18;
            if (accumulatedYield > staker.rewardDebt) {
                staker.pendingYield += accumulatedYield - staker.rewardDebt;
            }
        }
        
        staker.rewardDebt = (staker.amount * accYieldPerShare) / 1e18;
    }

    // ============================================
    // Emergency Functions
    // ============================================

    /**
     * @notice Pause the contract (prevents new stakes)
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
     * @notice Emergency withdrawal for a staker if contract is paused
     * @dev Only callable when paused, doesn't update yield
     */
    function emergencyWithdraw() external whenPaused nonReentrant {
        StakerInfo storage staker = stakers[msg.sender];
        uint256 amount = staker.amount;
        
        require(amount > 0, "Nothing to withdraw");
        
        staker.amount = 0;
        staker.rewardDebt = 0;
        // Note: pending yield is forfeited in emergency
        staker.pendingYield = 0;
        
        totalStaked -= amount;
        
        diemToken.safeTransfer(msg.sender, amount);
        
        emit Unstaked(msg.sender, amount);
    }
}
