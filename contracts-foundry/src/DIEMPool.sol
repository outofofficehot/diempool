// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DIEMPool
 * @author DIEMpool Team
 * @notice A non-custodial staking pool for DIEM tokens that enables yield generation
 *         from AI inference credit sales.
 *
 * @dev Architecture:
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

    /// @notice The DIEM token contract
    IERC20 public immutable diemToken;

    /// @notice The token used for yield payments (e.g., USDC)
    IERC20 public immutable yieldToken;

    /// @notice Total DIEM staked in the pool
    uint256 public totalStaked;

    /// @notice Accumulated yield per staked DIEM (scaled by PRECISION)
    uint256 public accYieldPerShare;

    /// @notice Pending yield for operator
    uint256 public operatorPendingYield;

    /// @notice Staker info
    struct StakerInfo {
        uint256 amount; // Amount of DIEM staked
        uint256 rewardDebt; // Reward debt for yield calculation
        uint256 pendingYield; // Unclaimed yield
    }

    /// @notice Mapping of staker address to their info
    mapping(address => StakerInfo) public stakers;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
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
    error NoYieldToClaim();
    error NoStakers();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the DIEMPool
     * @param _diemToken Address of the DIEM token
     * @param _yieldToken Address of the yield token (e.g., USDC)
     * @param _owner Address of the operator/owner
     */
    constructor(address _diemToken, address _yieldToken, address _owner) Ownable(_owner) {
        if (_diemToken == address(0)) revert ZeroAddress();
        if (_yieldToken == address(0)) revert ZeroAddress();

        diemToken = IERC20(_diemToken);
        yieldToken = IERC20(_yieldToken);
    }

    /*//////////////////////////////////////////////////////////////
                            STAKING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Stake DIEM tokens to the pool
     * @param amount Amount of DIEM to stake
     */
    function stake(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();

        // Update staker's pending yield before changing their stake
        _updateStakerYield(msg.sender);

        // Transfer DIEM from staker to this contract
        diemToken.safeTransferFrom(msg.sender, address(this), amount);

        // Update staker info
        StakerInfo storage staker = stakers[msg.sender];
        staker.amount += amount;
        staker.rewardDebt = (staker.amount * accYieldPerShare) / PRECISION;

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
        if (amount == 0) revert ZeroAmount();
        if (staker.amount < amount) revert InsufficientStake();

        // Update staker's pending yield before changing their stake
        _updateStakerYield(msg.sender);

        // Update staker info
        staker.amount -= amount;
        staker.rewardDebt = (staker.amount * accYieldPerShare) / PRECISION;

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
        if (pending == 0) revert NoYieldToClaim();

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

        // Update accumulated yield per share
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
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get staker's current staked amount
     * @param user Address of the staker
     * @return Amount of DIEM staked
     */
    function stakedAmount(address user) external view returns (uint256) {
        return stakers[user].amount;
    }

    /**
     * @notice Get staker's pending yield (including not-yet-updated)
     * @param user Address of the staker
     * @return Total pending yield
     */
    function pendingYield(address user) external view returns (uint256) {
        StakerInfo storage staker = stakers[user];

        uint256 accumulatedYield = (staker.amount * accYieldPerShare) / PRECISION;
        uint256 pendingFromAcc = 0;

        if (accumulatedYield > staker.rewardDebt) {
            pendingFromAcc = accumulatedYield - staker.rewardDebt;
        }

        return staker.pendingYield + pendingFromAcc;
    }

    /**
     * @notice Get pool statistics
     * @return _totalStaked Total DIEM staked
     * @return _accYieldPerShare Accumulated yield per share
     * @return _operatorPendingYield Pending yield for operator
     */
    function getPoolStats()
        external
        view
        returns (uint256 _totalStaked, uint256 _accYieldPerShare, uint256 _operatorPendingYield)
    {
        return (totalStaked, accYieldPerShare, operatorPendingYield);
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

        if (staker.amount > 0) {
            uint256 accumulatedYield = (staker.amount * accYieldPerShare) / PRECISION;
            if (accumulatedYield > staker.rewardDebt) {
                staker.pendingYield += accumulatedYield - staker.rewardDebt;
            }
        }

        staker.rewardDebt = (staker.amount * accYieldPerShare) / PRECISION;
    }

    /*//////////////////////////////////////////////////////////////
                         EMERGENCY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

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
     * @dev Only callable when paused, doesn't update yield (forfeits pending yield)
     */
    function emergencyWithdraw() external whenPaused nonReentrant {
        StakerInfo storage staker = stakers[msg.sender];
        uint256 amount = staker.amount;

        if (amount == 0) revert ZeroAmount();

        // Reset staker info (pending yield is forfeited in emergency)
        staker.amount = 0;
        staker.rewardDebt = 0;
        staker.pendingYield = 0;

        totalStaked -= amount;

        diemToken.safeTransfer(msg.sender, amount);

        emit EmergencyWithdraw(msg.sender, amount);
    }
}
